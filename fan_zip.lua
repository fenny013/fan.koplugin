local bit = require("bit")
local Z = {}
local lookup={}
for i=0,255 do
    local c=i
    for _=1,8 do c=bit.bxor(bit.rshift(c,1),bit.band(c,1)==1 and 0xedb88320 or 0) end
    lookup[i]=c
end
local function crc(data)
    local c=-1
    for i=1,#data do c=bit.bxor(bit.rshift(c,8),lookup[bit.band(bit.bxor(c,data:byte(i)),255)]) end
    return bit.bnot(c)
end
local function le(n,bytes)
    local out={}
    for i=1,bytes do out[i]=string.char(bit.band(n,255)); n=bit.rshift(n,8) end
    return table.concat(out)
end
function Z.write(path,entries)
    local f=assert(io.open(path,"wb"))
    local directory,offset={},0
    local ok,err=pcall(function()
        for _,entry in ipairs(entries) do
            local name,data=entry[1],entry[2]
            local sum,size=crc(data),#data
            local common=le(0,2)..le(0,2)..le(0,2)..le(33,2)..le(sum,4)..le(size,4)..le(size,4)..le(#name,2)..le(0,2)
            local header="PK\003\004"..le(20,2)..common..name
            assert(f:write(header,data))
            directory[#directory+1]="PK\001\002"..le(20,2)..le(20,2)..common..le(0,2)..le(0,2)..le(0,2)..le(0,4)..le(offset,4)..name
            offset=offset+#header+size
        end
        local central=table.concat(directory)
        assert(f:write(central,"PK\005\006"..le(0,2)..le(0,2)..le(#entries,2)..le(#entries,2)..le(#central,4)..le(offset,4)..le(0,2)))
    end)
    local closed=f:close()
    if not ok then os.remove(path); error(err,0) end
    assert(closed)
end
return Z
