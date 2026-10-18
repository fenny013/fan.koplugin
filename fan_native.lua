local H=require("fan_html")
local Z=require("fan_zip")
local N=require("fan_http")
local URL=require("socket.url")
local JSON=require("json")
local util=require("util")
local md5=require("ffi/sha2").md5
local _=require("fan_i18n").t
local FS=require("fan_fs")
local E={}
E.__index=E
local ao3_hosts={ ["archiveofourown.org"]=true,["archiveofourown.gay"]=true }
local function read(path)
    local f=io.open(path,"rb"); if not f then return end
    local s=f:read("*a"); f:close(); return s
end
local function write(path,s)
    local f=assert(io.open(path..".tmp","wb")); assert(f:write(s)); assert(f:close()); FS.replace(path..".tmp",path)
end
local function canonical(url)
    url=N.normalize(url)
    local p=URL.parse(url or "")
    assert(p and p.host,_ ("Invalid story URL"))
    local host=p.host:lower():gsub("^www%.","")
    local id
    if ao3_hosts[host] then id=(p.path or ""):match("/works/(%d+)"); if id then return "https://"..host.."/works/"..id,"ao3",id end end
    if host=="ficbook.net" then id=(p.path or ""):match("^/readfic/([%w%-]+)"); if id then return "https://ficbook.net/readfic/"..id,"ficbook",id end end
    error(_("Native engine supports AO3 work URLs and Ficbook story URLs"),0)
end
function E.new(options)
    local progress=options.progress or function() end
    return setmetatable({data=options.data,pages={}, options=options.native_options or {},progress=progress, net=N.new(read(options.data.."/cookies.txt"),progress)},E)
end
function E:page(url)
    url=N.normalize(url)
    local host=(URL.parse(url).host or ""):lower():gsub("^www%.","")
    if self.options.adult and ao3_hosts[host] then url=url..(url:find("?",1,true) and "&" or "?").."view_adult=true" end
    if self.pages[url] then return H.parse(self.pages[url].raw),self.pages[url].url end
    local raw,headers,final=self.net:get(url)
    local doc=H.parse(raw)
    if (H.id(doc,"adultCoverWarning") and not self.options.adult) or raw:find("This work could have adult content",1,true) then
        error(_("Adult content confirmation is required on the website; import your cookies and enable adult content in Settings"),0)
    end
    if raw:find("Just a moment...",1,true) or raw:find("cf-chl-",1,true) then error(_("Website protection blocked access. Open the website in a browser."),0) end
    self.pages={[url]={raw=raw,url=final or url}}
    return doc,final or url
