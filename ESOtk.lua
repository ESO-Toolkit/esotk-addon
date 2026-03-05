-- ESOtk - Official ESOTK Addon
-- https://github.com/ESO-Toolkit/esotk-addon

local ADDON_NAME = "ESOtk"
local ADDON_VERSION = "1.0.0"

ESOtk = ESOtk or {}
local addon = ESOtk

-- Saved variables defaults
local SAVED_VARS_VERSION = 1
local DEFAULT_SAVED_VARS = {
    version = SAVED_VARS_VERSION,
}

-- Initialization
local function OnAddonLoaded(event, addonName)
    if addonName ~= ADDON_NAME then return end
    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    addon.savedVars = ZO_SavedVars:NewAccountWide(
        "ESOtk_SavedVars",
        SAVED_VARS_VERSION,
        nil,
        DEFAULT_SAVED_VARS
    )

    d("[ESOtk] v" .. ADDON_VERSION .. " loaded.")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)
