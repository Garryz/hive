local cell = require "cell"
local udp = require "udp"

local function accepter(fd, addr, listen_fd)
    print("Accept from ", listen_fd)
    local client = cell.cmd("launch", "test.udp_session", fd, addr)
    print("accept", fd, addr, client)
    return client
end

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

    local server = udp.listen("127.0.0.1", 8888, accepter)
    servers[server.__fd] = server

    local client = udp.connect("127.0.0.1", 8888)
    print("client connect ", client)
    client:write(random_str(10))
    print("client read", client, client:read())
    client:write(random_str(100))
    print("client read", client, client:read())
    client:write(random_str(1400))
    print("client read", client, client:read())
    client:write(random_str(2000))
    print("client read", client, client:read())
end
