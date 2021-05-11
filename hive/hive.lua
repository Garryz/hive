package.cpath = "./luaclib/lib?.so;./luaclib/?.dll;./luaclib/lib?.dylib;" .. package.cpath
package.path = "./lualib/?.lua;" .. package.path

local c = require "hive.core"

local system_cell = assert(package.searchpath("service.system", package.path), "system cell was not found")
local socket_cell = assert(package.searchpath("service.network", package.path), "socket cell was not found")

local hive = {}

function hive.start(t)
    local main = assert(package.searchpath(t.main, package.path), "main cell was not found")
    return c.start(t, system_cell, socket_cell, main)
end

return hive
