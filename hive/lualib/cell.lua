local c = require "cell.c"

local table = table
local coroutine = coroutine
local assert = assert
local select = select
local next = next
local pairs = pairs
local type = type

local session = 0
local coroutine_pool = setmetatable({}, {__mode = "kv"})
local msg_dispatchers = {}
local task_coroutine = {}
local task_session = {}
local task_source = {}
local event_q1 = {}
local event_q2 = {}
local command = {}
local message = {}

local cell = {}

local self = c.self
local system = c.system
cell.self = self

cell.rawsend = c.send

local function new_task(source, session, co, event)
    task_coroutine[event] = co
    task_session[event] = session
    task_source[event] = source
end

local function co_create(f)
    local co = table.remove(coroutine_pool)
    if co == nil then
        co =
            coroutine.create(
            function(...)
                local result = table.pack(f(...))
                while true do
                    -- recycle co into coroutine_pool
                    f = nil
                    coroutine_pool[#coroutine_pool + 1] = co
                    -- recv new main function f
                    f = coroutine.yield(table.unpack(result))
                    result = table.pack(f(coroutine.yield()))
                end
            end
        )
    else
        local ret, err = coroutine.resume(co, f)
        if not ret then
            print(debug.traceback(), "\n", string.format("co_create %s", err))
        end
    end
    return co
end

cell.co_create = co_create

local function suspend(source, session, co, ok, op, ...)
    if ok then
        if op == "RETURN" then
            c.send(source, 1, session, true, ...)
        elseif op == "EXIT" then
            -- do nothing
        elseif op == "WAIT" then
            new_task(source, session, co, ...)
        else
            error("Unknown op : " .. op)
        end
    elseif source then
        c.send(source, 1, session, false, op)
    else
        print(cell.self, op, ...)
        print(debug.traceback(co))
    end
end

cell.suspend = suspend

local function resume_co(session, ...)
    local co = task_coroutine[session]
    if co == nil then
        error("Unknown response : " .. tostring(session))
    end
    local reply_session = task_session[session]
    local reply_addr = task_source[session]
    task_coroutine[session] = nil
    task_session[session] = nil
    task_source[session] = nil
    suspend(reply_addr, reply_session, co, coroutine.resume(co, ...))
end

local function deliver_event()
    while next(event_q1) do
        event_q1, event_q2 = event_q2, event_q1
        for i = 1, #event_q2 do
            local ok, err = pcall(resume_co, event_q2[i])
            if not ok then
                print(cell.self, err)
            end
            event_q2[i] = nil
        end
    end
end

function cell.dispatch(dispatcher)
    local msg_type = assert(dispatcher.msg_type)
    assert(dispatcher.dispatch and type(dispatcher.dispatch) == "function")
    msg_dispatchers[msg_type] = dispatcher
end

function cell.get_dispatch(msg_type)
    return msg_dispatchers[msg_type].dispatch
end

function cell.event()
    session = session + 1
    return session
end

function cell.call(addr, ...)
    -- command
    session = session + 1
    if not c.send(addr, 2, cell.self, session, ...) then
        error("call error " .. addr)
    end
    return select(2, assert(coroutine.yield("WAIT", session)))
end

function cell.rawcall(addr, session, ...)
    if not c.send(addr, ...) then
        error("rawcall error " .. addr)
    end
    return select(2, assert(coroutine.yield("WAIT", session)))
end

function cell.cmd(...)
    return cell.call(system, ...)
end

function cell.newservice(service_path, ...)
    return cell.cmd("launch", service_path, ...)
end

function cell.uniqueservice(service_path)
    return cell.cmd("uniquelaunch", service_path)
end

function cell.wakeup(event)
    table.insert(event_q1, event)
end

function cell.fork(func, ...)
    local n = select("#", ...)
    local co
    if n == 0 then
        co =
            co_create(
            function()
                func()
                return "EXIT"
            end
        )
    else
        local args = {...}
        co =
            co_create(
            function()
                func(table.unpack(args, 1, n))
                return "EXIT"
            end
        )
    end
    session = session + 1
    new_task(nil, nil, co, session)
    cell.wakeup(session)
    return co
end

function cell.send(addr, ...)
    -- message
    return c.send(addr, 3, ...)
end

function cell.wait(event)
    coroutine.yield("WAIT", event)
end

function cell.exit()
    cell.send(system, "kill", self)
    -- no return
    cell.wait(cell.event())
end

function cell.sleep(ti)
    session = session + 1
    c.send(system, 2, self, session, "timeout", ti)
    coroutine.yield("WAIT", session)
end

function cell.yield()
    cell.sleep(0)
end

function cell.timeout(ti, f)
    local co =
        co_create(
        function()
            f()
            return "EXIT"
        end
    )
    session = session + 1
    c.send(system, 2, self, session, "timeout", ti)
    new_task(nil, nil, co, session)
end

function cell.command(cmdfuncs)
    command = cmdfuncs
end

function cell.message(msgfuncs)
    message = msgfuncs
end

function cell.main()
end

cell.dispatch {
    msg_type = 5, -- exit
    dispatch = function()
        local err = tostring(self) .. " is dead"
        for event, session in pairs(task_session) do
            local source = task_source[event]
            if source ~= self then
                c.send(source, 1, session, false, err)
            end
        end
    end
}

cell.dispatch {
    msg_type = 4, -- launch
    dispatch = function(source, session, report, ...)
        local op = report and "RETURN" or "EXIT"
        local co =
            co_create(
            function(...)
                return op, cell.main(...)
            end
        )
        suspend(source, session, co, coroutine.resume(co, ...))
    end
}

cell.dispatch {
    msg_type = 3, -- message
    dispatch = function(cmd, ...)
        local f = message[cmd]
        if f == nil then
            print("Unknown message ", cmd)
        else
            local co =
                co_create(
                function(...)
                    return "EXIT", f(...)
                end
            )
            suspend(nil, nil, co, coroutine.resume(co, ...))
        end
    end
}

cell.dispatch {
    msg_type = 2, -- command
    dispatch = function(source, session, cmd, ...)
        local f = command[cmd]
        if f == nil then
            c.send(source, 1, session, false, "Unknown command " .. cmd)
        else
            local co =
                co_create(
                function(...)
                    return "RETURN", f(...)
                end
            )
            suspend(source, session, co, coroutine.resume(co, ...))
        end
    end
}

cell.dispatch {
    msg_type = 1, -- response
    dispatch = function(session, ...)
        resume_co(session, ...)
    end
}

c.dispatch(
    function(msg_type, ...)
        local dispatcher = msg_dispatchers[msg_type]
        if dispatcher == nil then
            deliver_event()
            error("Unknown msg_type : " .. msg_type)
        end
        dispatcher.dispatch(...)
        deliver_event()
    end
)

return cell
