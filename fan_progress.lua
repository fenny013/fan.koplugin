local JSON=require("json")
local P={}
function P.writer(path)
    if not path then return function() end end
    local state,last={},0
    return function(event)
        local now=os.time()
        local changed=event.stage and event.stage~=state.stage or event.url and event.url~=state.url
            or event.done and event.done~=state.done or event.attempt and event.attempt~=state.attempt
        for key,value in pairs(event) do state[key]=value end
        if not changed and now==last then return end
        last=now
        local f=io.open(path..".tmp","wb")
        if f then
            f:write(JSON.encode(state)); f:close()
            require("fan_fs").replace(path..".tmp",path)
        end
    end
end
function P.read(path)
    local f=io.open(path,"rb")
    if not f then return end
    local value=f:read("*a"); f:close()
    local ok,state=pcall(JSON.decode,value)
    if ok and type(state)=="table" then return state end
end
function P.window(label,path)
    local ConfirmBox=require("ui/widget/confirmbox")
    local ProgressWidget=require("ui/widget/progresswidget")
    local TextBoxWidget=require("ui/widget/textboxwidget")
    local Font=require("ui/font")
    local Screen=require("device").screen
    local UI=require("ui/uimanager")
    local _=require("fan_i18n").t
    local width=math.floor(math.min(Screen:getWidth(),Screen:getHeight())*2/3)
    local bar=ProgressWidget:new{width=width,height=Screen:scaleBySize(12),percentage=0}
    local details=TextBoxWidget:new{width=width,height=Screen:scaleBySize(180),face=Font:getFace("smallinfofont"),text="\n\n\n\n"}
    local dialog
    dialog=ConfirmBox:new{text=label,icon="notice-info",no_ok_button=true,dismissable=false,keep_dialog_open=true,
        cancel_text=_("Cancel download"),_added_widgets={bar,details},
        cancel_callback=function()
            dialog.closing=true
            if dialog.dismiss_callback then dialog.dismiss_callback() end
        end}
    local started,active,last=os.time(),true,nil
    local function tick()
        if not active then return end
        local s=P.read(path) or {}
        local text=_(s.stage or "Connecting to website…")
        local host=(s.url or ""):match("^https?://([^/]+)") or ""
        text=text.."\n"..host
        if s.total then text=text.."\n".._("Chapters: ")..(s.done or 0).." / "..s.total
        else text=text.."\n".._("Waiting for website response…") end
        text=text.."\n"..string.format("%.1f KiB",(s.bytes or 0)/1024)
            .." · "..(os.time()-started).." ".._("sec")
        if s.attempt and s.attempt>1 then text=text.." · ".._("Attempt ")..s.attempt.."/3" end
        if text~=last then
            details:setText(text)
            bar:setPercentage(s.total and math.min(1,(s.done or 0)/s.total) or 0)
            UI:setDirty(dialog,"ui")
            last=text
        end
        UI:scheduleIn(1,tick)
    end
    function dialog:stopProgress()
        active=false
        UI:unschedule(tick)
        if not self.closing then UI:close(self) end
        os.remove(path); os.remove(path..".tmp")
    end
    UI:show(dialog)
    tick()
    return dialog
end
return P
