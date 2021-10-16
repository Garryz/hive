local cell = require "cell"
local socket = require "socket"

local function accepter(fd, addr, listen_fd)
    print("Accept from ", listen_fd)
    -- can't read fd in this function, because socket.cell haven't forward data from fd
    local client = cell.cmd("launch", "test.session", fd, addr)
    -- return cell the data from fd will forward to, you can also return nil for forwarding to self
    print("accept", fd, addr, client)
    return client
end

local session_agents = {}
local client_agents = {}

-- local function accepter(fd, addr, listen_fd)
--     print("Accept from ", listen_fd, fd, addr)
--     local agent = session_agents[fd % 200]
--     cell.send(agent, "forward", fd, addr, listen_fd)
--     return agent
-- end

local servers = {}
local clients = {}

local function random_str(len)
    math.randomseed(os.time())
    local len = math.random(0, len)
    local rand_table = {}
    for i = 1, len do
        local rand_num = math.random(1, 3)
        if rand_num == 1 then
            rand_num = string.char(math.random(0, 25) + 65)
        elseif rand_num == 2 then
            rand_num = string.char(math.random(0, 25) + 97)
        else
            rand_num = math.random(0, 9)
        end
        table.insert(rand_table, rand_num)
    end
    return table.concat(rand_table)
end

function cell.main()
    print("[cell main]", cell.self, cell.id, cell.time())

    -- print(cell.cmd("echo", "Hello world"))
    -- local ping, pong = cell.cmd("launch", "test.pingpong", "pong")
    -- print(ping, pong)
    -- print(cell.call(ping, "ping"))
    -- cell.fork(function()
    --     cell.sleep(9000)
    --     print("run in fork coroutine")
    --     cell.cmd("kill", ping)
    -- end)
    -- cell.exit()

    -- local server = socket.listen("0.0.0.0", 8888, accepter)
    -- print("cell.main 1")
    -- local sock, err = socket.connect("127.0.0.1", 8888)
    -- print(sock, err)
    -- cell.sleep(60000)
    -- print("session write 1")
    -- sock:write("test\n")
    -- cell.sleep(60000)
    -- print("session write 2")
    -- sock:write("test\n")
    -- -- sock:disconnect()
    -- -- local line = sock:readline("\n")
    -- -- print("session read", line)
    -- -- sock:write(line .. "\n")
    -- -- -- server:disconnect()
    -- -- sock:disconnect()
    -- -- local function f()
    -- --     collectgarbage("count")
    -- --     cell.timeout(1000, f)
    -- -- end
    -- -- cell.timeout(1000, f)
    -- -- cell.exit()
    -- print("exit")

    local server = socket.listen("127.0.0.1", 8888, accepter)
    servers[server.__fd] = server
    -- for i = 1, 10000 do
    table.insert(clients, cell.cmd("launch", "test.client"))
    -- end

    -- for i = 1, 200 do
    --     table.insert(session_agents, cell.newservice("test.session_agent"))
    -- end
    -- local server = socket.listen("127.0.0.1", 8888, accepter)
    -- for i = 1, 200 do
    --     table.insert(client_agents, cell.newservice("test.client_agent"))
    -- end

    -- print(cell.uniqueservice("test.session_agent"))
    -- print(cell.uniqueservice("test.session_agent"))

    print(cell.uniqueservice("test.pingpong", "ping pong"))
    print(cell.uniqueservice("test.pingpong", "pong ping"))
    print(cell.call("pingpong", "ping", "ping"))
end
