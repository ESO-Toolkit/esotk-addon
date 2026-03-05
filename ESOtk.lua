-- ESOtk - Official ESOTK Addon
-- https://github.com/ESO-Toolkit/esotk-addon
--
-- Main entry point: initialization, slash command routing, module orchestration.
-- Individual modules attach to the ESOtk global namespace and are loaded via
-- the manifest (ESOtk.txt) in dependency order.

local ADDON_NAME = "ESOtk"
local ADDON_VERSION = "1.0.0"

ESOtk = ESOtk or {}
local addon = ESOtk

addon.name = ADDON_NAME
addon.version = ADDON_VERSION

-- ---------------------------------------------------------------------------
-- Saved variables defaults
-- ---------------------------------------------------------------------------
local SAVED_VARS_VERSION = 3
local DEFAULT_SAVED_VARS = {
    version = SAVED_VARS_VERSION,
    rosters = {},       -- roster storage for RosterImport (ESO-654)
    verbose = true,     -- show informational messages in chat
    overlayPos = nil,   -- { x, y } saved position for ValidationOverlay (ESO-660)
}

-- ---------------------------------------------------------------------------
-- Help text
-- ---------------------------------------------------------------------------
function addon.PrintHelp()
    local Util = addon.Util
    Util.Print("v" .. ADDON_VERSION .. " — Available commands:")
    Util.Print("  /esotk group     — Print current group info")
    Util.Print("  /esotk roster    — Roster import/management (import, list, delete, clear)")
    Util.Print("  /esotk validate  — Run roster validation")
    Util.Print("  /esotk gear      — Print local player gear (add roster name to validate)")
    Util.Print("  /esotk ui        — Toggle validation overlay (show/hide/refresh)")
    Util.Print("  /esotk help      — Show this help message")
end

-- ---------------------------------------------------------------------------
-- Slash command router
-- ---------------------------------------------------------------------------
local function OnSlashCommand(args)
    -- Parse first word as the subcommand, rest as arguments
    local command, rest = "", ""
    if args and args ~= "" then
        command, rest = args:match("^(%S+)%s*(.*)$")
        command = command and command:lower() or ""
        rest = rest or ""
    end

    if command == "group" then
        addon.GroupScanner.PrintGroupInfo()
    elseif command == "roster" then
        addon.RosterImport.HandleCommand(rest)
    elseif command == "validate" then
        addon.RosterValidator.HandleCommand(rest)
    elseif command == "gear" then
        if rest and rest ~= "" then
            addon.GearScanner.PrintGearValidation(rest)
        else
            addon.GearScanner.PrintGearInfo()
        end
    elseif command == "ui" then
        addon.ValidationOverlay.HandleCommand(rest)
    elseif command == "help" or command == "" then
        addon.PrintHelp()
    else
        addon.Util.Warn("Unknown command: " .. command)
        addon.PrintHelp()
    end
end

-- ---------------------------------------------------------------------------
-- Settings panel (LibAddonMenu-2.0)
-- ---------------------------------------------------------------------------
local function CreateSettingsPanel()
    local LAM = LibAddonMenu2
    if not LAM then return end

    local panelData = {
        type = "panel",
        name = "ESOtk",
        displayName = "ESOtk",
        author = "ESO-Toolkit",
        version = ADDON_VERSION,
        website = "https://github.com/ESO-Toolkit/esotk-addon",
        slashCommand = "/esotk",
    }
    LAM:RegisterAddonPanel(ADDON_NAME .. "_Options", panelData)

    local optionsData = {
        {
            type = "description",
            text = "Use |c00FF00/esotk help|r in chat for a list of commands.",
        },
        {
            type = "checkbox",
            name = "Verbose Chat Output",
            tooltip = "Show informational messages in chat (warnings and errors are always shown).",
            getFunc = function() return addon.savedVars.verbose end,
            setFunc = function(value) addon.savedVars.verbose = value end,
            default = DEFAULT_SAVED_VARS.verbose,
        },
    }
    LAM:RegisterOptionControls(ADDON_NAME .. "_Options", optionsData)
end

-- ---------------------------------------------------------------------------
-- Initialization
-- ---------------------------------------------------------------------------
local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Load saved variables
    addon.savedVars = ZO_SavedVars:NewAccountWide(
        "ESOtk_SavedVars",
        SAVED_VARS_VERSION,
        nil,
        DEFAULT_SAVED_VARS
    )

    -- Register slash command
    SLASH_COMMANDS["/esotk"] = OnSlashCommand

    -- Register settings panel (requires LibAddonMenu-2.0)
    CreateSettingsPanel()

    -- Hook overlay drag-stop for position persistence
    local overlayCtl = GetControl("ESOtk_ValidationOverlay")
    if overlayCtl then
        overlayCtl:SetHandler("OnMoveStop", function() addon.ValidationOverlay.OnMoveStop() end)
    end

    addon.Util.Print("v" .. ADDON_VERSION .. " loaded. Type /esotk help for commands.")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
