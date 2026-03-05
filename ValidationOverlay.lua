-- ESOtk ValidationOverlay - On-screen roster validation panel
-- Draggable overlay that shows roster validation status at a glance.
-- Auto-refreshes on group change events.
-- ESO-660

ESOtk = ESOtk or {}
ESOtk.ValidationOverlay = {}

local Overlay = ESOtk.ValidationOverlay
local Util, RosterValidator  -- resolved lazily

local function EnsureModules()
    if not Util then
        Util            = ESOtk.Util
        RosterValidator = ESOtk.RosterValidator
    end
end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CONTROL_NAME    = "ESOtk_ValidationOverlay"
local ROW_HEIGHT      = 24
local HEADER_HEIGHT   = 52  -- title (28) + summary (20) + divider (4)
local BOTTOM_PADDING  = 8
local MAX_ROWS        = 14  -- 2 tanks + 2 healers + 8 DPS + 2 extra

-- Status icon characters
local ICON_PASS    = "+"
local ICON_FAIL    = "x"
local ICON_WARN    = "!"
local ICON_UNKNOWN = "?"

-- Colors  (RRGGBB hex without alpha — ESO label color format)
local CLR = {
    PASS    = { 0, 1, 0, 1 },       -- green
    FAIL    = { 1, 0, 0, 1 },       -- red
    WARN    = { 1, 1, 0, 1 },       -- yellow
    CYAN    = { 0, 1, 1, 1 },       -- headers / labels
    WHITE   = { 1, 1, 1, 1 },       -- neutral
    DIM     = { 0.65, 0.65, 0.65, 1 }, -- secondary text
    ORANGE  = { 1, 0.53, 0, 1 },    -- attention
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------

local rows = {}       -- array of created row controls
local isShowing = false
local eventRegistered = false

-- ---------------------------------------------------------------------------
-- Row management
-- ---------------------------------------------------------------------------

--- Get or create a row control at the given index.
--- @param index number  1-based row index
--- @return userdata     The row control
local function GetRow(index)
    if rows[index] then return rows[index] end

    local parent = GetControl(CONTROL_NAME .. "Rows")
    if not parent then return nil end

    local row = CreateControlFromVirtual(
        CONTROL_NAME .. "Row" .. index,
        parent,
        "ESOtk_OverlayRowTemplate"
    )
    if not row then return nil end

    -- Position: stack vertically
    row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, (index - 1) * ROW_HEIGHT)
    rows[index] = row
    return row
end

--- Set the contents of a single row.
--- @param index number
--- @param icon string
--- @param iconColor table
--- @param slotText string
--- @param playerText string
--- @param detailText string
--- @param detailColor table|nil
local function SetRowData(index, icon, iconColor, slotText, playerText, detailText, detailColor)
    local row = GetRow(index)
    if not row then return end

    local statusCtl = GetControl(row:GetName() .. "Status")
    local slotCtl   = GetControl(row:GetName() .. "Slot")
    local playerCtl = GetControl(row:GetName() .. "Player")
    local detailCtl = GetControl(row:GetName() .. "Detail")

    if statusCtl then
        statusCtl:SetText(icon or "")
        if iconColor then statusCtl:SetColor(unpack(iconColor)) end
    end
    if slotCtl then slotCtl:SetText(slotText or "") end
    if playerCtl then playerCtl:SetText(playerText or "") end
    if detailCtl then
        detailCtl:SetText(detailText or "")
        if detailColor then detailCtl:SetColor(unpack(detailColor)) end
    end

    row:SetHidden(false)
end

--- Hide all rows from `startIndex` onward.
local function HideRowsFrom(startIndex)
    for i = startIndex, MAX_ROWS do
        if rows[i] then rows[i]:SetHidden(true) end
    end
end

-- ---------------------------------------------------------------------------
-- Populate overlay from a validation result
-- ---------------------------------------------------------------------------

