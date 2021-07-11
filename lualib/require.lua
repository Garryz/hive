local coroutine = coroutine
local package = package
local loadfile = loadfile
local error = error
local ipairs = ipairs
local xpcall = xpcall

local M = {}

local mainthread, ismain = coroutine.running()
assert(ismain, "skynet.require must initialize in main thread")

local context = {[mainthread] = {}}

do
    local require = _G.require
    local loaded = package.loaded
    local loading = {}

    function M.require(name)
        local m = loaded[name]
        if m ~= nil then
            return m
        end

        local co, main = coroutine.running()
        if main then
            return require(name)
        end

        local filename = package.searchpath(name, package.path)
        if not filename then
            return require(name)
        end

        local modfunc = loadfile(filename)
        if not modfunc then
            return require(name)
        end

        local loading_queue = loading[name]
        if loading_queue then
            assert(loading_queue.co ~= co, "circular dependency")
            -- Module is in the init process (require the same mod at the same time in different coroutines) , waiting.
            local cell = require "cell"
            local event = cell.event()
            loading_queue[#loading_queue + 1] = event
            cell.wait(event)
            local m = loaded[name]
            if m == nil then
                error(string.format("require %s failed", name))
            end
            return m
        end

        loading_queue = {co = co}
        loading[name] = loading_queue

        local old_init_list = context[co]
        local init_list = {}
        context[co] = init_list

        -- We should call modfunc in lua, because modfunc may yield by calling M.require recursive.
        local function execute_module()
            local m = modfunc(name, filename)

            for _, f in ipairs(init_list) do
                f()
            end

            if m == nil then
                m = true
            end

            loaded[name] = m
        end

        local ok, err = xpcall(execute_module, debug.traceback)

        context[co] = old_init_list

        local waiting = #loading_queue
        if waiting > 0 then
            local cell = require "cell"
            for i = 1, waiting do
                cell.wakeup(loading_queue[i])
            end
        end
        loading[name] = nil

        if ok then
            return loaded[name]
        else
            error(err)
        end
    end
end

function M.init_all()
    for _, f in ipairs(context[mainthread]) do
        f()
    end
    context[mainthread] = nil
end

function M.init(f)
    assert(type(f) == "function")
    local co = coroutine.running()
    table.insert(context[co], f)
end

return M
