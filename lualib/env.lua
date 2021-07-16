local datasheet = require "datasheet"

local env = {}

function env.getenv()
    return datasheet.query("__HIVE_ENV")
end

function env.getconfig(key)
    return env.getenv()[key]
end

return env
