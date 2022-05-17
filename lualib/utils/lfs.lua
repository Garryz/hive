local lfs = require "lfs"

local m = {}

local function isFilterFile(file)
    return file == "." or file == ".." or file == ".git" or file == ".DS_Store"
end

local function getFiles(path, fileList, upperDir)
    path = path:rtrim("/")
    if not lfs.attributes(path) then
        return
    end

    fileList = fileList or {}
    for file in lfs.dir(path) do
        if not isFilterFile(file) then
            local f = path .. "/" .. file
            local attr = lfs.attributes(f)
            local filename = file
            if upperDir then
                filename = string.format("%s/%s", upperDir, filename)
            end

            if attr.mode == "directory" then
                getFiles(f, fileList, filename)
            else
                table.insert(fileList, filename)
            end
        end
    end
end

function m.getLuaFiles(path)
    local fileList = {}
    getFiles(path, fileList)
    local res = {}
    -- 去掉.lua后缀
    for _, file in ipairs(fileList) do
        local luaFile = file:match("(.+).lua+$")
        if luaFile then
            table.insert(res, luaFile)
        end
    end
    return res
end

function m.getFiles(path)
    local fileList = {}
    getFiles(path, fileList)
    return fileList
end

function m.createPath(path)
    local attr = lfs.attributes(path)
    if not attr then
        lfs.mkdir(path)
    end
end

function m.getFileModification(file)
    return lfs.attributes(file, "modification")
end

function m.getCurrentDir()
    return lfs.currentdir()
end

return m
