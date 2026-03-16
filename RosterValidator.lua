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
--- Expects members to have pre-computed _rawLower / _displayLower fields.
--- @param playerName string  Name from the roster slot
--- @param members table      Array of GroupScanner member data
--- @param matchedTags table  Set of unitTags already matched (skip these)
--- @return table|nil         Matched member, or nil
local function FindMember(playerName, members, matchedTags)
    if not playerName or playerName == "" then return nil end
    local target = playerName:lower()
    for _, m in ipairs(members) do
        if not matchedTags[m.unitTag] and m._rawLower == target then return m end
    end
    for _, m in ipairs(members) do
        if not matchedTags[m.unitTag] and m._displayLower == target then return m end
    end
    return nil
end

--- Find a group member by @account display name (case-insensitive).
--- Expects members to have pre-computed _displayLower field.
--- @param displayName string  @account name
--- @param members table       Array of GroupScanner member data
--- @param matchedTags table   Set of unitTags already matched (skip these)
--- @return table|nil
local function FindMemberByDisplayName(displayName, members, matchedTags)
    if not displayName or displayName == "" then return nil end
    local target = displayName:lower()
    for _, m in ipairs(members) do
        if not matchedTags[m.unitTag] and m._displayLower == target then return m end
    end
    return nil
end

--- Find the first unmatched group member with the given role.
--- @param role string         Expected role ("Tank", "Healer", "DPS")
--- @param members table       Array of GroupScanner member data
--- @param matchedTags table   Set of unitTags already matched (skip these)
--- @return table|nil
local function FindMemberByRole(role, members, matchedTags)
    for _, m in ipairs(members) do
        if not matchedTags[m.unitTag] and m.role == role then return m end
    end
    return nil
end

--- Get explicit slot mappings for a roster from savedVars.
--- @param rosterName string
--- @return table|nil   { slotKey = "@account", ... }
local function GetSlotMappings(rosterName)
    local sv = ESOtk.savedVars
    if not sv or not sv.slotMappings then return nil end
    return sv.slotMappings[rosterName]
end

-- ---------------------------------------------------------------------------
-- Single-slot validation
-- ---------------------------------------------------------------------------

--- Build a brief comma-separated gear requirements string from a roster slot.
--- Returns nil if no gear sets are specified.
--- @param slotData table  Roster slot data
--- @return string|nil
local GEAR_NAMED_KEYS = { "set1", "set2", "monsterSet" }

