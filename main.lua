local _ = require("fan_i18n").t
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local State = {}
local Fanfic = WidgetContainer:extend{ name = "fan", is_doc_only = false }

function Fanfic:init()
    if not State.settings then
        local settings_path = DataStorage:getSettingsDir() .. "/fan.lua"
        local old_path = DataStorage:getSettingsDir() .. "/fanficfire.lua"
        local source = LuaSettings:open(settings_path)
        if not lfs.attributes(settings_path, "mode") and lfs.attributes(old_path, "mode") then
            source = LuaSettings:open(old_path)
        end
        State.settings = LuaSettings:open(settings_path)
        local saved = source:readSetting("config", {})
        State.config = {}
        for _, key in ipairs({ "author_styles", "adult", "auto_next", "last_url", "current_url" }) do
            State.config[key] = saved[key]
        end
        State.library = source:readSetting("library", {})
        State.documents = source:readSetting("documents", {})
    end
    self.settings, self.config = State.settings, State.config
    self.library, self.documents = State.library, State.documents
    self.storage = DataStorage:getFullDataDir() .. "/fan"
    local old_storage = DataStorage:getFullDataDir() .. "/fanficfire"
    if not lfs.attributes(self.storage, "mode") and lfs.attributes(old_storage, "mode") then self.storage = old_storage end
    self.plugin_dir = lfs.currentdir() .. "/" .. self.path
    if self.path:sub(1, 1) == "/" then self.plugin_dir = self.path end
    self.Client = dofile(self.plugin_dir .. "/client.lua")
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:hookChapterEnd()
end

function Fanfic:hookChapterEnd()
    if not self.ui.status then return end
    local original = self.ui.status.onEndOfBook
    self.ui.status.onEndOfBook = function(status, ...)
        local file = self.ui.document and self.ui.document.file
        local doc = file and self.documents[file]
        local story = doc and self.library[doc.url]
        if self.config.auto_next ~= false and story and doc.index < #story.chapters then
            if not self.turning_chapter then
                self.turning_chapter = true
                UIManager:nextTick(function()
                    self:readChapter(story, doc.index + 1)
                    self.turning_chapter = false
                end)
            end
            return true
        end
        return original(status, ...)
    end
end

function Fanfic:onDispatcherRegisterActions()
    Dispatcher:registerAction("fan_open", { category = "none", event = "FanficOpen", title = _("fan.koplugin: open story"), general = true })
    Dispatcher:registerAction("fan_next", { category = "none", event = "FanficNext", title = _("fan.koplugin: next chapter"), general = true })
    Dispatcher:registerAction("fan_previous", { category = "none", event = "FanficPrevious", title = _("fan.koplugin: previous chapter"), general = true })
end

function Fanfic:save()
    self.settings:saveSetting("config", self.config)
    self.settings:saveSetting("library", self.library)
    self.settings:saveSetting("documents", self.documents)
    self.settings:flush()
end

function Fanfic:onFlushSettings() self:save() end

function Fanfic:client()
    return self.Client.new{
        native_options = { styles = self.config.author_styles ~= false, adult = self.config.adult == true },
        progress = require("fan_progress").writer(self.progress_path),
        data = self.storage .. "/engine", cache = self.storage .. "/books",
    }
end

function Fanfic:message(text)
    UIManager:show(InfoMessage:new{ text = tostring(text) })
end

function Fanfic:text(title, text)
    UIManager:show(TextViewer:new{ title = title, text = text })
end

