local cell = require "cell"
local httpc = require "http.httpc"

local function http_test(protocol)
    print("GET baidu.com")
    protocol = protocol or "http"
    local respheader = {}
    local host = string.format("%s://baidu.com", protocol)
    print("geting... " .. host)
    local status, body = httpc.get(host, "/", respheader, nil, 1000)
    print("[header] =====>")
    for k, v in pairs(respheader) do
        print(k, v)
    end
    print("[body] =====>", status)
    print(body)
end

function cell.main()
    http_test("http")
    http_test("https")
end
