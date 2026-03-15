-- ESOtk RosterValidator - Validation engine
-- Compares imported roster data against the current group composition.
-- ESO-655

ESOtk = ESOtk or {}
ESOtk.RosterValidator = {}

local RosterValidator = ESOtk.RosterValidator
local Util, GroupScanner, RosterImport, ValidationUI  -- resolved lazily

--- Resolve lazy references to other modules.
local function EnsureModules()
    if not Util then
        Util           = ESOtk.Util
        GroupScanner   = ESOtk.GroupScanner
        RosterImport   = ESOtk.RosterImport
        ValidationUI   = ESOtk.ValidationUI
    end
end

--- Last validation result, kept for `/esotk validate status`.
RosterValidator.lastResult = nil

-- ---------------------------------------------------------------------------
-- Role mapping helpers
-- ---------------------------------------------------------------------------

--- Map roster role labels to GroupScanner role names.
local ROLE_LABEL_MAP = {
    tank   = "Tank",
    healer = "Healer",
    dps    = "DPS",
}

--- Infer the expected role from the roster slot key.
--- @param slotKey string  e.g. "tank1", "healer2", "dps"
--- @return string  Normalized role name ("Tank", "Healer", "DPS")
local function InferRole(slotKey)
    if slotKey:find("^tank")   then return "Tank" end
    if slotKey:find("^healer") then return "Healer" end
    return "DPS"
end

-- ---------------------------------------------------------------------------
-- Player matching
-- ---------------------------------------------------------------------------

--- Try to find a group member matching a roster slot's playerName.
--- Matches against character name first, then @account name (case-insensitive).
--- @param playerName string  Name from the roster slot
--- @param members table      Array of GroupScanner member data
--- @return table|nil         Matched member, or nil
local function FindMember(playerName, members)
    if not playerName or playerName == "" then return nil end
    local target = playerName:lower()
    for _, m in ipairs(members) do
        if m.rawName:lower() == target then return m end
    end
    for _, m in ipairs(members) do
        if m.displayName:lower() == target then return m end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Single-slot validation
-- ---------------------------------------------------------------------------

--- Validate a single roster slot against the group.
--- @param slotKey string       Slot identifier (e.g. "tank1", "healer2")
--- @param slotData table       Roster slot data (must have playerName)
--- @param members table        Array of GroupScanner member data
--- @param matchedTags table    Set of unitTags already matched (mutated)
--- @return table               Slot validation result
local function ValidateSlot(slotKey, slotData, members, matchedTags)
    local result = {
        slot       = slotKey,
        playerName = slotData.playerName or "(unnamed)",
        checks     = {},  -- array of { check, pass, detail }
        pass       = true,
    }

    local expectedRole = InferRole(slotKey)

    -- 1. Player Presence
    local member = FindMember(slotData.playerName, members)
    if not member then
        result.pass = false
        table.insert(result.checks, {
            check  = "presence",
            pass   = false,
            detail = slotData.playerName .. " is not in the group",
        })
        return result  -- can't check further without a match
    end

    -- Mark this member as matched
    matchedTags[member.unitTag] = true

    table.insert(result.checks, {
        check  = "presence",
        pass   = true,
        detail = member.rawName .. " (" .. member.displayName .. ") found",
    })

    -- 2. Role Match
    if member.role ~= expectedRole then
        result.pass = false
        table.insert(result.checks, {
            check  = "role",
            pass   = false,
            detail = "Expected " .. expectedRole .. ", has " .. member.role,
        })
    else
        table.insert(result.checks, {
            check  = "role",
            pass   = true,
            detail = expectedRole,
        })
    end

    -- 3. Class Match (if roster specifies expected class via skillLines)
    if slotData.className then
        if member.className ~= slotData.className then
            result.pass = false
            table.insert(result.checks, {
                check  = "class",
                pass   = false,
                detail = "Expected " .. slotData.className .. ", is " .. member.className,
            })
        else
            table.insert(result.checks, {
                check  = "class",
                pass   = true,
                detail = member.className,
            })
        end
    end

    -- 4. Online Status
    if not member.isOnline then
        result.pass = false
        table.insert(result.checks, {
            check  = "online",
            pass   = false,
            detail = "Player is offline",
        })
    else
        table.insert(result.checks, {
            check  = "online",
            pass   = true,
            detail = "Online in " .. (member.zoneName or "unknown zone"),
        })
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Full roster validation
-- ---------------------------------------------------------------------------

--- Collect all roster slots into a flat list of { key, data } pairs.
--- @param roster table  Roster data
--- @return table        Array of { key = string, data = table }
local function CollectSlots(roster)
    local slots = {}

    -- Named slots: tank1, tank2, healer1, healer2
    for _, key in ipairs({ "tank1", "tank2", "healer1", "healer2" }) do
        if roster[key] and roster[key].playerName then
            table.insert(slots, { key = key, data = roster[key] })
        end
    end

    -- DPS slots array
    if roster.dpsSlots then
        for i, dps in ipairs(roster.dpsSlots) do
            if dps and dps.playerName then
                table.insert(slots, { key = "dps" .. i, data = dps })
            end
        end
    end

    return slots
end

