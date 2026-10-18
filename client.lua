local _ = require("fan_i18n").t
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Client = {}
Client.__index = Client

local function mkdir(path)
    assert(util.makePath(path) or lfs.attributes(path, "mode") == "directory", _("Cannot create ") .. path)
end

local function artifactPath(value)
    assert(type(value) == "string" and value:match("^[%w_/%.-]+$")
        and not value:find("..", 1, true) and value:sub(1, 1) ~= "/", _("Invalid artifact path"))
    assert(value:match("^stories/"), _("Invalid artifact root"))
    return value
end

function Client.new(options)
    local self = setmetatable(options, Client)
    mkdir(self.data)
    mkdir(self.cache)
    return self
end

function Client:request(req)
    return require("fan_native").new(self):request(req)
end

function Client:cached(artifact, size)
    local path = self.cache .. "/" .. artifactPath(artifact)
    local attrs = lfs.attributes(path)
    if attrs and attrs.mode == "file" and attrs.size > 0 and (not size or attrs.size == size) then
        return path
    end
end

function Client:fetch(result, refresh)
    if self.progress then self.progress{stage="Saving EPUB…",bytes=0} end
    local relative = artifactPath(result.artifact)
    if not refresh then
        local cached = self:cached(relative, result.size)
        if cached then return cached end
    end
    local target = self.cache .. "/" .. relative
    mkdir(target:match("^(.*)/[^/]+$"))
    local temporary = target .. ".part"
    local source = assert(io.open(self.data .. "/" .. relative, "rb"))
    local output = assert(io.open(temporary, "wb"))
    local ok, err = pcall(function()
        while true do
            local chunk = source:read(65536)
            if not chunk then break end
            assert(output:write(chunk))
        end
    end)
    source:close()
    local closed = output:close()
    if not ok or not closed then os.remove(temporary); error(err or _("Incomplete file download"), 0) end
    local size = lfs.attributes(temporary, "size")
    if not size or size == 0 or (result.size and size ~= result.size) then
        os.remove(temporary)
        error(_("Incomplete file download"))
    end
    require("fan_fs").replace(temporary, target)
    return target
end

return Client