end
function E:metadata(url)
    self.progress{stage="Loading chapter list…",done=0,bytes=0}
    local canonical_url,site,id=canonical(url)
    local doc=self:page(canonical_url)
    local title,author,chapters=nil,nil,{}
    if site=="ao3" then
        title=H.first(doc,function(n) return n.tag=="h2" and H.has(n,"title") end)
        author=H.first(doc,function(n) return n.attr.rel=="author" end)
        local nav=self:page(canonical_url.."/navigate")
        local seen={}
        for _,a in ipairs(H.all(nav,function(n) return n.tag=="a" and (n.attr.href or ""):match("/works/"..id.."/chapters/%d+") end)) do
            local link=URL.absolute(canonical_url,a.attr.href):gsub("[?#].*$","")
            local parsed=URL.parse(link)
            if ao3_hosts[(parsed.host or ""):lower():gsub("^www%.","")] then
                link="https://"..URL.parse(canonical_url).host..parsed.path
            end
            if not seen[link] then chapters[#chapters+1]={title=H.title(a),url=link}; seen[link]=true end
        end
    else
        local section=H.class(doc,"chapter-info") or doc
        title=H.first(section,function(n) return n.tag=="h1" end)
        author=H.first(doc,function(n) return n.attr.itemprop=="author" end)
        local listing=H.class(doc,"list-of-fanfic-parts")
        local seen={}
        for _,a in ipairs(H.all(listing,function(n) return n.tag=="a" and (n.attr.href or ""):find("/readfic/"..id.."/",1,true) end)) do
            local link=URL.absolute(canonical_url,a.attr.href):gsub("[?#].*$","")
            if not seen[link] then chapters[#chapters+1]={title=H.title(a),url=link}; seen[link]=true end
        end
    end
    assert(title and H.title(title)~="",_("Story not found or login required. Import cookies.txt in Settings."))
    if #chapters==0 then chapters[1]={title=H.title(title),url=canonical_url} end
    local story={url=canonical_url,site=site,id=id,title=H.title(title),author=H.title(author),chapters=chapters}
    local requested=(URL.parse(N.normalize(url)).path or ""):match("/chapters/(%d+)")
    if requested then
        for i,chapter in ipairs(chapters) do
            if chapter.url:match("/chapters/(%d+)$")==requested then story.start_index=i; break end
        end
    end
    story.metadata={title=story.title,author=story.author,site=site,chapters=#chapters,description=H.title(H.first(doc,function(n) return n.attr.itemprop=="description" or H.has(n,"summary") end))}
    return story
end
local mime={jpg="image/jpeg",jpeg="image/jpeg",png="image/png",gif="image/gif",webp="image/webp",svg="image/svg+xml",woff="application/font-woff",woff2="font/woff2",ttf="application/x-font-ttf",otf="application/vnd.ms-opentype",eot="application/vnd.ms-fontobject",css="text/css"}
local extensions={ ["image/jpeg"]="jpg",["image/png"]="png",["image/gif"]="gif",["image/webp"]="webp",["image/svg+xml"]="svg",["text/css"]="css",["font/woff"]="woff",["font/woff2"]="woff2" }
function E:chapter(story,index,refresh)
    local chapter=assert(story.chapters[index],_("Invalid chapter range"))
    local dir=self.data.."/native-cache"
    util.makePath(dir)
    local key=md5(chapter.url..JSON.encode(self.options))
    local saved=read(dir.."/"..key..".json")
    if saved and not refresh then self.progress{stage="Reading cached chapter…"}; return JSON.decode(saved) end
    local doc,base=self:page(chapter.url)
    local content
    if story.site=="ao3" then content=H.id(doc,"workskin")
    else
        local text=H.id(doc,"content") or H.class(doc,"public_beta_disabled")
        if text then
            text.attr.class=(text.attr.class or "").." part_text"
            content={tag="div",attr={},children={}}
            for _,c in ipairs({"part-comment-top"}) do local n=H.class(doc,c); if n then content.children[#content.children+1]=n end end
            content.children[#content.children+1]=text
            local bottom=H.class(doc,"part-comment-bottom"); if bottom then content.children[#content.children+1]=bottom end
        end
    end
    assert(content and #H.title(content)>0,_("Chapter text not found. The website may require login or have changed."))
    local assets,seen,warnings={},{},{}
    local cssrewrite,asset
    local function fetchasset(value,origin,depth)
        if value:match("^data:") or value:sub(1,1)=="#" then return value end
        local remote=URL.absolute(origin,value):gsub("#.*$","")
        if seen[remote] then return seen[remote] end
        assert(#assets<300,_("Too many chapter resources"))
        local bytes,headers=self.net:get(remote,origin)
        local typ=(headers["content-type"] or ""):match("^[^;]+")
        local ext=extensions[typ] or remote:match("%.([%a%d]+)[^/]*$") or "bin"
        ext=ext:lower(); if not mime[ext] then ext="bin" end
        assert(ext~="bin",_("Unsupported resource type: ")..tostring(typ or remote))
        local name=md5(remote).."."..ext
        seen[remote]=name
        local item={name=name,type=mime[ext],data=bytes}
        assets[#assets+1]=item
        if ext=="css" then assert(depth<5,_("Stylesheet nesting is too deep")); item.data=cssrewrite(bytes,remote,depth+1) end
        return name
    end
    asset=function(value,origin,depth)
        local ok,result=pcall(fetchasset,value,origin,depth)
        if ok then return result end
        warnings[#warnings+1]=URL.absolute(origin,value).."\n"..tostring(result)
        return nil
    end
    cssrewrite=function(css,origin,depth)
        css=css:gsub("@import%s+(['\"])(.-)%1%s*;",function(q,url)
            local name=asset(url,origin,depth)
            return name and '@import url("'..name..'");' or ""
        end)
        return css:gsub("url%(%s*([^%)]+)%s*%)",function(value)
            value=value:match("^%s*(.-)%s*$"):gsub("^['\"]",""):gsub("['\"]$","")
            for _,a in ipairs(assets) do if value==a.name then return 'url("'..value..'")' end end
            return 'url("'..(asset(value,origin,depth) or "")..'")'
        end)
    end
    local css={"body{line-height:1.4}img{max-width:100%;height:auto}.part_text,.text-preline{white-space:pre-wrap}.landmark{display:none}blockquote{margin:1em 5%}table{max-width:100%}"}
    if self.options.styles~=false then
        for _,style in ipairs(H.all(doc,function(n) return n.tag=="style" end)) do css[#css+1]=cssrewrite(H.text(style),base,0) end
        if story.site=="ficbook" then
            for _,link in ipairs(H.all(doc,function(n) return n.tag=="link" and n.attr.rel=="stylesheet" and n.attr.href end)) do
                local name=asset(link.attr.href,base,0)
                if name then css[#css+1]='@import url("'..name..'");' end
            end
        end
    end
    for _,img in ipairs(H.all(content,function(n) return n.tag=="img" end)) do
        img.attr.src=img.attr["data-src"] or img.attr.src
    end
    local html=H.render(content,function(node,k,v)
        if k=="src" and node.tag=="img" then return asset(v,base,0) end
        if k=="href" and v:sub(1,1)~="#" then return URL.absolute(base,v) end
        if k=="style" then return self.options.styles~=false and cssrewrite(v,base,0) or nil end
        return v
    end)
    local result={html=html,css=table.concat(css,"\n"),assets=assets,title=chapter.title,url=chapter.url}
    local stored={html=result.html,css=result.css,assets={},title=result.title,url=result.url,warnings=warnings}
    for _,a in ipairs(assets) do
        write(dir.."/"..a.name,a.data)
        stored.assets[#stored.assets+1]={name=a.name,type=a.type}
    end
    write(dir.."/"..key..".json",JSON.encode(stored))
    return stored
end
function E:book(story,first,last,refresh)
    local entries={{"mimetype","application/epub+zip"},{"META-INF/container.xml",'<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'}}
    local manifest,spine,nav,seen,warnings={},{},{},{},{}
    for i=first,last do
        self.progress{stage="Downloading chapter…",done=i-first,total=last-first+1,bytes=0}
        local ch=self:chapter(story,i,refresh)
        for _,warning in ipairs(ch.warnings or {}) do warnings[#warnings+1]=warning end
        local prefix="c"..i.."/"
        local filename=prefix.."chapter.xhtml"
        entries[#entries+1]={"OEBPS/"..filename,'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>'..H.escape(ch.title)..'</title><link rel="stylesheet" type="text/css" href="style.css" /></head><body>'..ch.html..'</body></html>'}
        entries[#entries+1]={"OEBPS/"..prefix.."style.css",ch.css}
        manifest[#manifest+1]='<item id="c'..i..'" href="'..filename..'" media-type="application/xhtml+xml"/><item id="s'..i..'" href="'..prefix..'style.css" media-type="text/css"/>'
        spine[#spine+1]='<itemref idref="c'..i..'"/>'
        nav[#nav+1]='<navPoint id="n'..i..'" playOrder="'..(#nav+1)..'"><navLabel><text>'..H.escape(ch.title)..'</text></navLabel><content src="'..filename..'"/></navPoint>'
        for j,a in ipairs(ch.assets) do
            local bytes=assert(read(self.data.."/native-cache/"..a.name),_("Cached resource is missing; download the chapter again"))
            local path=prefix..a.name
            if not seen[path] then entries[#entries+1]={"OEBPS/"..path,bytes}; seen[path]=true
                manifest[#manifest+1]='<item id="a'..i..'_'..j..'" href="'..path..'" media-type="'..a.type..'"/>' end
        end
    end
    entries[#entries+1]={"OEBPS/toc.ncx",'<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="'..H.escape(story.url)..'"/></head><docTitle><text>'..H.escape(story.title)..'</text></docTitle><navMap>'..table.concat(nav)..'</navMap></ncx>'}
    entries[#entries+1]={"OEBPS/content.opf",'<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">'..H.escape(story.url)..'</dc:identifier><dc:title>'..H.escape(story.title)..'</dc:title><dc:creator>'..H.escape(story.author)..'</dc:creator><dc:language>'..(story.site=="ficbook" and "ru" or "en")..'</dc:language></metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'..table.concat(manifest)..'</manifest><spine toc="ncx">'..table.concat(spine)..'</spine></package>'}
    local dir="stories/"..story.site.."-"..story.id
    if URL.parse(story.url).host=="archiveofourown.gay" then dir=dir.."-gay" end
    util.makePath(self.data.."/"..dir)
    local name=first==last and md5(story.chapters[first].url) or first.."-"..last
    local artifact=dir.."/native-"..name..".epub"
    local path=self.data.."/"..artifact
    self.progress{stage="Building EPUB…",done=last-first,total=last-first+1,bytes=0}
    Z.write(path..".tmp",entries)
    FS.replace(path..".tmp",path)
    self.progress{stage="EPUB ready",done=last-first+1,total=last-first+1}
    local f=assert(io.open(path,"rb")); local size=f:seek("end"); f:close()
    return {artifact=artifact,size=size,filename=artifact:match("[^/]+$"),format="epub",warnings=warnings}
end
function E:request(req)
    self.pages={}
    if req.action=="diagnose" then return {text=self.net:diagnose(req.url)} end
    if req.action=="status" then return {engine="Native Lua",version=require("fan_version"),sites={"AO3","archiveofourown.gay","Ficbook"}} end
    if req.action=="sites" then return {sites={{site="archiveofourown.org",examples="https://archiveofourown.org/works/123"},{site="archiveofourown.gay",examples="https://archiveofourown.gay/works/94864406/chapters/253293581"},{site="ficbook.net",examples="https://ficbook.net/readfic/123"}}} end
    if req.action=="set_cookies" then write(self.data.."/cookies.txt",req.text); self.net=N.new(req.text); return {} end
    if req.action=="list" then
        local doc,base=self:page(req.url)
        local out,seen={},{}
        for _,a in ipairs(H.all(doc,function(n) return n.tag=="a" and n.attr.href end)) do
            local ok,url=pcall(canonical,URL.absolute(base,a.attr.href))
            if ok and not seen[url] then out[#out+1]=url; seen[url]=true end
        end
        return {urllist=out}
    end
    assert(req.action=="metadata" or req.action=="chapter" or req.action=="download" or req.action=="update",_("Unsupported operation"))
    assert(not req.format or req.format=="epub",_("Only EPUB export is supported"))
    local story=self:metadata(req.url)
    if req.action=="metadata" then return story end
    local first=req.action=="chapter" and tonumber(req.index) or tonumber(req.begin) or 1
    local last=req.action=="chapter" and tonumber(req.index) or tonumber(req["end"]) or #story.chapters
    assert(first and last and first>=1 and last>=first and last<=#story.chapters and first%1==0 and last%1==0,_("Invalid chapter range"))
    return self:book(story,first,last,req.refresh or req.always)
end
return E
