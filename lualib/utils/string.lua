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

function string.toString(v)
    local function dump(obj)
        local cache = {}
        local getIndent, quoteStr, wrapKey, wrapVal, dumpObj
        getIndent = function(level)
            return string.rep("\t", level)
        end
        quoteStr = function(str)
            return '"' .. string.gsub(str, '"', '\\"') .. '"'
        end
        wrapKey = function(val, level)
            local valType = type(val)
            if valType == "number" then
                return "[" .. val .. "]"
            elseif valType == "string" then
                return "[" .. quoteStr(val) .. "]"
            elseif valType == "table" then
                if cache[val] then
                    return "[" .. cache[val] .. "]"
                else
                    return "[" .. dumpObj(val, level, ".") .. "]"
                end
            else
                return "[" .. tostring(val) .. "]"
            end
        end
        wrapVal = function(val, level, path)
            local valType = type(val)
            if valType == "table" then
                return dumpObj(val, level, path)
            elseif valType == "number" then
                return val
            elseif valType == "string" then
                return quoteStr(val)
            else
                return tostring(val)
            end
        end
        dumpObj = function(obj, level, path)
            if type(obj) ~= "table" then
                return wrapVal(obj)
            end
            level = level + 1
            if cache[obj] then
                return cache[obj]
            end
            cache[obj] = string.format('"%s"', path)
            local tokens = {}
            tokens[#tokens + 1] = "{"
            for k, v in pairs(obj) do
                if type(k) == "table" then
                    tokens[#tokens + 1] =
                        getIndent(level) ..
                        wrapKey(k, level) .. " = " .. wrapVal(v, level, path .. cache[k] .. ".") .. ","
                else
                    tokens[#tokens + 1] =
                        getIndent(level) .. wrapKey(k, level) .. " = " .. wrapVal(v, level, path .. k .. ".") .. ","
                end
            end
            tokens[#tokens + 1] = getIndent(level - 1) .. "}"
            return table.concat(tokens, "\n")
        end
        return dumpObj(obj, 0, ".")
    end
    if type(v) == "table" then
        return dump(v)
    else
        return tostring(v)
    end
end