--- Determine the icon and color for a slot result.
--- @param sr table  Slot result from RosterValidator
--- @return string, table  icon char, color
local function SlotIcon(sr)
    if sr.pass then
        return ICON_PASS, CLR.PASS
    end
    -- Check if only soft failures (e.g. offline)
    local hasHard = false
    for _, c in ipairs(sr.checks) do
        if not c.pass and c.check ~= "online" then
            hasHard = true
            break
        end
    end
    if hasHard then
        return ICON_FAIL, CLR.FAIL
    else
        return ICON_WARN, CLR.WARN
    end
end

--- Build a short detail string for a failing slot result.
--- @param sr table
--- @return string
local function SlotDetail(sr)
    if sr.pass then return "" end
    local parts = {}
    for _, c in ipairs(sr.checks) do
        if not c.pass then
            if c.check == "presence" then
                table.insert(parts, "missing")
            elseif c.check == "role" then
                table.insert(parts, "role")
            elseif c.check == "class" then
                table.insert(parts, "class")
            elseif c.check == "online" then
                table.insert(parts, "offline")
            end
        end
    end
    return table.concat(parts, ", ")
end

--- Populate the overlay with data from a validation result.
--- @param result table  Validation result from RosterValidator.Validate()
function Overlay.Populate(result)
    if not result then return end

    local control = GetControl(CONTROL_NAME)
    if not control then return end

    -- Update title
    local titleCtl = GetControl(CONTROL_NAME .. "HeaderTitle")
    if titleCtl then
        titleCtl:SetText(result.rosterName or "Roster Validation")
    end

    -- Update summary
    local summaryCtl = GetControl(CONTROL_NAME .. "Summary")
    if summaryCtl then
        local summaryText = result.passedSlots .. "/" .. result.totalSlots .. " passed"
        if #result.unassigned > 0 then
            summaryText = summaryText .. "  |  " .. #result.unassigned .. " extra"
        end
        if #result.emptySlots > 0 then
            summaryText = summaryText .. "  |  " .. #result.emptySlots .. " missing"
        end
        summaryCtl:SetText(summaryText)

        if result.overallPass then
            summaryCtl:SetColor(unpack(CLR.PASS))
        else
            summaryCtl:SetColor(unpack(CLR.FAIL))
        end
    end

    -- Populate rows for each slot result
    local rowIndex = 0
    for _, sr in ipairs(result.slotResults) do
        rowIndex = rowIndex + 1
        local icon, iconColor = SlotIcon(sr)
        local detail = SlotDetail(sr)
        local detailColor = sr.pass and CLR.DIM or CLR.FAIL
        -- Downgrade to yellow for soft-only failures
        if not sr.pass then
            local onlySoft = true
            for _, c in ipairs(sr.checks) do
                if not c.pass and c.check ~= "online" then
                    onlySoft = false
                    break
                end
            end
            if onlySoft then detailColor = CLR.WARN end
        end
        SetRowData(rowIndex, icon, iconColor, sr.slot, sr.playerName, detail, detailColor)
    end

    -- Unassigned players
    for _, p in ipairs(result.unassigned) do
        rowIndex = rowIndex + 1
        SetRowData(rowIndex, ICON_UNKNOWN, CLR.ORANGE, "extra",
            p.rawName or p.displayName, p.className .. " " .. p.role, CLR.ORANGE)
    end

    HideRowsFrom(rowIndex + 1)

    -- Resize window to fit rows
    local totalHeight = HEADER_HEIGHT + (rowIndex * ROW_HEIGHT) + BOTTOM_PADDING
    control:SetHeight(totalHeight)
end

-- ---------------------------------------------------------------------------
-- Show / Hide / Toggle
-- ---------------------------------------------------------------------------

function Overlay.Show()
    local control = GetControl(CONTROL_NAME)
    if not control then return end
    control:SetHidden(false)
    isShowing = true

    -- Restore saved position if available
    local sv = ESOtk.savedVars
    if sv and sv.overlayPos then
        control:ClearAnchors()
        control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.overlayPos.x, sv.overlayPos.y)
    end

    -- If we have a last result, populate immediately
    EnsureModules()
    if RosterValidator and RosterValidator.lastResult then
        Overlay.Populate(RosterValidator.lastResult)
    else
        -- Show empty state
        local summaryCtl = GetControl(CONTROL_NAME .. "Summary")
        if summaryCtl then
            summaryCtl:SetText("Run /esotk validate run to populate")
            summaryCtl:SetColor(unpack(CLR.DIM))
        end
        HideRowsFrom(1)
    end

    Overlay.RegisterEvents()
