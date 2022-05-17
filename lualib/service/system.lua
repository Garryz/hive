local cell = require "cell"
local system = require "cell.system"
local seri = require "hive.seri"
local builder = require "datasheet.builder"
local log = require "log"

local coroutine = coroutine
local table = table
local assert = assert
local package = package
local error = error
local type = type
local ipairs = ipairs

local command = {}
local message = {}
local ticker = 0
local timer = {}
local free_queue = {}
local unique_service = {}
local service_name = {}
local service_id = {}
local id_service = {}
local register_name_service = {}
local service_register_name = {}

local function alloc_queue()
    local n = #free_queue
    if n > 0 then
        local r = free_queue[n]
        free_queue[n] = nil
        return r
    else
        return {}
    end
end

local function timeout(n, f)
    local co =
        cell.cocreate(
        function()
            local ev = cell.event()
            local ti = ticker + n
            local q = timer[ti]
            if q == nil then
                q = alloc_queue()
                timer[ti] = q
            end
            table.insert(q, ev)
            cell.wait(ev)
            f()
            return "EXIT"
        end
    )
    cell.suspend(nil, nil, co, coroutine.resume(co))
end

function command.echo(str)
    return str
end

function command.launch(name, ...)
    local fullname = assert(package.searchpath(name, package.path), "cell was not found")
    local c = system.launch(fullname, system.loader)
    if c then
        local ok, result =
            pcall(
            function(...)
                -- 4 is launch proto
                local ev = cell.event()
                return table.pack(cell.rawcall(c, ev, 4, cell.self, ev, true, ...))
            end,
            ...
        )
        if ok then
            service_name[c] = fullname
            service_id[c] = c:id()
            id_service[c:id()] = c
            return c, table.unpack(result)
        else
            system.kill(c)
            return nil, result
        end
    else
        error("launch " .. name .. " failed")
    end
end

function command.uniquelaunch(name, ...)
    local fullname = assert(package.searchpath(name, package.path), "cell was not found")
    local s = unique_service[fullname]
    if type(s) == "userdata" then
        return s
    end

    if s == nil then
        s = {}
        unique_service[fullname] = s
    elseif type(s) == "string" then
        error(s)
    end

    assert(type(s) == "table")

    if s.launch == nil then
        s.launch = true
        local c = system.launch(fullname, system.loader)
        local ok, result
        if c then
            ok, result =
                pcall(
                function(...)
                    local ev = cell.event()
                    return table.pack(cell.rawcall(c, ev, 4, cell.self, ev, true, ...))
                end,
                ...
            )
            if ok then
                unique_service[fullname] = c
                service_name[c] = fullname
                service_id[c] = c:id()
                id_service[c:id()] = c
            else
                system.kill(c)
                unique_service[fullname] = result
            end
        else
            unique_service[fullname] = "launch " .. name .. " failed"
        end

        for _, v in ipairs(s) do
            cell.wakeup(v)
        end

        if c and ok then
            return c, table.unpack(result)
        else
            error(unique_service[fullname])
        end
    end

    local session = cell.event()
    table.insert(s, session)
    cell.wait(session)
    s = unique_service[fullname]
    if type(s) == "string" then
        error(s)
    end
    assert(type(s) == "userdata")
    return s
end

function command.kill(c)
    if service_name[c] then
        unique_service[service_name[c]] = nil
        service_name[c] = nil
        id_service[service_id[c]] = nil
        service_id[c] = nil
    end
    if service_register_name[c] then
        register_name_service[service_register_name[c]] = nil
        service_register_name[c] = nil
    end
    return assert(system.kill(c))
end

function command.timeout(n)
    if n > 0 then
        local ev = cell.event()
        local ti = ticker + n
        local q = timer[ti]
        if q == nil then
            q = alloc_queue()
            timer[ti] = q
        end
        table.insert(q, ev)
        cell.wait(ev)
    end
end

function command.socket()
    return system.socket
end

function command.getcell(val)
    local val_type = type(val)
    if val_type == "number" then
        return id_service[val]
    elseif val_type == "string" then
        return register_name_service[val]
    end
end

function command.register(c, name)
    if register_name_service[name] then
        return false
    end
    service_register_name[c] = name
    register_name_service[name] = c
    return true
end

function command.list()
    local list = {}
    for k, v in pairs(service_name) do
        list[tostring(k)] = v
    end
    return list
end

local function list_srv(ti, cmd)
    local list = {}
    for k in pairs(service_name) do
        list[tostring(k)] = cell.debug(k, ti, cmd)
        if not list[tostring(k)] then
            list[tostring(k)] = k .. "timeout"
        end
    end
    return list
end

function command.stat()
    return list_srv(3000, "stat")
end

function command.mem()
    return list_srv(3000, "mem")
end

function command.gc()
    return list_srv(3000, "gc")
end

message.kill = command.kill

cell.command(command)
cell.message(message)

cell.dispatch {
    msg_type = 0, -- timer
    dispatch = function()
        ticker = ticker + 1
        local q = timer[ticker]
        if q == nil then
            return
        end
        for i = 1, #q do
            cell.wakeup(q[i])
            q[i] = nil
        end
        timer[ticker] = nil
        table.insert(free_queue, q)
    end
}

local config

function cell.main()
    builder.new("__HIVE_ENV", config)
end

local function start()
    print("[system cell]", cell.self)
    local socket_cell = system.socket
    print("[socket cell]", socket_cell)
    cell.rawsend(socket_cell, 4, nil, nil, false)

    config = seri.unpack(system.configptr)
    system.configptr = nil
    cell.rawsend(cell.self, 4, nil, nil, false)

    local c = system.launch(system.maincell, system.loader)
    if c then
        print("[main cell]", c)
        cell.rawsend(c, 4, nil, nil, false)
    else
        error "launch main.lua failed"
    end
end

start()
