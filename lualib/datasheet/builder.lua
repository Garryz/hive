local cell = require "cell"
local dump = require "datasheet.dump"
local core = require "hive.datasheet"

local address

cell.init(
    function()
        address = cell.uniqueservice("service.datasheetd")
    end
)

local builder = {}

local cache = {}
local dataset = {}

local unique_id = 0
local function unique_string(str)
    unique_id = unique_id + 1
    return str .. tostring(unique_id)
end

local function monitor(pointer)
    cell.fork(
        function()
            cell.call(address, "collect", pointer)
            for k, v in pairs(cache) do
                if v == pointer then
                    cache[k] = nil
                    return
                end
            end
        end
    )
end

local function dumpsheet(v)
    if type(v) == "string" then
        return v
    else
        return dump.dump(v)
    end
end

function builder.new(name, v)
    assert(dataset[name] == nil)
    local datastring = unique_string(dumpsheet(v))
    local pointer = core.stringpointer(datastring)
    cell.call(address, "update", name, pointer)
    cache[datastring] = pointer
    dataset[name] = datastring
    monitor(pointer)
end

function builder.update(name, v)
    local lastversion = assert(dataset[name])
    local newversion = dumpsheet(v)
    local diff = unique_string(dump.diff(lastversion, newversion))
    local pointer = core.stringpointer(diff)
    cell.call(address, "update", name, pointer)
    cache[diff] = pointer
    local lp = assert(cache[lastversion])
    cell.send(address, "release", cell.self, lp)
    dataset[name] = diff
    monitor(pointer)
end

function builder.compile(v)
    return dump.dump(v)
end

return builder
