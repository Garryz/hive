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

local function http_stream_test()
    for resp, stream in httpc.request_stream("GET", "http://baidu.com", "/") do
        print("STATUS", stream.status)
        for k, v in pairs(stream.header) do
            print("HEADER", k, v)
        end
        print("BODY", resp)
    end
end

local function http_head_test()
    local respheader = {}
    local status = httpc.head("http://baidu.com", "/", respheader, nil, nil, 1000)
    print("STATUS", status)
    for k, v in pairs(respheader) do
        print("HEAD", k, v)
    end
end

function cell.main()
    http_stream_test()
    http_head_test()
    http_test("http")
    http_test("https")
end