end

function Overlay.Hide()
    local control = GetControl(CONTROL_NAME)
    if not control then return end

    -- Save position before hiding
    Overlay.SavePosition()

    control:SetHidden(true)
    isShowing = false
end

function Overlay.Toggle()
    if isShowing then
        Overlay.Hide()
    else
        Overlay.Show()
    end
end

function Overlay.IsShowing()
    return isShowing
end

-- ---------------------------------------------------------------------------
-- Position persistence
-- ---------------------------------------------------------------------------

function Overlay.SavePosition()
    local control = GetControl(CONTROL_NAME)
    if not control then return end
    local sv = ESOtk.savedVars
    if not sv then return end

    local _, _, _, _, offsetX, offsetY = control:GetAnchor(0)
    sv.overlayPos = { x = offsetX, y = offsetY }
end

--- Called when user stops dragging the overlay.
function Overlay.OnMoveStop()
    Overlay.SavePosition()
end

-- ---------------------------------------------------------------------------
-- Auto-refresh on group events
-- ---------------------------------------------------------------------------

local function OnGroupChanged()
    if not isShowing then return end
    EnsureModules()

    -- Re-run validation silently and refresh overlay
    if RosterValidator and RosterValidator.lastResult then
        local lastRosterName = RosterValidator.lastResult.rosterName
        if lastRosterName then
            local RosterImport = ESOtk.RosterImport
            local GroupScanner = ESOtk.GroupScanner
            if RosterImport and GroupScanner then
                local roster = RosterImport.Get(lastRosterName)
                if roster then
                    local members, groupSize = GroupScanner.ScanGroup()
                    if groupSize > 0 then
                        local result = RosterValidator.Validate(roster, members, groupSize)
                        RosterValidator.lastResult = result
                        Overlay.Populate(result)
                    end
                end
            end
        end
    end
end

function Overlay.RegisterEvents()
    if eventRegistered then return end
    eventRegistered = true

    EVENT_MANAGER:RegisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_JOINED, OnGroupChanged)
    EVENT_MANAGER:RegisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_LEFT, OnGroupChanged)
    EVENT_MANAGER:RegisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_ROLE_CHANGED, OnGroupChanged)
    EVENT_MANAGER:RegisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_CONNECTED_STATUS, OnGroupChanged)
end

function Overlay.UnregisterEvents()
    if not eventRegistered then return end
    eventRegistered = false

    EVENT_MANAGER:UnregisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_JOINED)
    EVENT_MANAGER:UnregisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_LEFT)
    EVENT_MANAGER:UnregisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_ROLE_CHANGED)
    EVENT_MANAGER:UnregisterForEvent("ESOtk_Overlay", EVENT_GROUP_MEMBER_CONNECTED_STATUS)
end

-- ---------------------------------------------------------------------------
-- Slash command handler
-- ---------------------------------------------------------------------------

--- Handle /esotk ui <subcommand>.
--- @param args string  Remaining arguments after "ui"
function Overlay.HandleCommand(args)
    EnsureModules()
    local subcommand = args and args:match("^(%S+)") or ""
    subcommand = subcommand:lower()

    if subcommand == "show" then
        Overlay.Show()
    elseif subcommand == "hide" then
        Overlay.Hide()
    elseif subcommand == "toggle" or subcommand == "" then
        Overlay.Toggle()
    elseif subcommand == "refresh" then
        if isShowing and RosterValidator and RosterValidator.lastResult then
            OnGroupChanged()
            Util.Print("Overlay refreshed.")
        else
            Util.Warn("Overlay not visible or no validation run yet.")
        end
    else
        Util.Print("UI commands:")
        Util.Print("  show     — Show the validation overlay")
        Util.Print("  hide     — Hide the validation overlay")
        Util.Print("  toggle   — Toggle overlay visibility (default)")
        Util.Print("  refresh  — Force refresh the overlay data")
    end
end