--- Run validation of a roster against the current group.
--- @param roster table    Roster data from RosterImport
--- @param members table   Array of GroupScanner member data
--- @param groupSize number
--- @return table          Validation result
function RosterValidator.Validate(roster, members, groupSize)
    local result = {
        rosterName      = roster.rosterName,
        timestamp       = GetTimeStamp and GetTimeStamp() or os.time(),
        groupSize       = groupSize,
        slotResults     = {},   -- per-slot validation results
        unassigned      = {},   -- group members with no roster slot
        emptySlots      = {},   -- roster slots with no matching member
        totalSlots      = 0,
        matchedSlots    = 0,
        passedSlots     = 0,
        overallPass     = true,
    }

    local matchedTags = {}  -- unitTags that have been matched to a slot
    local slots = CollectSlots(roster)
    result.totalSlots = #slots

    -- Validate each roster slot
    for _, slot in ipairs(slots) do
        local slotResult = ValidateSlot(slot.key, slot.data, members, matchedTags)
        table.insert(result.slotResults, slotResult)

        if slotResult.pass then
            result.passedSlots = result.passedSlots + 1
            result.matchedSlots = result.matchedSlots + 1
        else
            result.overallPass = false
            -- Check if the player was at least found (matched but failed other checks)
            for _, c in ipairs(slotResult.checks) do
                if c.check == "presence" and c.pass then
                    result.matchedSlots = result.matchedSlots + 1
                    break
                end
            end
        end
    end

    -- 5. Unassigned Players: group members not in any roster slot
    for _, member in ipairs(members) do
        if not matchedTags[member.unitTag] then
            table.insert(result.unassigned, {
                rawName     = member.rawName,
                displayName = member.displayName,
                role        = member.role,
                className   = member.className,
            })
        end
    end
    if #result.unassigned > 0 then
        result.overallPass = false
    end

    -- 6. Empty Slots: roster slots whose player was not found
    for _, sr in ipairs(result.slotResults) do
        for _, c in ipairs(sr.checks) do
            if c.check == "presence" and not c.pass then
                table.insert(result.emptySlots, {
                    slot       = sr.slot,
                    playerName = sr.playerName,
                })
                break
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Slash command integration
-- ---------------------------------------------------------------------------

--- Run validation against a named roster (or the only stored roster).
--- @param rosterName string  Optional roster name
function RosterValidator.Run(rosterName)
    EnsureModules()

    -- Resolve which roster to use
    local roster
    if rosterName and rosterName ~= "" then
        roster = RosterImport.Get(Util.Trim(rosterName))
        if not roster then
            Util.Error("Roster '" .. rosterName .. "' not found. Use /esotk roster list")
            return
        end
    else
        -- No name given; use the only roster if there's exactly one
        local all = RosterImport.GetAll()
        local count = 0
        local onlyName
        for name, _ in pairs(all) do
            count = count + 1
            onlyName = name
        end
        if count == 0 then
            Util.Error("No rosters stored. Import one first with /esotk roster import")
            return
        elseif count == 1 then
            roster = all[onlyName]
        else
            Util.Error("Multiple rosters stored. Specify which: /esotk validate run <name>")
            Util.Print("Stored rosters:")
            for name, _ in pairs(all) do
                Util.Print("  - " .. name)
            end
            return
        end
    end

    -- Scan the current group
    local members, groupSize = GroupScanner.ScanGroup()
    if groupSize == 0 then
        Util.Error("Not in a group. Join a group before validating.")
        return
    end

    -- Run validation
    local result = RosterValidator.Validate(roster, members, groupSize)
    RosterValidator.lastResult = result

    -- Display results
    if ValidationUI and ValidationUI.DisplayResult then
        ValidationUI.DisplayResult(result)
    else
        -- Fallback: simple chat output
        RosterValidator.PrintResult(result)
    end
end

--- Simple chat-based output of validation results (fallback if ValidationUI
--- is not yet implemented).
--- @param result table  Validation result from Validate()
function RosterValidator.PrintResult(result)
    EnsureModules()

    local status = result.overallPass and "PASS" or "FAIL"
    Util.Print("=== Roster Validation: " .. result.rosterName .. " [" .. status .. "] ===")
    Util.Print("Slots: " .. result.passedSlots .. "/" .. result.totalSlots .. " passed, "
        .. result.matchedSlots .. "/" .. result.totalSlots .. " matched")

    -- Per-slot details (only show failures to keep chat readable)
    for _, sr in ipairs(result.slotResults) do
        if not sr.pass then
            local issues = {}
            for _, c in ipairs(sr.checks) do
                if not c.pass then
                    table.insert(issues, c.detail)
                end
            end
            Util.Warn("  " .. sr.slot .. " (" .. sr.playerName .. "): " .. table.concat(issues, "; "))
        end
    end

    -- Unassigned players
    if #result.unassigned > 0 then
        Util.Warn("Unassigned players in group:")
        for _, p in ipairs(result.unassigned) do
            Util.Warn("  - " .. p.rawName .. " (" .. p.displayName .. ") " .. p.className .. " " .. p.role)
        end
    end

    -- Empty slots
    if #result.emptySlots > 0 then
        Util.Warn("Empty roster slots (player not in group):")
        for _, s in ipairs(result.emptySlots) do
            Util.Warn("  - " .. s.slot .. ": " .. s.playerName)
        end
    end
end

--- Show the last validation result.
function RosterValidator.Status()
    EnsureModules()

    if not RosterValidator.lastResult then
        Util.Print("No validation has been run yet. Use /esotk validate run [name]")
        return
    end

    RosterValidator.PrintResult(RosterValidator.lastResult)
end

--- Handle /esotk validate <subcommand> commands.
--- @param args string  Remaining arguments after "validate"
function RosterValidator.HandleCommand(args)
    EnsureModules()
    local subcommand = args and args:match("^(%S+)") or ""
    subcommand = subcommand:lower()

    if subcommand == "run" then
        RosterValidator.Run(args:match("^%S+%s*(.*)$") or "")
    elseif subcommand == "status" then
        RosterValidator.Status()
    else
        Util.Print("Validate commands:")
        Util.Print("  run [roster_name]  — Validate group against a roster")
        Util.Print("  status             — Show last validation result")
    end
end
