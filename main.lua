local config = {}

local function init_config()
    local config_file = assert(arg[1])
    assert(loadfile(config_file, "t", config))()
end

local function start()
    config.cpath = config.cpath or "./luaclib/lib?.so;./luaclib/?.dll;./luaclib/lib?.dylib;"
    config.path = config.path or "./lualib/?.lua;./lualib/?/init.lua;"

    package.cpath = config.cpath .. package.cpath
    package.path = config.path .. package.path

    local c = require "hive.core"

    local system_cell = assert(package.searchpath("service.system", package.path), "system cell was not found")
    local socket_cell = assert(package.searchpath("service.network", package.path), "socket cell was not found")

    local main = assert(package.searchpath(config.main, package.path), "main cell was not found")
    local loader
    if config.loader then
        loader = assert(package.searchpath(config.loader, package.path), "loader was not found")
    end
    return c.start(config, system_cell, socket_cell, main, loader)
end

init_config()
start()
