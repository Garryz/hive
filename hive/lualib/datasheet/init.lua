local cell = require "cell"
local core = require "hive.datasheet"

local datasheet_srv

cell.init(
    function()
        datasheet_srv = cell.uniqueservice("service.datasheetd")
    end
)

local datasheet = {}
local sheets =
    setmetatable(
    {},
    {
        __gc = function(t)
            cell.send(datasheet_srv, "close", cell.self)
        end
    }
)

local function querysheet(name)
    return cell.call(datasheet_srv, "query", cell.self, name)
end

local function updateobject(name)
    local t = sheets[name]
    if not t.object then
        t.object = core.new(t.handle)
    end
    local function monitor()
        local handle = t.handle
        local newhandle = cell.call(datasheet_srv, "monitor", cell.self, handle)
        core.update(t.object, newhandle)
        t.handle = newhandle
        cell.send(datasheet_srv, "release", cell.self, handle)
        return monitor()
    end
    cell.fork(monitor)
end

function datasheet.query(name)
    local t = sheets[name]
    if not t then
        t = {}
        sheets[name] = t
    end
    if t.error then
        error(t.error)
    end
    if t.object then
        return t.object
    end
    if t.queue then
        local event = cell.event()
        table.insert(t.queue, event)
        cell.wait(event)
    else
        t.queue = {} -- create wait queue for other query
        local ok, handle = pcall(querysheet, name)
        if ok then
            t.handle = handle
            updateobject(name)
        else
            t.error = handle
        end
        local q = t.queue
        t.queue = nil
        for _, event in ipairs(q) do
            cell.wakeup(event)
        end
    end
    if t.error then
        error(t.error)
    end
    return t.object
end

return datasheet
