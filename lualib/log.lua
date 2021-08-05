local c = require "cell.c"

local table = table

local log = {}

local function send(...)
    return c.send(c.logger, 3, ...)
end

local function sendlog(levelstr, ...)
    local strs = {}
    for _, v in ipairs({...}) do
        table.insert(strs, tostring(v))
    end
    return send(levelstr, table.concat(strs, " "))
end

local function setlevel(levelstr, flag)
    return send("enable" .. levelstr, flag and true or false)
end

function log.warning(...)
    sendlog("warning", ...)
end

function log.debug(...)
    sendlog("debug", ...)
end

function log.info(...)
    sendlog("info", ...)
end

function log.error(...)
    sendlog("error", ...)
end

function log.enableprint(flag)
    setlevel("print", flag)
end

function log.enablewarning(flag)
    setlevel("warning", flag)
end

function log.enabledebug(flag)
    setlevel("debug", flag)
end

function log.enableinfo(flag)
    setlevel("info", flag)
end

function log.enableerror(flag)
    setlevel("error", flag)
end

return log
