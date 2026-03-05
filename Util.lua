-- ESOtk Util - Shared utilities
-- Loaded before all other modules

ESOtk = ESOtk or {}
ESOtk.Util = {}

local Util = ESOtk.Util

--- Print a message to chat with the addon prefix.
--- @param msg string
function Util.Print(msg)
    d("[ESOtk] " .. tostring(msg))
end

--- Print a warning message to chat.
--- @param msg string
function Util.Warn(msg)
    d("[ESOtk] WARNING: " .. tostring(msg))
end

--- Print an error message to chat.
--- @param msg string
function Util.Error(msg)
    d("[ESOtk] ERROR: " .. tostring(msg))
end

--- Base64 decode a string.
--- @param data string  Base64-encoded input
--- @return string       Decoded output
function Util.Base64Decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = string.gsub(data, "[^" .. b .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (b:find(x) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do
            c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
    end))
end

--- Split a string by a delimiter.
--- @param str string
--- @param sep string  Separator pattern (default: "%s")
--- @return table       Array of substrings
function Util.Split(str, sep)
    sep = sep or "%s"
    local parts = {}
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(parts, part)
    end
    return parts
end

--- Trim leading and trailing whitespace.
--- @param str string
--- @return string
function Util.Trim(str)
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Check if a table is empty.
--- @param t table
--- @return boolean
function Util.IsEmpty(t)
    return next(t) == nil
end

--- Shallow copy a table.
--- @param t table
--- @return table
function Util.ShallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end
