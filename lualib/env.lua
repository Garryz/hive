local c = require "cell.c"
local seri = require "hive.seri"

local config

local function init()
    config = seri.unpack(c.config, true)
end

init()

local env = {}

function env.getconfig(key)
    return config[key]
end

return env