local function GearSummary(slotData)
    local gs = slotData.gearSets
    if not gs then return nil end
    local sets, seen = {}, {}
    for _, key in ipairs(GEAR_NAMED_KEYS) do
        local s = gs[key]
        if type(s) == "string" and s ~= "" then
            local lower = s:lower()
            if not seen[lower] then seen[lower] = true; sets[#sets + 1] = s end
        end
    end
    for _, v in ipairs(gs) do
        if type(v) == "string" and v ~= "" then
            local lower = v:lower()
            if not seen[lower] then seen[lower] = true; sets[#sets + 1] = v end
        end
    end
    return #sets > 0 and table.concat(sets, ", ") or nil
end

--- Validate a single roster slot against a pre-matched group member.
--- @param slotKey string       Slot identifier (e.g. "tank1", "healer2")
--- @param slotData table       Roster slot data (must have playerName)
--- @param member table|nil     Matched group member, or nil if unmatched
--- @param matchMethod string   How the member was matched ("map", "name", "role", or "none")
--- @return table               Slot validation result
local function ValidateSlot(slotKey, slotData, member, matchMethod)
    local result = {
        slot        = slotKey,
        playerName  = slotData.playerName or "(unnamed)",
        matchedName = nil,  -- actual in-game name if matched
        matchMethod = matchMethod or "none",
        gearSummary = GearSummary(slotData),  -- brief gear requirements for overlay display
        checks      = {},
        pass        = true,
    }

    local expectedRole = InferRole(slotKey)

    -- 1. Player Presence
    if not member then
        result.pass = false
        table.insert(result.checks, {
            check  = "presence",
            pass   = false,
            detail = (slotData.playerName or "?") .. " is not in the group",
        })
        return result
    end

    -- Store matched player's actual name for overlay display
    result.matchedName = member.rawName .. " (" .. member.displayName .. ")"

    table.insert(result.checks, {
        check  = "presence",
        pass   = true,
        detail = member.rawName .. " (" .. member.displayName .. ") found"
            .. (matchMethod ~= "name" and " [" .. matchMethod .. "]" or ""),
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

    -- 3. Class Match (if roster specifies expected class)
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

    -- 5. Gear Check (local player only — ESO API can't inspect others' gear)
    if slotData.gearSets and AreUnitsEqual(member.unitTag, "player") then
        local GearScanner = ESOtk.GearScanner
        if GearScanner then
            local gearData = GearScanner.ScanPlayerGear()
            local gearResult = GearScanner.ValidateGearAgainstRoster(gearData, slotData)
            if not gearResult.pass then
                result.pass = false
                for _, issue in ipairs(gearResult.issues) do
                    table.insert(result.checks, {
                        check  = "gear",
                        pass   = false,
                        detail = issue,
                    })
                end
            else
                table.insert(result.checks, {
                    check  = "gear",
                    pass   = true,
                    detail = "Gear OK",
                })
            end
        end
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
--- Uses three-pass matching:
---   1. Explicit slot mappings (from /esotk map)
---   2. Name matching (roster playerName vs character/account name)
---   3. Role-based fallback (match unassigned members by role)
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

    -- Pre-compute lowercase names once to avoid repeated :lower() per match
    for _, m in ipairs(members) do
        m._rawLower     = m.rawName:lower()
        m._displayLower = m.displayName:lower()
    end

    -- Build slotKey → member mapping via three-pass matching
    local slotMembers = {}   -- slotKey → member
    local slotMethods = {}   -- slotKey → "map" | "name" | "role"
    local slotMappings = GetSlotMappings(roster.rosterName)

    -- Pass 1: Explicit slot mappings (/esotk map <slot> <@account>)
    if slotMappings then
        for _, slot in ipairs(slots) do
            local mapped = slotMappings[slot.key]
            if mapped then
                local m = FindMemberByDisplayName(mapped, members, matchedTags)
                if m then
                    slotMembers[slot.key] = m
                    slotMethods[slot.key] = "map"
                    matchedTags[m.unitTag] = true
                end
            end
        end
    end

    -- Pass 2: Name matching (roster playerName vs character/account name)
    for _, slot in ipairs(slots) do
        if not slotMembers[slot.key] then
            local m = FindMember(slot.data.playerName, members, matchedTags)
            if m then
                slotMembers[slot.key] = m
                slotMethods[slot.key] = "name"
                matchedTags[m.unitTag] = true
            end
        end
    end

    -- Pass 3: Role-based fallback (match unassigned players by role)
    local sv = ESOtk.savedVars
    if not sv or sv.matchByRole ~= false then  -- default: on
        for _, slot in ipairs(slots) do
            if not slotMembers[slot.key] then
                local expectedRole = InferRole(slot.key)
                local m = FindMemberByRole(expectedRole, members, matchedTags)
                if m then
                    slotMembers[slot.key] = m
                    slotMethods[slot.key] = "role"
                    matchedTags[m.unitTag] = true
                end
            end
        end
    end

    -- Validate each slot with its matched (or unmatched) member
    for _, slot in ipairs(slots) do
        local member = slotMembers[slot.key]
        local method = slotMethods[slot.key] or "none"
        local slotResult = ValidateSlot(slot.key, slot.data, member, method)
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

-- ---------------------------------------------------------------------------
-- Explicit slot mapping (/esotk map)
-- ---------------------------------------------------------------------------

--- Resolve which roster to use for mapping.
--- Uses the last validated roster or the sole stored roster.
--- @return string|nil  Roster name, or nil with error printed
local function ResolveRosterForMapping()
    EnsureModules()

    -- Prefer the last validated roster
    if RosterValidator.lastResult then
        return RosterValidator.lastResult.rosterName
    end

    -- Fall back to sole stored roster
    local all = RosterImport.GetAll()
    local count = 0
    local onlyName
    for name, _ in pairs(all) do count = count + 1; onlyName = name end
    if count == 1 then return onlyName end
    if count == 0 then
        Util.Error("No rosters stored. Import one first.")
    else
        Util.Error("Multiple rosters stored; run validation first to select one.")
    end
    return nil
end

local VALID_SLOT_KEYS = {
    tank1 = true, tank2 = true,
    healer1 = true, healer2 = true,
    dps1 = true, dps2 = true, dps3 = true, dps4 = true,
    dps5 = true, dps6 = true, dps7 = true, dps8 = true,
}

--- Handle /esotk map <subcommand> commands.
--- @param args string  Remaining arguments after "map"
function RosterValidator.HandleMapCommand(args)
    EnsureModules()

    local subcommand = args and args:match("^(%S+)") or ""
    subcommand = subcommand:lower()
    local rest = args and args:match("^%S+%s*(.*)$") or ""

    local sv = ESOtk.savedVars
    -- Force write-back for ZO_SavedVars persistence
    sv.slotMappings = sv.slotMappings or {}

    if subcommand == "list" then
        local rosterName = ResolveRosterForMapping()
        if not rosterName then return end
        local mappings = sv.slotMappings[rosterName]
        if not mappings or Util.IsEmpty(mappings) then
            Util.Print("No slot mappings for roster '" .. rosterName .. "'.")
            return
        end
        Util.Print("Slot mappings for '" .. rosterName .. "':")
        for slot, account in pairs(mappings) do
            Util.Print("  " .. slot .. " → " .. account)
        end

    elseif subcommand == "clear" then
        local rosterName = ResolveRosterForMapping()
        if not rosterName then return end
        sv.slotMappings[rosterName] = nil
        Util.Print("Cleared all slot mappings for '" .. rosterName .. "'.")

    elseif VALID_SLOT_KEYS[subcommand] then
        -- /esotk map <slot> <@account|clear>
        local slotKey = subcommand
        local account = Util.Trim(rest)
        local rosterName = ResolveRosterForMapping()
        if not rosterName then return end

        if account == "" then
            Util.Error("Usage: /esotk map " .. slotKey .. " @AccountName")
            return
        end

        if account:lower() == "clear" then
            -- Clear a single slot mapping
            if sv.slotMappings[rosterName] then
                sv.slotMappings[rosterName][slotKey] = nil
            end
            Util.Print("Cleared mapping for " .. slotKey .. " in '" .. rosterName .. "'.")
            return
        end

        -- Ensure @prefix
        if account:sub(1, 1) ~= "@" then
            account = "@" .. account
        end

        sv.slotMappings[rosterName] = sv.slotMappings[rosterName] or {}
        sv.slotMappings[rosterName][slotKey] = account
        Util.Print("Mapped " .. slotKey .. " → " .. account .. " for '" .. rosterName .. "'.")

    else
        Util.Print("Map commands — explicitly assign players to roster slots:")
        Util.Print("  /esotk map <slot> @AccountName  — Map a slot to a player")
        Util.Print("  /esotk map <slot> clear         — Clear a single mapping")
        Util.Print("  /esotk map list                 — Show current mappings")
        Util.Print("  /esotk map clear                — Clear all mappings")
        Util.Print("Slots: tank1, tank2, healer1, healer2, dps1–dps8")
    end
end
