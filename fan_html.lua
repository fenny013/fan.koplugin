local util = require("util")
local H = {}
local void = { area=true, base=true, br=true, col=true, embed=true, hr=true, img=true, input=true, link=true, meta=true, param=true, source=true, track=true, wbr=true }
local blocked = { script=true, iframe=true, object=true, embed=true, form=true, input=true, button=true, textarea=true, select=true }

function H.decode(s)
    return util.htmlEntitiesToUtf8(s or "")
end

function H.escape(s)
    return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

function H.parse(html)
    local root = { tag="root", attr={}, children={} }
    local stack, pos = { root }, 1
    while pos <= #html do
        local start = html:find("<", pos, true)
        local parent = stack[#stack]
        if not start then parent.children[#parent.children+1] = H.decode(html:sub(pos)); break end
        if start > pos then parent.children[#parent.children+1] = H.decode(html:sub(pos,start-1)) end
        if html:sub(start,start+3) == "<!--" then
            local finish = html:find("-->",start+4,true)
            pos = finish and finish+3 or #html+1
        else
            local cursor, quote = start+1, nil
            while cursor <= #html do
                local c = html:sub(cursor,cursor)
                if quote then if c == quote then quote = nil end
                elseif c == '"' or c == "'" then quote = c
                elseif c == ">" then break end
                cursor = cursor+1
            end
            if cursor > #html then parent.children[#parent.children+1] = H.decode(html:sub(start)); break end
            local token = html:sub(start+1,cursor-1)
            local closing, tag = token:match("^%s*(/?)%s*([%w:_%-]+)")
            pos = cursor+1
            if tag then
                tag = tag:lower()
                if closing == "/" then
                    for i=#stack,2,-1 do
                        if stack[i].tag == tag then for j=#stack,i,-1 do stack[j]=nil end; break end
                    end
                else
                    if (tag == "p" or tag == "li") and stack[#stack].tag == tag then table.remove(stack) end
                    parent = stack[#stack]
                    local node = { tag=tag, attr={}, children={} }
                    local rest = token:match("^%s*[%w:_%-]+(.*)$") or ""
                    local i = 1
                    while i <= #rest do
                        local a,b,key = rest:find("^%s*([%w:_%-]+)",i)
                        if not a then break end
                        i=b+1
                        local _,eq = rest:find("^%s*=%s*",i)
                        local value = ""
                        if eq then
                            i=eq+1
                            local q = rest:sub(i,i)
                            if q == '"' or q == "'" then
                                local e = rest:find(q,i+1,true) or #rest+1
                                value=rest:sub(i+1,e-1); i=e+1
                            else
                                local e = rest:find("[%s>]",i) or #rest+1
                                value=rest:sub(i,e-1); i=e
                            end
                        end
                        node.attr[key:lower()] = H.decode(value)
                    end
                    parent.children[#parent.children+1]=node
                    if tag == "style" or tag == "script" then
                        local a,b = html:lower():find("</"..tag.."%s*>",pos)
                        node.children[1]=html:sub(pos,a and a-1 or #html)
                        pos=b and b+1 or #html+1
                    elseif not void[tag] and not token:match("/%s*$") then stack[#stack+1]=node end
                end
            end
        end
    end
    return root
end

function H.has(node, class)
    return (" "..(node.attr.class or "").." "):find(" "..class.." ",1,true) ~= nil
end

function H.all(node, predicate, out)
    out = out or {}
    if type(node) ~= "table" then return out end
    if predicate(node) then out[#out+1]=node end
    for _,child in ipairs(node.children) do H.all(child,predicate,out) end
    return out
end

function H.first(node, predicate) return H.all(node,predicate)[1] end
function H.id(node,id) return H.first(node,function(n) return n.attr.id == id end) end
function H.class(node,c) return H.first(node,function(n) return H.has(n,c) end) end
function H.text(node)
    if not node then return "" end
    if type(node) == "string" then return node end
    local out={}
    for _,c in ipairs(node.children) do out[#out+1]=H.text(c) end
    return table.concat(out)
end
function H.title(node) return H.text(node):gsub("%s+"," "):match("^%s*(.-)%s*$") end

function H.render(node, rewrite)
    if type(node)=="string" then return H.escape(node) end
    if blocked[node.tag] or node.tag == "style" or node.tag == "link" or node.tag == "meta" then return "" end
    local children={}
    for _,child in ipairs(node.children) do children[#children+1]=H.render(child,rewrite) end
    if node.tag=="root" then return table.concat(children) end
    local attrs={}
    for k,v in pairs(node.attr) do
        if not k:match("^on") and k ~= "srcset" and k ~= "xmlns" and k ~= "data-src" and k:match("^[%a_][%w_.%-]*$") then
            if rewrite then v=rewrite(node,k,v) end
            if v and not ((k=="href" or k=="src") and v:lower():match("^%s*javascript:")) then attrs[#attrs+1]=" "..k..'="'..H.escape(v)..'"' end
        end
    end
    table.sort(attrs)
    local tag=node.tag
    if tag:find(":",1,true) then tag="span" end
    if void[tag] then return "<"..tag..table.concat(attrs).." />" end
    return "<"..tag..table.concat(attrs)..">"..table.concat(children).."</"..tag..">"
end

return H
