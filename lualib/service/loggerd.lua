local cell = require "cell"
local c = require "cell.c"
local logger = require "logger"

local log = logger.new(c.logdir, c.logfile)

local message = {}

function message.warning(str)
    log:log(logger.level.warning, str)
end

function message.debug(str)
    log:log(logger.level.debug, str)
end

function message.info(str)
    log:log(logger.level.info, str)
end

function message.error(str)
    log:log(logger.level.error, str)
end

function message.enableprint(flag)
    log:enablelevel(logger.level.print, flag)
end

function message.enablewarning(flag)
    log:enablelevel(logger.level.warning, flag)
end

function message.enabledebug(flag)
    log:enablelevel(logger.level.debug, flag)
end

function message.enableinfo(flag)
    log:enablelevel(logger.level.info, flag)
end

function message.enableerror(flag)
    log:enablelevel(logger.level.error, flag)
end

cell.message(message)

cell.dispatch {
    msg_type = 11, -- send log
    dispatch = function(str)
        log:log(logger.level.error, str)
    end
}
