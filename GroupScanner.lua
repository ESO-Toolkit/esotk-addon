-- ESOtk GroupScanner - Group member scanning
-- Reads group member data from the ESO addon API.
-- ESO-653

ESOtk = ESOtk or {}
ESOtk.GroupScanner = {}

local GroupScanner = ESOtk.GroupScanner
local Util  -- resolved after addon loads

--- Map ESO class IDs to human-readable names.
local CLASS_NAMES = {
    [1]  = "Dragonknight",
    [2]  = "Sorcerer",
    [3]  = "Nightblade",
    [4]  = "Warden",
    [5]  = "Necromancer",
    [6]  = "Templar",
    [117] = "Arcanist",
}

--- Map ESO role constants to human-readable names.
local ROLE_NAMES = {
    [0] = "Unknown",
    [1] = "DPS",
    [2] = "Tank",
    [4] = "Healer",
}

--- Resolve lazy references to other modules (called at first use).
local function EnsureUtil()
    if not Util then Util = ESOtk.Util end
end

-- ---------------------------------------------------------------------------
-- Core scanning
-- ---------------------------------------------------------------------------

--- Scan a single group member by unit tag and return a data table.
--- @param unitTag string  e.g. "group1"
--- @return table|nil  member data, or nil if the unit tag is invalid
function GroupScanner.ScanMember(unitTag)
    if not DoesUnitExist(unitTag) then return nil end

    local rawName     = zo_strformat("<<1>>", GetRawUnitName(unitTag))
    local displayName = GetUnitDisplayName(unitTag)  -- @account
    local classId     = GetUnitClassId(unitTag)
    local level       = GetUnitLevel(unitTag)
    local cp          = GetUnitChampionPoints(unitTag)
    local role        = GetGroupMemberSelectedRole(unitTag)
    local isOnline    = IsUnitOnline(unitTag)
    local isLeader    = IsUnitGroupLeader(unitTag)
    local zoneName    = GetUnitZone(unitTag)

    return {
        unitTag     = unitTag,
        rawName     = rawName,
        displayName = displayName,
        className   = CLASS_NAMES[classId] or ("Unknown(" .. tostring(classId) .. ")"),
        classId     = classId,
        level       = level,
        cp          = cp,
        role        = ROLE_NAMES[role] or "Unknown",
        roleId      = role,
        isOnline    = isOnline,
        isLeader    = isLeader,
        zoneName    = zoneName,
    }
end

--- Scan all current group members.
--- @return table  Array of member data tables (see ScanMember)
--- @return number  Group size
function GroupScanner.ScanGroup()
    local groupSize = GetGroupSize()
    local members = {}

    for i = 1, groupSize do
        local unitTag = GetGroupUnitTagByIndex(i)
        local member = GroupScanner.ScanMember(unitTag)
        if member then
            table.insert(members, member)
        end
    end

    return members, groupSize
end

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------

--- Find a group member by @account name (case-insensitive).
--- @param accountName string  e.g. "@PlayerName"
--- @param existingMembers table|nil  Optional pre-scanned members array
--- @return table|nil  member data or nil
function GroupScanner.FindByAccount(accountName, existingMembers)
    local members = existingMembers or GroupScanner.ScanGroup()
    local target = accountName:lower()
    for _, m in ipairs(members) do
        if m.displayName:lower() == target then
            return m
        end
    end
    return nil
end

--- Find a group member by character name (case-insensitive).
--- @param characterName string
--- @param existingMembers table|nil  Optional pre-scanned members array
--- @return table|nil  member data or nil
function GroupScanner.FindByCharacter(characterName, existingMembers)
    local members = existingMembers or GroupScanner.ScanGroup()
    local target = characterName:lower()
    for _, m in ipairs(members) do
        if m.rawName:lower() == target then
            return m
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------

--- Format a single member for chat display.
--- @param member table  Member data from ScanMember
--- @return string
function GroupScanner.FormatMember(member)
    local status = member.isOnline and "" or " [OFFLINE]"
    local leader = member.isLeader and " *" or ""
    local levelStr
    if member.cp and member.cp > 0 then
        levelStr = "CP" .. member.cp
    else
        levelStr = "Lv" .. member.level
    end
    return string.format(
        "%s (%s) - %s %s %s%s%s",
        member.rawName,
        member.displayName,
        member.className,
        levelStr,
        member.role,
        leader,
        status
    )
end

--- Print information about the current group to chat.
function GroupScanner.PrintGroupInfo()
    EnsureUtil()
    local members, groupSize = GroupScanner.ScanGroup()

    if groupSize == 0 then
        Util.Print("Not in a group.")
        return
    end

    Util.Print("Group members (" .. #members .. "/" .. groupSize .. "):")
    for i, member in ipairs(members) do
        Util.Print("  " .. i .. ". " .. GroupScanner.FormatMember(member))
    end
end
