local F={}
function F.replace(temporary,target)
    local ok,err=os.rename(temporary,target)
    if ok then return true end
    local f=io.open(target,"rb")
    if not f then error(err,0) end
    f:close()
    local backup=target..".backup-"..os.time().."-"..math.random(100000,999999)
    assert(os.rename(target,backup))
    local moved,message=os.rename(temporary,target)
    if not moved then assert(os.rename(backup,target)); error(message,0) end
    os.remove(backup)
    return true
end
return F
