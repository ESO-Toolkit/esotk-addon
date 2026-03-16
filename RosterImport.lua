-- ESOtk RosterImport - Roster data import and storage
-- Accepts Base64-encoded JSON roster strings via slash command, persists to
-- SavedVariables.
-- ESO-654

ESOtk = ESOtk or {}
ESOtk.RosterImport = {}

local RosterImport = ESOtk.RosterImport
local Util  -- resolved lazily

--- Resolve lazy references to other modules.
local function EnsureUtil()
    if not Util then Util = ESOtk.Util end
end

--- Return the rosters table from SavedVariables (creates if missing).
--- @return table
local function GetRosters()
    local sv = ESOtk.savedVars
    -- Explicit write-back forces ZO_SavedVars to store the table via
    -- __newindex.  Without this, sv.rosters returns the default {} through
    -- the __index metatable and mutations to it are never persisted to disk.
    sv.rosters = sv.rosters or {}
    return sv.rosters
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

--- Basic structural validation of a decoded roster table.
--- @param roster table
--- @return boolean ok
--- @return string|nil errorMessage
function RosterImport.ValidateRoster(roster)
    if type(roster) ~= "table" then
        return false, "Roster data is not a table."
    end
    if not roster.rosterName or roster.rosterName == "" then
        return false, "Roster is missing a 'rosterName' field."
    end
    -- Verify at least some slot data exists (tanks, healers, or dps)
    local hasSlots = roster.tank1 or roster.tank2
        or roster.healer1 or roster.healer2
        or (roster.dpsSlots and #roster.dpsSlots > 0)
    if not hasSlots then
        return false, "Roster has no player slots (tank/healer/dps)."
    end
    return true, nil
end

-- ---------------------------------------------------------------------------
-- Import / decode
-- ---------------------------------------------------------------------------

--- Decode a Base64url-encoded JSON string into a roster table.
--- @param encoded string  Base64url-encoded JSON
--- @return table|nil  roster
--- @return string|nil error
function RosterImport.DecodeRoster(encoded)
    EnsureUtil()

    -- Strip any whitespace the user may have included
    encoded = encoded:gsub("%s", "")
    if encoded == "" then
        return nil, "No data provided."
    end

    -- Decode Base64URL → JSON string
    local ok, jsonStr = pcall(Util.Base64UrlDecode, encoded)
    if not ok or not jsonStr or jsonStr == "" then
        -- Fall back to standard base64 in case the user used that
        ok, jsonStr = pcall(Util.Base64Decode, encoded)
        if not ok or not jsonStr or jsonStr == "" then
            return nil, "Failed to decode Base64 data."
        end
    end

    -- Parse JSON → Lua table
    local ok2, roster = pcall(Util.JsonDecode, jsonStr)
    if not ok2 or not roster then
        return nil, "Failed to parse JSON: " .. tostring(roster)
    end

    return roster, nil
end

--- Import a roster from a Base64-encoded JSON string and store it.
--- @param data string  Base64url-encoded JSON roster
function RosterImport.Import(data)
    EnsureUtil()

    if not data or Util.Trim(data) == "" then
        Util.Error("Usage: /esotk roster import <base64-encoded roster data>")
        return
    end

    local roster, err = RosterImport.DecodeRoster(data)
    if not roster then
        Util.Error("Import failed: " .. (err or "unknown error"))
        return
    end

    local valid, validErr = RosterImport.ValidateRoster(roster)
    if not valid then
        Util.Error("Invalid roster: " .. validErr)
        return
    end

    -- Store by roster name (overwrite if already exists)
    local rosters = GetRosters()
    local name = roster.rosterName
    local isUpdate = rosters[name] ~= nil
    roster.importedAt = GetTimeStamp and GetTimeStamp() or os.time()
    rosters[name] = roster

    if isUpdate then
        Util.Print("Roster '" .. name .. "' updated.")
    else
        Util.Print("Roster '" .. name .. "' imported successfully.")
    end

    -- Auto-validate immediately if the setting is on and we're in a group
    local sv = ESOtk.savedVars
    if sv and sv.autoValidate then
        local GroupScanner   = ESOtk.GroupScanner
        local RosterValidator = ESOtk.RosterValidator
        local Overlay         = ESOtk.ValidationOverlay
        if GroupScanner and RosterValidator then
            local members, groupSize = GroupScanner.ScanGroup()
            if groupSize > 0 then
                local result = RosterValidator.Validate(roster, members, groupSize)
                RosterValidator.lastResult = result
                if Overlay and Overlay.IsShowing and Overlay.IsShowing() then
                    Overlay.Populate(result)
                else
                    local ValidationUI = ESOtk.ValidationUI
                    if ValidationUI and ValidationUI.DisplaySummary then
                        ValidationUI.DisplaySummary(result)
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- List / delete / clear
-- ---------------------------------------------------------------------------

--- List all stored rosters.
function RosterImport.List()
    EnsureUtil()
    local rosters = GetRosters()
    if Util.IsEmpty(rosters) then
        Util.Print("No rosters stored.")
        return
    end

    local count = 0
    for name, roster in pairs(rosters) do
        count = count + 1
        local slots = 0
        if roster.tank1   then slots = slots + 1 end
        if roster.tank2   then slots = slots + 1 end
        if roster.healer1 then slots = slots + 1 end
        if roster.healer2 then slots = slots + 1 end
        if roster.dpsSlots then slots = slots + #roster.dpsSlots end
        Util.Print(string.format("  %d. %s (%d slots)", count, name, slots))
    end
    Util.Print("Total: " .. count .. " roster(s).")
end

--- Delete a single roster by name.
--- @param name string  Roster name to delete
function RosterImport.Delete(name)
    EnsureUtil()
    local rosters = GetRosters()
    if not rosters[name] then
        Util.Error("Roster '" .. name .. "' not found.")
        return
    end
    rosters[name] = nil
    Util.Print("Roster '" .. name .. "' deleted.")
end

--- Clear all stored rosters.
function RosterImport.Clear()
    EnsureUtil()
    local sv = ESOtk.savedVars
    sv.rosters = {}
    Util.Print("All rosters cleared.")
end

--- Get a stored roster by name.
--- @param name string
--- @return table|nil
function RosterImport.Get(name)
    return GetRosters()[name]
end

--- Get all stored rosters.
--- @return table  Map of rosterName → roster
function RosterImport.GetAll()
    return GetRosters()
end

-- ---------------------------------------------------------------------------
-- Slash command handler
-- ---------------------------------------------------------------------------

--- Handle /esotk roster <subcommand> commands.
--- @param args string  Remaining arguments after "roster"
function RosterImport.HandleCommand(args)
    EnsureUtil()
    local subcommand = args and args:match("^(%S+)") or ""
    subcommand = subcommand:lower()

    if subcommand == "import" then
        RosterImport.Import(args:match("^%S+%s*(.*)$") or "")
    elseif subcommand == "list" then
        RosterImport.List()
    elseif subcommand == "delete" then
        local name = args:match("^%S+%s+(.+)$")
        if name then
            RosterImport.Delete(Util.Trim(name))
        else
            Util.Error("Usage: /esotk roster delete <roster name>")
        end
    elseif subcommand == "clear" then
        RosterImport.Clear()
    else
        Util.Print("Roster commands:")
        Util.Print("  import <base64data>  — Import a roster")
        Util.Print("  list                 — List stored rosters")
        Util.Print("  delete <name>        — Delete a roster")
        Util.Print("  clear                — Remove all rosters")
    end
end
