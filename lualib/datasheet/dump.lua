--[[ file format
document:
    int32 strtbloffset
    int32 n
    int32*n index table
    table*n
    strings

table:
    int32 dict
    int8*dict k type v type (align 4)
    kvpair*dict

kvpair:
    value k
    value v

value: (union)
    int32 integer
    float real
    int32 boolean
    int32 table index
    int32 string offset

type: (enum)
    0 nil
    1 integer
    2 real
    3 boolean
    4 table
    5 string
]]
local ctd = {}
local math = math
local table = table
local string = string

function ctd.dump(root)
    local doc = {
        table_n = 0,
        table = {},
        strings = {},
        offset = 0
    }
    local function dump_table(t)
        local index = doc.table_n + 1
        doc.table_n = index
        doc.table[index] = false -- place holder
        local kvs = {}
        local types = {}
        local function encode(v)
            local t = type(v)
            if t == "table" then
                local index = dump_table(v)
                return "\4", string.pack("<I4", index - 1)
            elseif t == "number" then
                if math.tointeger(v) and v <= 0x7FFFFFFF and v >= -(0x7FFFFFFF + 1) then
                    return "\1", string.pack("<i4", v)
                else
                    return "\2", string.pack("<f", v)
                end
            elseif t == "boolean" then
                if v then
                    return "\3", "\0\0\0\1"
                else
                    return "\4", "\0\0\0\0"
                end
            elseif t == "string" then
                local offset = doc.strings[v]
                if not offset then
                    offset = doc.offset
                    doc.offset = offset + #v + 1
                    doc.strings[v] = offset
                    table.insert(doc.strings, v)
                end
                return "\5", string.pack("<I4", offset)
            else
                error("Unsupport value " .. tostring(v))
            end
        end
        for k, v in pairs(t) do
            local ktv, kv = encode(k)
            if ktv ~= "\1" and ktv ~= "\2" and ktv ~= "\5" then
                error("Unsupport key type " .. type(k))
            end
            local etv, ev = encode(v)
            table.insert(types, ktv)
            table.insert(types, etv)
            table.insert(kvs, kv .. ev)
        end
        -- encode table
        local typeset = table.concat(types)
        local align = string.rep("\0", (4 - #typeset & 3) & 3)
        local tmp = {
            string.pack("<I4", #kvs),
            typeset,
            align,
            table.concat(kvs)
        }
        doc.table[index] = table.concat(tmp)
        return index
    end
    dump_table(root)
    -- encode document
    local index = {}
    local offset = 0
    for i, v in ipairs(doc.table) do
        index[i] = string.pack("<I4", offset)
        offset = offset + #v
    end
    local tmp = {
        string.pack("<I4", 4 + 4 + 4 * doc.table_n + offset),
        string.pack("<I4", doc.table_n),
        table.concat(index),
        table.concat(doc.table),
        table.concat(doc.strings, "\0"),
        "\0"
    }
    return table.concat(tmp)
end

function ctd.undump(v)
    local stringtbl, n = string.unpack("<I4I4", v)
    local index = {string.unpack("<" .. string.rep("I4", n), v, 9)}
    local header = 4 + 4 + 4 * n + 1
    stringtbl = stringtbl + 1
    local tblidx = {}
    local function decode(n)
        local toffset = index[n + 1] + header
        local dict = string.unpack("<I4", v, toffset)
        local types = {string.unpack(string.rep("B", 2 * dict), v, toffset + 4)}
        local offset = ((2 * dict + 4 + 3) & ~3) + toffset
        local result = {}
        local function value(t)
            local off = offset
            offset = offset + 4
            if t == 1 then -- integer
                return (string.unpack("<i4", v, off))
            elseif t == 2 then -- float
                return (string.unpack("<f", v, off))
            elseif t == 3 then -- boolean
                return string.unpack("<i4", v, off) ~= 0
            elseif t == 4 then -- table
                local tindex = (string.unpack("<I4", v, off))
                return decode(tindex)
            elseif t == 5 then -- string
                local sindex = string.unpack("<I4", v, off)
                return (string.unpack("z", v, stringtbl + sindex))
            else
                error(string.format("Invalid data at %d (%d)", off, t))
            end
        end
        for i = 1, dict do
            result[value(types[2 * i - 1])] = value(types[2 * i])
        end
        tblidx[result] = n
        return result
    end
    return decode(0), tblidx
end

local function diffmap(last, current)
    local lastv, lasti = ctd.undump(last)
    local curv, curi = ctd.undump(current)
    local map = {} -- new(current index):old(last index)
    local function comp(lastr, curr)
        local old = lasti[lastr]
        local new = curi[curr]
        map[new] = old
        for k, v in pairs(lastr) do
            if type(v) == "table" then
                local newv = curr[k]
                if type(newv) == "table" then
                    comp(v, newv)
                end
            end
        end
    end
    comp(lastv, curv)
    return map
end

function ctd.diff(last, current)
    local map = diffmap(last, current)
    local stringtbl, n = string.unpack("<I4I4", current)
    local _, lastn = string.unpack("<I4I4", last)
    local newn = lastn
    for i = 0, n - 1 do
        if not map[i] then
            map[i] = newn
            newn = newn + 1
        end
    end
    -- remap current
    local index = {string.unpack("<" .. string.rep("I4", n), current, 9)}
    local header = 4 + 4 + 4 * n + 1
    local function remap(n)
        local toffset = index[n + 1] + header
        local dict = string.unpack("<I4", current, toffset)
        local types = {string.unpack(string.rep("B", 2 * dict), current, toffset + 4)}
        local hlen = (2 * dict + 4 + 3) & ~3
        local hastable = false
        for i = 2, 2 * dict, 2 do
            if types[i] == 4 then -- table
                hastable = true
                break
            end
        end
        if not hastable then
            return string.sub(current, toffset, toffset + hlen + dict * 2 * 4 - 1)
        end
        local offset = hlen + toffset
        local pat = "<" .. string.rep("I4", 2 * dict)
        local values = {string.unpack(pat, current, offset)}
        for i = 1, dict do
            if types[i * 2] == 4 then -- table
                values[i * 2] = map[values[2 * i]]
            end
        end
        return string.sub(current, toffset, toffset + hlen - 1) .. string.pack(pat, table.unpack(values))
    end
    -- rebuild
    local oldindex = {string.unpack("<" .. string.rep("I4", n), current, 9)}
    local index = {}
    for i = 1, newn do
        index[i] = 0xffffffff
    end
    for i = 0, #map do
        index[map[i] + 1] = oldindex[i + 1]
    end

    local tmp = {
        string.pack("<I4I4", stringtbl + (newn - n) * 4, newn), -- expand index table
        string.pack("<" .. string.rep("I4", newn), table.unpack(index))
    }
    for i = 0, n - 1 do
        table.insert(tmp, remap(i))
    end
    table.insert(tmp, string.sub(current, stringtbl + 1))

    return table.concat(tmp)
end

return ctd
