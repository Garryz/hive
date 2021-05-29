package.cpath = "./luaclib/lib?.so;./luaclib/?.dll;./luaclib/lib?.dylib;" .. package.cpath

local crypt = require "crypt"

local function sha1(text)
    local c = crypt.sha1(text)
    return crypt.hexencode(c)
end

local function sha256(text)
    local c = crypt.sha256(text)
    return crypt.hexencode(c)
end

local function md5(text)
    local c = crypt.md5(text)
    return crypt.hexencode(c)
end

print("sha1")
assert(sha1 "hive" == "801d027309b0f931b1c155dc9f844a295cd51a2b", "sha1")
print("sha256")
assert(sha256 "hive" == "7640da40298286a6e462d5a80f1c608b0df8660fb13bd5aad0f32b6db68b42c0", "sha256")
print("md5")
assert(md5 "hive" == "8a4ac216fb230da3834de641b3e5d0f7", "md5")
