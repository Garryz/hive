package.path = "./lualib/?.lua;./lualib/?/init.lua;" .. package.path

require "utils.string"

local str = "string"
print(str[1])

print(str:firstToUpper())

str = "String"
print(str:firstToUpper())

print(str:firstToLower())

print(str:firstToLower())

str = "STRING_STRING"
print(str:toUpperHump())

str = "StringString"
print(str:toUpperHump())

str = "STRING_STRING"
print(str:toLowerHump())

local result = str:split("_")
for _, v in ipairs(result) do
    print(v)
end

str = "||string||"
print(str:ltrim("|"))

print(str:rtrim("|"))

print(str:trim("|"))

local t = {
    [1] = 1,
    a = "b",
    f = function()
    end,
    t = {}
}
print(string.toString(t))
