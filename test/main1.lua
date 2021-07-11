local cell = require "cell"
local socket = require "socket"

local servers = {}
local clients = {}
local sessions = {}

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

local function accepter(fd, addr, listen_fd)
	print("Accept from ", listen_fd, fd, addr)
	local obj = socket.bind(fd)
	sessions[fd] = obj
	cell.fork(
		function()
			local str
			local line = obj:readline("\n")
			while line do
				str = random_str(1024)
				obj:write(str .. "\n")
				line = obj:readline("\n")
			end
		end
	)
end

function cell.main()
	print("[cell main]", cell.self)

	local server = socket.listen("127.0.0.1", 8888, accepter)
	servers[server.__fd] = server
	for i = 1, 10000 do
		cell.fork(
			function()
				local sock = socket.connect("127.0.0.1", 8888)
				clients[sock.__fd] = sock
				print("connect", sock.__fd)
				local str = random_str(1024)
				sock:write(str .. "\n")
				local line = sock:readline("\n")
				while line do
					str = random_str(1024)
					sock:write(str .. "\n")
					line = sock:readline("\n")
				end
			end
		)
	end
end
