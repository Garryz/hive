do
    local mt = getmetatable("")
    local _index = mt.__index

    function mt.__index(s, ...)
        local k = ...
        if "number" == type(k) then
            return _index.sub(s, k, k)
        else
            return _index[k]
        end
    end
end

function string.firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

function string.firstToLower(str)
    return (str:gsub("^%u", string.lower))
end

function string.toUpperHump(str)
    return (str:gsub(
        "[^_]+",
        function(w)
            return (w:lower():gsub("^%l", string.upper))
        end
    ):gsub("_+", ""))
end

function string.toLowerHump(str)
    return string.firstToLower(string.toUpperHump(str))
end

function string.split(s, p)
    local rt = {}
    s:gsub(
        "[^" .. p .. "]+",
        function(w)
            table.insert(rt, w)
        end
    )
    return rt
end

function string.ltrim(s, c)
    return (s:gsub("^" .. (c or "%s") .. "+", ""))
end

function string.rtrim(s, c)
    return (s:gsub((c or "%s") .. "+" .. "$", ""))
end

function string.trim(s, c)
    return string.rtrim(string.ltrim(s, c), c)
end
