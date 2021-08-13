--- Hotfix helper which hotfixes modified modules.

local M = {}

local hotfix = require("hotfix.hotfix")
local log = require("log")

-- global_objects which must not hotfix.
local global_objects = {
    arg,
    assert,
    collectgarbage,
    coroutine,
    debug,
    dofile,
    error,
    getmetatable,
    io,
    ipairs,
    load,
    loadfile,
    math,
    next,
    os,
    package,
    pairs,
    pcall,
    print,
    rawequal,
    rawget,
    rawlen,
    rawset,
    require,
    select,
    setmetatable,
    string,
    table,
    tonumber,
    tostring,
    type,
    utf8,
    xpcall
}

function M.update(module_names)
    for _, module_name in pairs(module_names) do
        hotfix.hotfix_module(module_name)
    end
end

function M.init()
    hotfix.log_error = function(s)
        log.error(s)
    end
    hotfix.log_info = function(s)
        log.info(s)
    end
    hotfix.log_debug = function(s)
        log.debug(s)
    end
    hotfix.add_protect(global_objects)
end

return M
