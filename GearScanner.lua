-- ESOtk GearScanner - Local player gear scanning
-- Reads equipped gear from the ESO API and validates against roster requirements.
-- ESO-656

ESOtk = ESOtk or {}
ESOtk.GearScanner = {}

local GearScanner = ESOtk.GearScanner
local Util  -- resolved lazily

local function EnsureUtil()
    if not Util then Util = ESOtk.Util end
end

-- ---------------------------------------------------------------------------
-- Equipment slot definitions
-- ---------------------------------------------------------------------------

--- All equipment slots to scan (front bar + armor + jewelry + back bar).
local EQUIP_SLOTS = {
    { slot = EQUIP_SLOT_HEAD,            label = "Head" },
    { slot = EQUIP_SLOT_NECK,            label = "Neck" },
    { slot = EQUIP_SLOT_CHEST,           label = "Chest" },
    { slot = EQUIP_SLOT_SHOULDERS,       label = "Shoulders" },
    { slot = EQUIP_SLOT_MAIN_HAND,       label = "Main Hand" },
    { slot = EQUIP_SLOT_OFF_HAND,        label = "Off Hand" },
    { slot = EQUIP_SLOT_WAIST,           label = "Waist" },
    { slot = EQUIP_SLOT_LEGS,            label = "Legs" },
    { slot = EQUIP_SLOT_FEET,            label = "Feet" },
    { slot = EQUIP_SLOT_RING1,           label = "Ring 1" },
    { slot = EQUIP_SLOT_RING2,           label = "Ring 2" },
    { slot = EQUIP_SLOT_HAND,            label = "Hands" },
    { slot = EQUIP_SLOT_BACKUP_MAIN,     label = "Backup Main" },
    { slot = EQUIP_SLOT_BACKUP_OFF,      label = "Backup Off" },
}

-- ---------------------------------------------------------------------------
-- Gear scanning
-- ---------------------------------------------------------------------------

--- Scan a single equipment slot.
--- @param slotIndex number  ESO equipment slot constant
--- @return table|nil  { itemLink, setName, setId, numBonuses, numEquipped, maxEquipped } or nil
local function ScanSlot(slotIndex)
    local itemLink = GetItemLink(BAG_WORN, slotIndex)
    if not itemLink or itemLink == "" then return nil end

    local hasSet, setName, numBonuses, numEquipped, maxEquipped, setId =
        GetItemLinkSetInfo(itemLink)

    return {
        itemLink    = itemLink,
        hasSet      = hasSet,
        setName     = hasSet and setName or nil,
        setId       = hasSet and setId or nil,
        numBonuses  = numBonuses,
        numEquipped = hasSet and numEquipped or 0,
        maxEquipped = hasSet and maxEquipped or 0,
    }
end

--- Scan all equipped gear on the local player.
--- @return table  { sets = { [setName] = { setId, count, maxEquipped } }, items = { [slotLabel] = itemData } }
function GearScanner.ScanPlayerGear()
    local result = {
        sets  = {},   -- setName → { setId, count, maxEquipped }
        items = {},   -- slotLabel → item data
    }

    for _, def in ipairs(EQUIP_SLOTS) do
        local item = ScanSlot(def.slot)
        if item then
            result.items[def.label] = item

            if item.hasSet and item.setName then
                local existing = result.sets[item.setName]
                if existing then
                    existing.count = item.numEquipped  -- API returns the total for the set
                else
                    result.sets[item.setName] = {
                        setId       = item.setId,
                        count       = item.numEquipped,
                        maxEquipped = item.maxEquipped,
                    }
                end
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Roster gear validation
-- ---------------------------------------------------------------------------

--- Extract required set names from a roster slot.
--- Handles both tank/healer format (set1, set2, monsterSet) and DPS format (gearSets table).
--- @param rosterSlot table  Roster slot data
--- @return table  Array of required set name strings
function GearScanner.GetRequiredSets(rosterSlot)
    local required = {}

    -- Tank / Healer format: gearSets = { set1, set2, monsterSet }
    if rosterSlot.gearSets then
        local gs = rosterSlot.gearSets
        if gs.set1 and gs.set1 ~= "" then table.insert(required, gs.set1) end
        if gs.set2 and gs.set2 ~= "" then table.insert(required, gs.set2) end
        if gs.monsterSet and gs.monsterSet ~= "" then table.insert(required, gs.monsterSet) end
    end

    -- DPS may also have a flat gearSets array
    if type(rosterSlot.gearSets) == "table" then
        for i, v in ipairs(rosterSlot.gearSets) do
            if type(v) == "string" and v ~= "" then
                -- Only add if not already present (avoid duplicates from mixed format)
                local found = false
                for _, r in ipairs(required) do
                    if r:lower() == v:lower() then found = true; break end
                end
                if not found then table.insert(required, v) end
            end
        end
    end

    return required
