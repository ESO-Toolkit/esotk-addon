-- ESOtk Util - Shared utilities
-- Loaded before all other modules

ESOtk = ESOtk or {}
ESOtk.Util = {}

local Util = ESOtk.Util

--- Print a message to chat with the addon prefix.
--- Suppressed when verbose mode is off.
--- @param msg string
function Util.Print(msg)
    if ESOtk.savedVars and not ESOtk.savedVars.verbose then return end
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
--- Uses a lookup table for ~10-20x faster decoding vs the old bit-string approach.
--- @param data string  Base64-encoded input
--- @return string       Decoded output
local B64_LOOKUP = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do B64_LOOKUP[chars:sub(i, i)] = i - 1 end
end

function Util.Base64Decode(data)
    data = data:gsub("[^A-Za-z0-9%+/=]", "")
    local parts = {}
    for i = 1, #data, 4 do
        local a = B64_LOOKUP[data:sub(i, i)] or 0
        local b = B64_LOOKUP[data:sub(i + 1, i + 1)] or 0
        local c = B64_LOOKUP[data:sub(i + 2, i + 2)]
        local d = B64_LOOKUP[data:sub(i + 3, i + 3)]
        parts[#parts + 1] = string.char(a * 4 + math.floor(b / 16))
        if c then
            parts[#parts + 1] = string.char((b % 16) * 16 + math.floor(c / 4))
        end
        if d then
            parts[#parts + 1] = string.char((c % 4) * 64 + d)
        end
    end
    return table.concat(parts)
end

--- Decode a Base64URL string (URL-safe variant used by the web UI).
--- Converts Base64URL chars to standard Base64 and pads, then decodes.
--- @param data string  Base64URL-encoded input
--- @return string       Decoded output
function Util.Base64UrlDecode(data)
    -- Replace URL-safe characters with standard Base64 equivalents
    data = data:gsub("-", "+"):gsub("_", "/")
    -- Pad to multiple of 4
    local remainder = #data % 4
    if remainder > 0 then
        data = data .. string.rep("=", 4 - remainder)
    end
    return Util.Base64Decode(data)
end

-- ---------------------------------------------------------------------------
-- Minimal JSON parser (decode only)
-- ESO Lua has no built-in JSON library. This handles the subset of JSON
-- produced by the web UI roster export.
-- ---------------------------------------------------------------------------

local JsonDecode  -- forward declaration

local function skipWhitespace(s, pos)
    return s:match("^%s*()", pos)
end

local function decodeString(s, pos)
    -- pos should point at the opening quote
    assert(s:sub(pos, pos) == '"', "Expected '\"' at position " .. pos)
    pos = pos + 1
    local parts = {}
    while pos <= #s do
        local c = s:sub(pos, pos)
        if c == '"' then
            return table.concat(parts), pos + 1
        elseif c == "\\" then
            pos = pos + 1
            local esc = s:sub(pos, pos)
            if     esc == '"' then parts[#parts + 1] = '"'
            elseif esc == "\\" then parts[#parts + 1] = "\\"
            elseif esc == "/"  then parts[#parts + 1] = "/"
            elseif esc == "n"  then parts[#parts + 1] = "\n"
            elseif esc == "r"  then parts[#parts + 1] = "\r"
            elseif esc == "t"  then parts[#parts + 1] = "\t"
            elseif esc == "u"  then
                local hex = s:sub(pos + 1, pos + 4)
                parts[#parts + 1] = string.char(tonumber(hex, 16))
                pos = pos + 4
            end
            pos = pos + 1
        else
            parts[#parts + 1] = c
            pos = pos + 1
        end
    end
    error("Unterminated string")
end

local function decodeNumber(s, pos)
    local numStr = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*()", pos)
    if not numStr then error("Invalid number at position " .. pos) end
    local endPos = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*()", pos)
    local raw = s:sub(pos, endPos - 1)
    return tonumber(raw), endPos
end

local function decodeArray(s, pos)
    -- pos points at '['
    pos = skipWhitespace(s, pos + 1)
    local arr = {}
    if s:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
        local val
        val, pos = JsonDecode(s, pos)
        arr[#arr + 1] = val
        pos = skipWhitespace(s, pos)
        local c = s:sub(pos, pos)
        if c == "]" then return arr, pos + 1 end
        if c ~= "," then error("Expected ',' or ']' at position " .. pos) end
        pos = skipWhitespace(s, pos + 1)
    end
end

local function decodeObject(s, pos)
    -- pos points at '{'
    pos = skipWhitespace(s, pos + 1)
    local obj = {}
    if s:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        local key
        key, pos = decodeString(s, pos)
        pos = skipWhitespace(s, pos)
        assert(s:sub(pos, pos) == ":", "Expected ':' at position " .. pos)
        pos = skipWhitespace(s, pos + 1)
        local val
        val, pos = JsonDecode(s, pos)
        obj[key] = val
        pos = skipWhitespace(s, pos)
        local c = s:sub(pos, pos)
        if c == "}" then return obj, pos + 1 end
        if c ~= "," then error("Expected ',' or '}' at position " .. pos) end
        pos = skipWhitespace(s, pos + 1)
    end
end

JsonDecode = function(s, pos)
    pos = skipWhitespace(s, pos or 1)
    local c = s:sub(pos, pos)
    if c == '"'       then return decodeString(s, pos)
    elseif c == "{"   then return decodeObject(s, pos)
    elseif c == "["   then return decodeArray(s, pos)
    elseif c == "t"   then
        assert(s:sub(pos, pos + 3) == "true", "Invalid literal at " .. pos)
        return true, pos + 4
    elseif c == "f"   then
        assert(s:sub(pos, pos + 4) == "false", "Invalid literal at " .. pos)
        return false, pos + 5
    elseif c == "n"   then
        assert(s:sub(pos, pos + 3) == "null", "Invalid literal at " .. pos)
        return nil, pos + 4
    else
        return decodeNumber(s, pos)
    end
end

--- Decode a JSON string into a Lua table/value.
--- @param s string  JSON string
--- @return any       Decoded Lua value
function Util.JsonDecode(s)
    if not s or s == "" then
        error("Empty JSON input")
    end
    local val, pos = JsonDecode(s, 1)
    return val
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

--- Strip emoji and non-ASCII symbols from a string.
--- ESO fonts support ASCII and 2-byte Latin Extended (accented chars like ñ, ü).
--- All 3-byte (U+0800+) and 4-byte (U+10000+) sequences render as boxes.
--- @param s string
--- @return string
function Util.StripEmoji(s)
    if not s then return "" end
    -- Remove 4-byte UTF-8 sequences (U+10000+): F0-F4 followed by 3 continuation bytes
    s = s:gsub("[\xF0-\xF4][\x80-\xBF][\x80-\xBF][\x80-\xBF]", "")
    -- Remove ALL 3-byte UTF-8 sequences (U+0800-U+FFFF): E0-EF followed by 2 continuation bytes
    s = s:gsub("[\xE0-\xEF][\x80-\xBF][\x80-\xBF]", "")
    -- Remove orphaned continuation bytes that lost their leading byte
    s = s:gsub("[\x80-\xBF]+", "")
    -- Collapse multiple spaces into one, trim
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end
