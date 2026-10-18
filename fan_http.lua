local URL = require("socket.url")
local socketutil = require("socketutil")
local _ = require("fan_i18n").t
local N = {}
N.__index=N
function N.normalize(url)
    url=type(url)=="string" and url:match("^%s*(.-)%s*$") or ""
    if url:sub(1,2)=="//" then url="https:"..url
    elseif not url:match("^[%a][%w+.-]*:") then url="https://"..url end
    local scheme=url:match("^([%a][%w+.-]*):")
    if scheme and (scheme:lower()=="http" or scheme:lower()=="https") then url="https"..url:sub(#scheme+1) end
    local p=URL.parse(url)
    if not p or p.scheme~="https" or not p.host or not p.host:find(".",1,true)
        or p.host:find("[%s<>]") or p.userinfo or p.user or p.password or url:find("[\r\n]") then
        error(_("Enter a website page URL, for example https://ficbook.net. This search finds story links on a page; it does not search by title."),0)
    end
    return (url:gsub("#.*$", ""))
end
function N.new(text,progress)
    local self=setmetatable({cookies={},history={},progress=progress or function() end},N)
    for line in (text or ""):gmatch("[^\r\n]+") do
        line=line:gsub("^#HttpOnly_","")
        if line:sub(1,1)~="#" then
            local domain,sub,path,secure,expires,name,value=line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
            if domain and not value:find("[\r\n]") then
                self.cookies[#self.cookies+1]={domain=domain:gsub("^%.",""):lower(),sub=sub=="TRUE",path=path,secure=secure=="TRUE",expires=tonumber(expires) or 0,name=name,value=value}
            end
        end
    end
    return self
end
function N:cookie(url)
    local p=URL.parse(url)
    local out={}
    for _,c in ipairs(self.cookies) do
        local domain=p.host==c.domain or (c.sub and p.host:sub(-#c.domain-1)=="."..c.domain)
        local path=p.path or "/"
        local matches=path==c.path or (path:sub(1,#c.path)==c.path and (c.path:sub(-1)=="/" or path:sub(#c.path+1,#c.path+1)=="/"))
        if domain and matches and (not c.secure or p.scheme=="https") and (c.expires==0 or c.expires>os.time()) then out[#out+1]=c.name.."="..c.value end
    end
    return table.concat(out,"; ")
end
function N:get(url,referer)
    for _redirect=1,6 do
        url=N.normalize(url)
        local a,code,headers,chunks,detail
        for attempt=1,3 do
            local size,started=0,os.time()
            local protocol=attempt==2 and "tlsv1_2" or "any"
            chunks={}
            self.progress{stage=attempt>1 and "Retrying connection…" or "Connecting to website…",url=url,bytes=0,attempt=attempt}
            local timeout=referer and 15 or 25
            socketutil:set_timeout(timeout,90)
            local ok
            ok,a,code,headers=pcall(function()
                return require("socket.http").request{
                    url=url, method="GET", redirect=false,protocol=protocol,
                    headers={ ["User-Agent"]=socketutil.USER_AGENT or "fan.koplugin/0.2 (KOReader)", ["Accept-Encoding"]="identity", Cookie=self:cookie(url), Referer=referer, Connection="close" },
                    sink=function(chunk,err)
                        if os.time()-started>90 then return nil,"timeout" end
                        if chunk then
                            size=size+#chunk
                            if size>32*1024*1024 then return nil,"Response exceeds 32 MiB" end
                            chunks[#chunks+1]=chunk
                            self.progress{stage=referer and "Downloading styles and images…" or "Downloading page…",url=url,bytes=size,attempt=attempt}
                        end
                        if err then return nil,err end
                        return 1
                    end,
                }
            end)
            socketutil:reset_timeout()
            detail=ok and code or a
            if not ok then a=nil end
            code=tonumber(code)
            local record=string.format("%s | TLS=%s | %ds | %d bytes | %s",URL.parse(url).host,
                protocol,os.time()-started,size,tostring(code or detail))
            self.history[#self.history+1]=record
            if #self.history>12 then table.remove(self.history,1) end
            local transient=detail=="wantread" or detail=="wantwrite" or detail=="timeout" or detail=="closed"
                or code==502 or code==503 or code==504
            if a and code==200 then return table.concat(chunks),headers or {},url end
            if not transient or attempt==3 or referer then break end
            require("socket").sleep(attempt)
        end
        if a and code and code>=300 and code<400 and headers and headers.location then
            url=URL.absolute(url,headers.location)
        else
            local message
            if detail=="wantread" or detail=="wantwrite" or detail=="timeout" then
                message=_("The website did not respond in time. Check Wi-Fi or try another network, then retry.").." ("..tostring(detail)..")"
            else message=_("Website request failed: ")..tostring(code or detail or a) end
            error(message.."\n"..url.."\n\n"..table.concat(self.history,"\n"),0)
        end
    end
    error(_("Too many redirects"),0)
end
function N:diagnose(url)
    local rows={"fan.koplugin HTTPS",jit and (jit.os.." / "..jit.arch) or _VERSION}
    for _,name in ipairs({"socket","ssl"}) do
        local ok,module=pcall(require,name)
        rows[#rows+1]=name..": "..tostring(ok and module._VERSION or "unavailable")
    end
    local ok,body=pcall(self.get,self,url)
    rows[#rows+1]=ok and ("HTTP 200; "..#body.." bytes") or tostring(body)
    if ok then for _,record in ipairs(self.history) do rows[#rows+1]=record end end
    return table.concat(rows,"\n")
end
return N
