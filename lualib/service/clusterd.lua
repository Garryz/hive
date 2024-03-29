local cell = require "cell"
local socket = require "socket"
local env = require "env"
local log = require "log"

local table = table
local assert = assert
local string = string
local pcall = pcall
local ipairs = ipairs
local setmetatable = setmetatable
local io = io
local load = load
local type = type
local pairs = pairs

local command = {}

local node_address = {}
local node_sender = {}

local CLUSTERNAME = env.getconfig("cluster") or "./clustername.lua"

local connecting = {}

local function open_channel(t, key)
    local ct = connecting[key]
    if ct then
        local channel
        while ct do
            local event = cell.event()
            table.insert(ct, event)
            cell.wait(event)
            channel = ct.channel
            -- reload again if ct ~= nil
        end
        return assert(node_address[key] and channel)
    end
    ct = {}
    connecting[key] = ct
    local address = node_address[key]
    local succ, err, c
    if address then
        local host, port = string.match(address, "([^:]+):(.*)$")
        c = node_sender[key]
        if c == nil then
            c = cell.newservice("service.clustersender", host, port)
            if node_sender[key] then
                -- doublc check
                cell.kill(c)
                c = node_sender[key]
            else
                node_sender[key] = c
            end
        end

        succ, err = pcall(cell.call, c, "changenode", host, port)

        if succ then
            t[key] = c
            ct.channel = c
        else
            err = string.format("changenode [%s] (%s:%s) failed", key, host, port)
        end
    elseif address == false then
        c = node_sender[key]
        if c == nil then
            -- no sender, always succ
            succ = true
        else
            -- turn off the sender
            succ, err = pcall(cell.call, c, "changenode", false)
        end
    else
        err = string.format("cluster node [%s] is %s.", key, address == false and "down" or "absent")
    end
    connecting[key] = nil
    for _, event in ipairs(ct) do
        cell.wakeup(event)
    end
    if node_address[key] ~= address then
        return open_channel(t, key)
    end
    assert(succ, err)
    return c
end

local node_channel = setmetatable({}, {
    __index = open_channel
})

function command.sender(node)
    return node_channel[node]
end

local function loadconfig(tmp)
    if tmp == nil then
        tmp = {}
        if CLUSTERNAME then
            local f = assert(io.open(CLUSTERNAME))
            local source = f:read "*a"
            f:close()
            assert(load(source, "@" .. CLUSTERNAME, "t", tmp))()
        end
    end
    local reload = {}
    for name, address in pairs(tmp) do
        assert(address == false or type(address) == "string")
        if node_address[name] ~= address then
            -- address changed
            if node_sender[name] then
                -- reset connection if node_sender[name] exist
                node_channel[name] = nil
                table.insert(reload, name)
            end
            node_address[name] = address
        end
    end
    for _, name in ipairs(reload) do
        -- open_channel would block
        cell.fork(open_channel, node_channel, name)
    end
end

function command.reload(config)
    loadconfig(config)
end

local cluster_gate = {} -- gatename : serversock
local cluster_agent = {} -- fd : service

local function accepter(fd, addr, listen_fd)
    log.infof("soket accept from %s", addr)
    local agent = cell.newservice("service.clusteragent", fd)
    cluster_agent[fd] = agent
    return agent
end

function command.listen(addr, port)
    local gatename = port
    if port == nil then
        local address = assert(node_address[addr], addr .. " is down")
        gatename = addr
        addr, port = string.match(address, "([^:]+):(.*)$")
    end
    cluster_gate[gatename] = socket.listen(addr, tonumber(port), accepter)
end

local register_name = {}

local function clearnamecache()
    for _, service in pairs(cluster_agent) do
        if type(service) == "userdata" then
            cell.send(service, "namechange")
        end
    end
end

function command.register(name, service)
    assert(register_name[name] == nil)
    local old_name = register_name[service]
    if old_name then
        register_name[old_name] = nil
        clearnamecache()
    end
    register_name[service] = name
    register_name[name] = service
    log.infof("Register [%s] :%s", name, service)
end

function command.queryname(name)
    return register_name[name]
end

function command.closeagent(fd)
    cluster_agent[fd] = nil
end

cell.command(command)

function cell.main()
    loadconfig()
end
