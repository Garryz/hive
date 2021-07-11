local cell = require "cell"

local command = {}
local message = {}

local handles = {} -- handle:{ ref:count , name:name , collect:resp }
local dataset = {} -- name:{ handle:handle, monitor:{monitors queue} }
local customers = {} -- source: { handle:true }

setmetatable(
    customers,
    {
        __index = function(c, source)
            local v = {}
            c[source] = v
            return v
        end
    }
)

local function releasehandle(source, handle)
    local h = handles[handle]
    h.ref = h.ref - 1
    if h.ret == 0 and h.collect then
        cell.wakeup(h.collect)
        h.collect = nil
        handles[handle] = nil
    end
    local t = dataset[h.name]
    local monitor = t.monitor[source]
    if monitor then
        cell.wakeup(monitor)
        t.monitor[source] = nil
    end
end

-- from builder, create or update handle
function command.update(name, handle)
    local t = dataset[name]
    if not t then
        -- new datasheet
        t = {handle = handle, monitor = {}}
        dataset[name] = t
        handles[handle] = {ref = 1, name = name}
    else
        -- report update to customers
        handles[handle] = {ref = handles[t.handle].ref, name = name}
        t.handle = handle

        for k, v in pairs(t.monitor) do
            cell.wakeup(v)
            t.monitor[k] = nil
        end
    end
end

-- from customers
function command.query(source, name)
    local t = assert(dataset[name], "create data first")
    local handle = t.handle
    local h = handles[handle]
    h.ref = h.ref + 1
    customers[source][handle] = true
    return handle
end

-- from customers, monitor handle change
function command.monitor(source, handle)
    local h = assert(handles[handle], "Invalid data handle")
    local t = dataset[h.name]
    if t.handle ~= handle then -- already changes
        customers[source][t.handle] = true
        return t.handle
    else
        assert(not t.monitor[source])
        local event = cell.event()
        t.monitor[source] = event
        cell.wait(event)
        customers[source][t.handle] = true
        return t.handle
    end
end

-- from builder, monitor handle release
function command.collect(handle)
    local h = assert(handles[handle], "Invalid data handle")
    if h.ref == 0 then
        handles[handle] = nil
    else
        assert(h.collect == nil, "Only one collect allows")
        local event = cell.event()
        h.collect = event
        cell.wait(event)
    end
end

-- from customers, release handle , ref count - 1
function message.release(source, handle)
    -- send message
    customers[source][handle] = nil
    releasehandle(source, handle)
end

-- customer closed, clear all handles it queried
function message.close(source)
    for handle in pairs(customers[source]) do
        releasehandle(source, handle)
    end
    customers[source] = nil
end

cell.command(command)
cell.message(message)

function cell.info()
    local info = {}
    local tmp = {}
    for k, v in pairs(handles) do
        tmp[k] = v
    end
    for k, v in pairs(dataset) do
        local h = handles[v.handle]
        tmp[v.handle] = nil
        info[k] = {
            handle = v.handle,
            monitors = h.ref
        }
    end
    for k, v in pairs(tmp) do
        info[k] = v.ref
    end

    return info
end
