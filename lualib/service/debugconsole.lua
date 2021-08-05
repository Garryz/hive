local cell = require "cell"
local socket = require "socket"
local log = require "log"

local COMMAND = {}
local COMMANDX = {}

local function format_table(t)
    local index = {}
    for k in pairs(t) do
        table.insert(index, k)
    end
    table.sort(
        index,
        function(a, b)
            return tostring(a) < tostring(b)
        end
    )
    local result = {}
    for _, v in ipairs(index) do
        table.insert(result, string.format("%s:%s", v, tostring(t[v])))
    end
    return table.concat(result, "\t")
end

local function dump_line(print, key, value)
    if type(value) == "table" then
        print(key, format_table(value))
    else
        print(key, tostring(value))
    end
end

local function dump_list(print, list)
    local index = {}
    for k in pairs(list) do
        table.insert(index, k)
    end
    table.sort(
        index,
        function(a, b)
            return tostring(a) < tostring(b)
        end
    )
    for _, v in ipairs(index) do
        dump_line(print, v, list[v])
    end
end

local function split_cmdline(cmdline)
    local split = {}
    for i in string.gmatch(cmdline, "%S+") do
        table.insert(split, i)
    end
    return split
end

local function docmd(cmdline, print)
    local split = split_cmdline(cmdline)
    local command = split[1]
    local cmd = COMMAND[command]
    local ok, list
    if cmd then
        ok, list = pcall(cmd, table.unpack(split, 2))
    else
        cmd = COMMANDX[command]
        if cmd then
            ok, list = pcall(cmd, cmdline)
        else
            print("Invalid command, type help for command list")
        end
    end

    if ok then
        if list then
            if type(list) == "string" then
                print(list)
            else
                dump_list(print, list)
            end
        end
        print("<CMD OK>")
    else
        print(list)
        print("<CMD Error>")
    end
end

local function console_main_loop(stdin, print, addr)
    print("Welcome to hive console")
    log.info(addr, "connected")
    local ok, err =
        pcall(
        function()
            while true do
                local cmdline = stdin:readline("\n")
                if not cmdline then
                    break
                end
                if cmdline ~= "" then
                    docmd(cmdline, print)
                end
            end
        end
    )
    if not ok then
        log.error(stdin, err)
    end
    log.info(addr, "disconnect")
    stdin:disconnect()
end

function cell.main(port)
    local ip = "127.0.0.1"
    socket.listen(
        ip,
        tonumber(port),
        function(fd, addr, listen_fd)
            local sock = socket.bind(fd)
            local function print(...)
                local t = {...}
                for k, v in ipairs(t) do
                    t[k] = tostring(v)
                end
                sock:write(table.concat(t, "\t"))
                sock:write("\n")
            end
            cell.fork(console_main_loop, sock, print, addr)
        end
    )
    print("Start debug console at " .. ip .. ":" .. port)
end

function cell.info()
    return "debug console"
end

function COMMAND.help()
    return {
        help = "This help message",
        list = "List all the service",
        stat = "Dump all stats",
        info = "info id : get service information",
        kill = "kill id : kill service",
        mem = "mem : show memory status",
        gc = "gc : force every lua service do garbage collect",
        start = "start service_path args : lanuch a new lua service, args like 'a',1,{} ",
        call = "call id cmd args : args like 'a',1,{} "
    }
end

function COMMAND.list()
    return cell.cmd("list")
end

function COMMAND.stat()
    return cell.cmd("stat")
end

function COMMAND.info(id)
    if id then
        id = tonumber(id)
    end
    if not id or id <= 0 then
        error "id invalid"
    end
    return cell.cmd("info", id)
end

function COMMAND.kill(id)
    if id then
        id = tonumber(id)
    end
    if not id or id <= 0 then
        error "id invalid"
    end
    return cell.cmd("killid", id)
end

function COMMAND.mem()
    return cell.cmd("mem")
end

function COMMAND.gc()
    return cell.cmd("gc")
end

function COMMANDX.start(cmdline)
    local service_path, cmdline = cmdline:match("%S+%s+(%S+)%s*(.*)")
    local args_func = assert(load("return " .. cmdline, "debug console", "t", {}), "Invalid arguments")
    local args = table.pack(pcall(args_func))
    if not args[1] then
        error(args[2])
    end
    local ok, c = pcall(cell.newservice, service_path, table.unpack(args, 2, args.n))
    if ok then
        if c then
            return {[tostring(c)] = service_path}
        else
            return "Exit"
        end
    else
        return "Failed, " .. c
    end
end

function COMMANDX.call(cmdline)
    local id, cmd, cmdline = cmdline:match("%S+%s+(%S+)%s+(%S+)%s*(.*)")
    if id then
        id = tonumber(id)
    end
    if not id or id <= 0 then
        error "id invalid"
    end
    local args_func = assert(load("return " .. cmdline, "debug console", "t", {}), "Invalid arguments")
    local args = table.pack(pcall(args_func))
    if not args[1] then
        error(args[2])
    end
    return table.pack(cell.cmd("call", id, cmd, table.unpack(args, 2, args.n)))
end
