local cell = require "cell"

cell.command {
    ping = function()
        return "pong"
    end
}

function cell.main(...)
    print("pingpong launched")
    cell.register("pingpong")
    return ...
end