end

--- Validate the local player's gear against a roster slot.
--- @param gearData table      Result from ScanPlayerGear()
--- @param rosterSlot table    Roster slot data containing gear requirements
--- @return table              { pass = bool, issues = { string... }, equipped = { string... } }
function GearScanner.ValidateGearAgainstRoster(gearData, rosterSlot)
    EnsureUtil()

    local result = {
        pass     = true,
        issues   = {},
        equipped = {},   -- set names the player is wearing
    }

    -- Collect what the player has
    for setName, info in pairs(gearData.sets) do
        table.insert(result.equipped, setName .. " (" .. info.count .. "pc)")
    end

    -- Check required sets
    local requiredSets = GearScanner.GetRequiredSets(rosterSlot)
    if #requiredSets == 0 then
        -- No gear requirements specified in roster — nothing to validate
        return result
    end

    for _, reqSet in ipairs(requiredSets) do
        local reqLower = reqSet:lower()
        local found = false
        for setName, _ in pairs(gearData.sets) do
            if setName:lower() == reqLower then
                found = true
                break
            end
        end
        if not found then
            result.pass = false
            table.insert(result.issues, "Missing required set: " .. reqSet)
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Chat output
-- ---------------------------------------------------------------------------

--- Print equipped gear set summary to chat.
function GearScanner.PrintGearInfo()
    EnsureUtil()

    local gear = GearScanner.ScanPlayerGear()

    if Util.IsEmpty(gear.sets) then
        Util.Print("No gear sets detected on equipped items.")
        return
    end

    Util.Print("Equipped gear sets:")
    for setName, info in pairs(gear.sets) do
        Util.Print(string.format("  %s — %d/%d pieces", setName, info.count, info.maxEquipped))
    end
end

--- Print gear validation against the player's roster slot.
--- @param rosterName string|nil  Optional roster name (auto-picks sole roster)
function GearScanner.PrintGearValidation(rosterName)
    EnsureUtil()

    local RosterImport = ESOtk.RosterImport
    local GroupScanner = ESOtk.GroupScanner

    -- Resolve roster
    local roster
    if rosterName and rosterName ~= "" then
        roster = RosterImport.Get(Util.Trim(rosterName))
        if not roster then
            Util.Error("Roster '" .. rosterName .. "' not found.")
            return
        end
    else
        local all = RosterImport.GetAll()
        local count = 0
        local onlyName
        for name, _ in pairs(all) do count = count + 1; onlyName = name end
        if count == 0 then
            -- No rosters — just show gear info
            GearScanner.PrintGearInfo()
            return
        elseif count == 1 then
            roster = all[onlyName]
        else
            -- Multiple rosters — just show gear info
            GearScanner.PrintGearInfo()
            Util.Print("(Tip: /esotk gear <roster_name> to validate against a roster)")
            return
        end
    end

    -- Find the local player's slot in the roster
    local playerName = GetRawUnitName("player")
    local displayName = GetUnitDisplayName("player")
    local mySlot = nil
    local mySlotKey = nil

    -- Check named slots
    for _, key in ipairs({ "tank1", "tank2", "healer1", "healer2" }) do
        local slot = roster[key]
        if slot and slot.playerName then
            local pn = slot.playerName:lower()
            if pn == playerName:lower() or pn == displayName:lower() then
                mySlot = slot
                mySlotKey = key
                break
            end
        end
    end

    -- Check DPS slots
    if not mySlot and roster.dpsSlots then
        for i, slot in ipairs(roster.dpsSlots) do
            if slot and slot.playerName then
                local pn = slot.playerName:lower()
                if pn == playerName:lower() or pn == displayName:lower() then
                    mySlot = slot
                    mySlotKey = "dps" .. i
                    break
                end
            end
        end
    end

    if not mySlot then
        GearScanner.PrintGearInfo()
        Util.Warn("You are not assigned to any slot in roster '" .. roster.rosterName .. "'.")
        return
    end

    -- Scan gear and validate
    local gear = GearScanner.ScanPlayerGear()
    local validation = GearScanner.ValidateGearAgainstRoster(gear, mySlot)

    Util.Print("Gear validation for slot " .. mySlotKey .. " in '" .. roster.rosterName .. "':")
    Util.Print("  Equipped: " .. (#validation.equipped > 0 and table.concat(validation.equipped, ", ") or "none"))

    if validation.pass then
        Util.Print("  Status: PASS — all required sets equipped")
    else
        Util.Warn("  Status: FAIL")
        for _, issue in ipairs(validation.issues) do
            Util.Warn("    - " .. issue)
        end
    end
end