function Fanfic:input(title, value, callback, multiline, password)
    local dialog
    dialog = InputDialog:new{
        title = title, input = value or "", text_type = password and "password" or nil,
        text_height = multiline and 360 or nil, allow_newline = multiline or false,
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            { text = "OK", is_enter_default = true, callback = function()
                local answer = dialog:getInputText()
                UIManager:close(dialog)
                callback(answer)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Fanfic:menu(title, rows)
    local menu
    local items = {}
    for _, row in ipairs(rows) do
        local callback = row.callback
        items[#items + 1] = {
            text = row.text, enabled = row.enabled,
            callback = function()
                UIManager:close(menu)
                if callback then callback() end
            end,
        }
    end
    menu = Menu:new{ title = title, item_table = items, is_enable_shortcut = false,
        close_callback = function() UIManager:close(menu) end }
    UIManager:show(menu)
end

function Fanfic:work(label, operation, callback, offline)
    local function run()
        Trapper:wrap(function()
            require("util").makePath(self.storage)
            local path=self.storage.."/progress-"..os.time().."-"..math.random(100000,999999)..".json"
            local dialog=require("fan_progress").window(label,path)
            local launched,completed,result=pcall(function()
                return Trapper:dismissableRunInSubprocess(function()
                    self.progress_path=path
                    local ok, value = pcall(operation)
                    self.progress_path=nil
                    return { ok = ok, value = ok and value or tostring(value) }
                end, dialog)
            end)
            dialog:stopProgress()
            if not launched then self:text(_("Engine error"),tostring(completed)); return end
            if not completed then return end
            if not result or not result.ok then
                self:text(_("Engine error"), result and result.value or _("Operation interrupted"))
                return
            end
            callback(result.value)
        end)
    end
    if offline then run() else NetworkMgr:runWhenConnected(run) end
end

function Fanfic:request(req, callback, offline)
    self:work(_("Working…"), function() return self:client():request(req) end, callback, offline)
end

function Fanfic:addToMainMenu(items)
    items.fan = { text = "fan.koplugin", sorting_hint = "more_tools",
        callback = function() self:showHome() end }
end

function Fanfic:showHome()
    self:menu("fan.koplugin", {
        { text = _("Open story URL"), callback = function() self:onFanficOpen() end },
        { text = _("My library / read offline"), callback = function() self:showLibrary() end },
        { text = _("Current story / chapters"), callback = function() self:currentStory() end },
        { text = _("Next chapter"), callback = function() self:onFanficNext() end },
        { text = _("Previous chapter"), callback = function() self:onFanficPrevious() end },
        { text = _("Find stories on a web page"), callback = function() self:discover() end },
        { text = _("Download multiple URLs"), callback = function() self:batch() end },
        { text = _("Supported sites"), callback = function() self:sites() end },
        { text = _("Settings"), callback = function() self:showSettings() end },
    })
end

function Fanfic:onFanficOpen()
    self:input(_("Story URL"), self.config.last_url, function(url) self:loadStory(url) end)
    return true
end

function Fanfic:loadStory(url)
    url = url:match("^%s*(.-)%s*$")
    self.config.last_url = url
    self:request({ action = "metadata", url = url }, function(story)
        local previous = self.library[story.url]
        story.last_index = story.start_index or previous and previous.last_index or 1
        story.cached = {}
        if previous then
            local by_url = {}
            for i, chapter in ipairs(previous.chapters or {}) do by_url[chapter.url] = (previous.cached or {})[tostring(i)] end
            for i, chapter in ipairs(story.chapters) do story.cached[tostring(i)] = by_url[chapter.url] end
            story.last_index = math.min(story.last_index, #story.chapters)
        end
        story.book = previous and previous.book
        self.library[story.url] = story
        self.config.current_url = story.url
        self:save()
        self:showStory(story)
    end)
end

function Fanfic:showLibrary()
    local stories, rows = {}, {}
    for _, story in pairs(self.library) do stories[#stories + 1] = story end
    table.sort(stories, function(a, b) return (a.title or a.url) < (b.title or b.url) end)
    for _, story in ipairs(stories) do
        rows[#rows + 1] = { text = story.title .. " — " .. (story.author or ""),
            callback = function() self:showStory(story) end }
    end
    if #rows == 0 then self:message(_("Your library is empty. Open a story URL.")); return end
    self:menu(_("Library"), rows)
end

function Fanfic:showStory(story)
    self.config.current_url = story.url
    self:save()
    self:menu(story.title or story.url, {
        { text = _("Continue at chapter ") .. (story.last_index or 1), callback = function() self:readChapter(story, story.last_index or 1) end },
        { text = _("Open downloaded book"), enabled = story.book ~= nil, callback = function()
            local path = story.book and self:client():cached(story.book.artifact, story.book.size)
            if path then self:openFile(path)
            elseif not lfs.attributes(self.storage.."/engine/"..story.book.artifact,"mode") then
                self:download(story,"download")
            else
                self:work(_("Retrieving file"),function() return self:client():fetch(story.book,true) end,
                    function(file) self:openFile(file) end,true)
            end
        end },
        { text = _("Chapters (") .. #story.chapters .. ")", callback = function() self:showChapters(story) end },
        { text = _("Story details"), callback = function() self:text(story.title, JSON.encode(story.metadata)) end },
        { text = _("Refresh chapters from website"), callback = function() self:loadStory(story.url) end },
        { text = _("Download complete book"), callback = function() self:download(story, "download") end },
        { text = _("Download chapter range"), callback = function() self:range(story) end },
        { text = _("Update EPUB: new chapters"), callback = function() self:download(story, "update") end },
        { text = _("Update EPUB even without new chapters"), callback = function() self:download(story, "update", "epub", { always = true }) end },
    })
end

function Fanfic:showChapters(story)
    local rows = {}
    for i, chapter in ipairs(story.chapters) do
        rows[#rows + 1] = { text = i .. ". " .. chapter.title .. (story.cached[tostring(i)] and " ✓" or ""),
            callback = function() self:chapterActions(story, i) end }
    end
    self:menu(story.title, rows)
end

function Fanfic:chapterActions(story, index)
    self:menu(story.chapters[index].title, {
        { text = _("Read"), callback = function() self:readChapter(story, index) end },
        { text = _("Download again"), callback = function() self:readChapter(story, index, true) end },
    })
end

function Fanfic:openFile(path)
    UIManager:nextTick(function()
        if self.ui.document then self.ui:switchDocument(path) else self.ui:openFile(path) end
    end)
end

function Fanfic:readChapter(story, index, refresh)
    if index < 1 or index > #story.chapters then self:message(_("No more chapters. Refresh the chapter list to check the website.")); return end
    local function open(path)
        story.last_index = index
        self.config.current_url = story.url
        self.documents[path] = { url = story.url, index = index }
        self:save()
        self:openFile(path)
    end
    local cached = story.cached[tostring(index)]
    if cached and not refresh then
        local path = self:client():cached(cached.artifact, cached.size)
        if path then open(path); return end
    end
    self:work(_("Downloading chapter ") .. index, function()
        local client = self:client()
        local result = client:request{ action = "chapter", url = story.url, index = index, refresh = refresh }
        return { file = client:fetch(result, refresh), artifact = result }
    end, function(result)
        story.cached[tostring(index)] = result.artifact
        open(result.file)
        if result.artifact.warnings and #result.artifact.warnings > 0 then
            UIManager:nextTick(function() self:text(_("Some resources could not be downloaded"), table.concat(result.artifact.warnings, "\n\n")) end)
        end
    end)
end

function Fanfic:active()
    local file = self.ui.document and self.ui.document.file
    local doc = file and self.documents[file]
    if doc and self.library[doc.url] then return self.library[doc.url], doc.index end
    local story = self.library[self.config.current_url or ""]
    return story, story and story.last_index or 1
end

function Fanfic:currentStory()
    local story = self:active()
    if story then self:showStory(story) else self:message(_("Open a story first.")) end
end

function Fanfic:onFanficNext()
    local story, index = self:active()
    if story then self:readChapter(story, index + 1) else self:message(_("Open a story first.")) end
    return true
end

function Fanfic:onFanficPrevious()
    local story, index = self:active()
    if story then self:readChapter(story, index - 1) else self:message(_("Open a story first.")) end
    return true
end

function Fanfic:range(story)
    self:input(_("Chapter range, for example 1-10"), "1-" .. #story.chapters, function(text)
        local first, last = text:match("^(%d+)%s*%-%s*(%d+)$")
        first, last = tonumber(first), tonumber(last)
        if not first or first < 1 or last < first or last > #story.chapters then self:message(_("Invalid chapter range")); return end
        self:download(story, "download", "epub", { begin = first, ["end"] = last })
    end)
end

function Fanfic:download(story, action, format, extra)
    local request = extra or {}
    request.action, request.url, request.format = action, story.url, format or "epub"
    self:work(_("Downloading book"), function()
        local client = self:client()
        local artifact = client:request(request)
        return { file = client:fetch(artifact, true), artifact = artifact }
    end, function(result)
        if not request.begin and not request["end"] then story.book = result.artifact; self:save() end
        self:menu(_("Book saved"), {
            { text = _("Read"), callback = function() self:openFile(result.file) end },
            { text = _("Some resources could not be downloaded"), enabled = result.artifact.warnings and #result.artifact.warnings > 0,
                callback = function() self:text(_("Some resources could not be downloaded"), table.concat(result.artifact.warnings or {}, "\n\n")) end },
            { text = _("File location"), callback = function() self:message(result.file) end },
        })
    end)
end

function Fanfic:discover()
    self:input(_("Author, series or list page URL"), "", function(url)
        self:request({ action = "list", url = url }, function(result)
            local rows = {}
            for _, found in ipairs(result.urllist or {}) do
                rows[#rows + 1] = { text = found, callback = function() self:loadStory(found) end }
            end
            if #rows == 0 then self:message(_("No story URLs found")) else self:menu(_("Stories found"), rows) end
        end)
    end)
end

function Fanfic:batch()
    self:input(_("URLs, one per line"), "", function(text)
        self:work(_("Downloading stories"), function()
            local client, results = self:client(), {}
            for url in text:gmatch("[^\r\n]+") do
                url = url:match("^%s*(.-)%s*$")
                if url ~= "" then
                    local ok, value = pcall(function()
                        local result = client:request{ action = "download", url = url }
                        return client:fetch(result, true)
                    end)
                    results[#results + 1] = url .. "\n" .. (ok and value or tostring(value))
                end
            end
            return table.concat(results, "\n\n")
        end, function(result) self:text(_("Download results"), result) end)
    end, true)
end

function Fanfic:sites()
    self:request({ action = "sites" }, function(result)
        local rows = {}
        for _, site in ipairs(result.sites) do
            rows[#rows + 1] = { text = site.site, callback = function()
                local examples = type(site.examples) == "table" and table.concat(site.examples, "\n") or site.examples
                self:text(site.site, examples)
            end }
        end
        self:menu(_("fan.koplugin sites"), rows)
    end, true)
end

function Fanfic:showSettings()
    self:menu(_("fan.koplugin settings"), {
        { text = _("Author styles: ") .. (self.config.author_styles == false and _("no") or _("yes")), callback = function()
            self.config.author_styles = self.config.author_styles == false
            for _, story in pairs(self.library) do story.cached = {} end
            self:save()
        end },
        { text = _("Allow adult content: ") .. (self.config.adult == true and _("yes") or _("no")), callback = function()
            self.config.adult = not self.config.adult; self:save()
        end },
        { text = _("Automatically open next chapter: ") .. (self.config.auto_next == false and _("no") or _("yes")), callback = function()
            self.config.auto_next = self.config.auto_next == false
            self:save()
        end },
        { text = _("Check engine"), callback = function()
            self:request({ action = "status" }, function(result) self:text(_("Engine versions"), JSON.encode(result)) end, true)
        end },
        { text = _("Test website connection"), callback = function()
            self:input(_("Story URL"),self.config.last_url or "https://ficbook.net/readfic/11801484",function(url)
                self:request({action="diagnose",url=url},function(result)
                    self:text(_("Connection diagnostics"),result.text)
                end)
            end)
        end },
        { text = _("Import cookies.txt from device"), callback = function()
            self:input(_("Absolute path to cookies.txt"), "/mnt/us/cookies.txt", function(path)
                local file = io.open(path, "rb")
                if not file then self:message(_("Could not open file")); return end
                local text = file:read(1048577)
                file:close()
                if #text > 1048576 then self:message(_("File exceeds 1 MiB")); return end
                self:request({ action = "set_cookies", text = text }, function() self:message(_("Cookies imported")) end, true)
            end)
        end },
        { text = _("Book storage folder"), callback = function() self:message(self.storage .. "/books") end },
    })
end

return Fanfic
