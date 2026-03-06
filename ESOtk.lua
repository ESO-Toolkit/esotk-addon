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
local SAVED_VARS_VERSION = 2
local DEFAULT_SAVED_VARS = {
    version = SAVED_VARS_VERSION,
    rosters = {},  -- roster storage for RosterImport (ESO-654)
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
    Util.Print("  /esotk gear      — Print local player gear")
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
        addon.GearScanner.PrintGearInfo()
    elseif command == "help" or command == "" then
        addon.PrintHelp()
    else
        addon.Util.Warn("Unknown command: " .. command)
        addon.PrintHelp()
    end
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

    addon.Util.Print("v" .. ADDON_VERSION .. " loaded. Type /esotk help for commands.")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
