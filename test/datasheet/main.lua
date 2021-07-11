local cell = require "cell"

function cell.main()
    cell.newservice("test.datasheet.service")
    cell.newservice("test.datasheet.service", "child")
end
