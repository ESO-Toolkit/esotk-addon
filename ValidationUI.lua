-- ESOtk ValidationUI - Chat output formatting for validation results
-- Color-coded display of roster validation using ESO chat color codes.
-- ESO-657

ESOtk = ESOtk or {}
ESOtk.ValidationUI = {}

local ValidationUI = ESOtk.ValidationUI
local Util  -- resolved lazily

local function EnsureUtil()
    if not Util then Util = ESOtk.Util end
end

-- ---------------------------------------------------------------------------
-- ESO chat color codes
-- ---------------------------------------------------------------------------

local COLOR = {
    GREEN  = "|c00FF00",   -- pass / matched
    RED    = "|cFF0000",   -- fail / missing
    YELLOW = "|cFFFF00",   -- warning (offline, wrong zone)
    WHITE  = "|cFFFFFF",   -- neutral info
    CYAN   = "|c00FFFF",   -- header / labels
    ORANGE = "|cFF8800",   -- partial / attention
    RESET  = "|r",         -- reset to default
}

--- Wrap text in a color code pair.
--- @param text string
--- @param color string  One of the COLOR constants
--- @return string
local function Colorize(text, color)
    return color .. tostring(text) .. COLOR.RESET
end

--- Return a colored PASS or FAIL label.
--- @param pass boolean
--- @return string
local function StatusLabel(pass)
    if pass then
        return Colorize("PASS", COLOR.GREEN)
    else
        return Colorize("FAIL", COLOR.RED)
    end
end

--- Return a colored check icon.
--- @param pass boolean
--- @return string
local function CheckIcon(pass)
    if pass then
        return Colorize("+", COLOR.GREEN)
    else
        return Colorize("x", COLOR.RED)
    end
end

-- ---------------------------------------------------------------------------
-- Display helpers
-- ---------------------------------------------------------------------------

--- Format a single slot result for chat.
--- @param sr table  Slot result from RosterValidator
--- @return string[]  Array of chat lines
local function FormatSlotLines(sr)
    local lines = {}
    local icon = CheckIcon(sr.pass)
    local slotLabel = Colorize(sr.slot, COLOR.CYAN)

    if sr.pass then
        -- Compact one-liner for passing slots
        table.insert(lines, "  " .. icon .. " " .. slotLabel .. " " .. sr.playerName)
    else
        -- Multi-line for failing slots
        table.insert(lines, "  " .. icon .. " " .. slotLabel .. " " .. Colorize(sr.playerName, COLOR.WHITE))
        for _, c in ipairs(sr.checks) do
            if not c.pass then
                local severity = COLOR.RED
                -- Downgrade to yellow for "soft" failures
                if c.check == "online" then severity = COLOR.YELLOW end
                table.insert(lines, "      " .. Colorize(c.detail, severity))
            end
        end
    end

    return lines
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Display a full validation result in color-coded chat output.
--- @param result table  Validation result from RosterValidator.Validate()
function ValidationUI.DisplayResult(result)
    EnsureUtil()

    -- Header
    local header = Colorize("=== Roster Validation: ", COLOR.CYAN)
        .. Colorize(result.rosterName, COLOR.WHITE)
        .. " " .. StatusLabel(result.overallPass)
        .. Colorize(" ===", COLOR.CYAN)
    d(header)

    -- Summary bar
    local summaryColor = result.overallPass and COLOR.GREEN or COLOR.RED
    local summary = Colorize(
        result.passedSlots .. "/" .. result.totalSlots .. " slots passed",
        summaryColor
    ) .. "  |  " .. Colorize(
        result.matchedSlots .. "/" .. result.totalSlots .. " players found",
        result.matchedSlots == result.totalSlots and COLOR.GREEN or COLOR.ORANGE
    ) .. "  |  " .. Colorize(
        "Group: " .. result.groupSize,
        COLOR.WHITE
    )
    d(summary)

    -- Divider
    d(Colorize("---", COLOR.CYAN))

    -- Per-slot results (pass first, then fail for readability)
    local passSlots = {}
    local failSlots = {}
    for _, sr in ipairs(result.slotResults) do
        if sr.pass then
            table.insert(passSlots, sr)
        else
            table.insert(failSlots, sr)
        end
    end

    if #passSlots > 0 then
        for _, sr in ipairs(passSlots) do
            for _, line in ipairs(FormatSlotLines(sr)) do
                d(line)
            end
        end
    end

    if #failSlots > 0 then
        if #passSlots > 0 then
            d(Colorize("---", COLOR.CYAN))
        end
        for _, sr in ipairs(failSlots) do
            for _, line in ipairs(FormatSlotLines(sr)) do
                d(line)
            end
        end
    end

    -- Unassigned players
    if #result.unassigned > 0 then
        d(Colorize("---", COLOR.CYAN))
        d(Colorize("Unassigned players in group:", COLOR.YELLOW))
        for _, p in ipairs(result.unassigned) do
            d("  " .. Colorize("?", COLOR.YELLOW) .. " "
                .. p.rawName .. " (" .. p.displayName .. ") "
                .. Colorize(p.className, COLOR.WHITE) .. " "
                .. Colorize(p.role, COLOR.WHITE))
        end
    end

    -- Empty slots
    if #result.emptySlots > 0 then
        d(Colorize("---", COLOR.CYAN))
        d(Colorize("Missing players (roster slot empty):", COLOR.RED))
        for _, s in ipairs(result.emptySlots) do
            d("  " .. Colorize("x", COLOR.RED) .. " "
                .. Colorize(s.slot, COLOR.CYAN) .. " — "
                .. Colorize(s.playerName .. " not in group", COLOR.RED))
        end
    end

    -- Footer
    d(Colorize("=================================", COLOR.CYAN))
end

--- Display a compact summary of validation results (for repeated checks).
--- @param result table  Validation result from RosterValidator.Validate()
function ValidationUI.DisplaySummary(result)
    EnsureUtil()

    local status = StatusLabel(result.overallPass)
    local summary = Colorize("[ESOtk] ", COLOR.CYAN)
        .. Colorize(result.rosterName, COLOR.WHITE) .. " "
        .. status .. " — "
        .. Colorize(result.passedSlots .. "/" .. result.totalSlots, result.overallPass and COLOR.GREEN or COLOR.RED)
        .. " slots"

    if #result.unassigned > 0 then
        summary = summary .. ", " .. Colorize(#result.unassigned .. " unassigned", COLOR.YELLOW)
    end
    if #result.emptySlots > 0 then
        summary = summary .. ", " .. Colorize(#result.emptySlots .. " missing", COLOR.RED)
    end

    d(summary)
end

--- Display multiple validation results (e.g. comparing against all rosters).
--- @param results table  Array of validation results
function ValidationUI.DisplayMultipleResults(results)
    EnsureUtil()

    if #results == 0 then
        Util.Print("No validation results to display.")
        return
    end

    if #results == 1 then
        ValidationUI.DisplayResult(results[1])
        return
    end

    d(Colorize("=== Validation Summary (" .. #results .. " rosters) ===", COLOR.CYAN))
    for _, result in ipairs(results) do
        ValidationUI.DisplaySummary(result)
    end
    d(Colorize("=================================", COLOR.CYAN))
end
