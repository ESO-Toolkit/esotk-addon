-- ESOtk Settings - Addon settings panel via LibAddonMenu-2.0
-- Provides a standard ESO settings panel under Settings → Addons → ESOtk.
-- Gracefully degrades if LibAddonMenu-2.0 is not installed.
-- ESO-660

ESOtk = ESOtk or {}
ESOtk.Settings = {}

local Settings = ESOtk.Settings

-- ---------------------------------------------------------------------------
-- Panel registration (called from OnAddonLoaded)
-- ---------------------------------------------------------------------------

--- Attempt to register the settings panel with LibAddonMenu-2.0.
--- Safe to call even if the library is not installed.
function Settings.Init()
    local LAM2 = LibAddonMenu2
    if not LAM2 then return end  -- LAM2 not installed; skip gracefully

    local sv = ESOtk.savedVars
    if not sv then return end

    -- Panel metadata
    local panelData = {
        type = "panel",
        name = "ESOtk",
        displayName = "|c00FFFFESOtk|r",
        author = "ESO-Toolkit",
        version = ESOtk.version or "1.0.0",
        website = "https://github.com/ESO-Toolkit/esotk-addon",
        slashCommand = "/esotk settings",
        registerForRefresh = true,
    }

    -- Options controls
    local optionsTable = {
        -- ---------------------------------------------------------------
        -- General
        -- ---------------------------------------------------------------
        {
            type = "header",
            name = "General",
        },
        {
            type = "description",
            text = "Use |c00FF00/esotk help|r in chat for a list of commands.",
        },
        {
            type = "checkbox",
            name = "Verbose Chat Output",
            tooltip = "Show informational messages in chat (warnings and errors are always shown).",
            getFunc = function() return sv.verbose end,
            setFunc = function(value) sv.verbose = value end,
            default = true,
            width = "full",
        },

        -- ---------------------------------------------------------------
        -- Roster Import
        -- ---------------------------------------------------------------
        {
            type = "header",
            name = "Roster Import",
        },
        {
            type = "description",
            text = "Paste a Base64-encoded roster string from the web UI, then click Import.",
        },
        {
            type = "editbox",
            name = "Roster Data",
            tooltip = "Paste the Base64-encoded roster string here.",
            isMultiline = true,
            isExtraWide = true,
            getFunc = function() return Settings._pendingRoster or "" end,
            setFunc = function(value) Settings._pendingRoster = value end,
            default = "",
            width = "full",
        },
        {
            type = "button",
            name = "Import Roster",
            tooltip = "Decode and import the roster data above.",
            func = function()
                local data = Settings._pendingRoster
                if not data or data == "" then
                    ESOtk.Util.Error("Paste roster data into the editbox first.")
                    return
                end
                ESOtk.RosterImport.Import(data)
                Settings._pendingRoster = ""
            end,
            width = "full",
        },

        -- ---------------------------------------------------------------
        -- Validation Overlay
        -- ---------------------------------------------------------------
        {
            type = "header",
            name = "Validation Overlay",
        },
        {
            type = "description",
            text = "On-screen panel showing roster validation status at a glance. "
                .. "Auto-refreshes when group members join, leave, or change role.",
        },

        -- ---------------------------------------------------------------
        -- Show / Hide
        -- ---------------------------------------------------------------
        {
            type = "checkbox",
            name = "Show Overlay",
            tooltip = "Show or hide the on-screen roster validation panel.",
            getFunc = function() return sv.overlayVisible end,
            setFunc = function(value)
                sv.overlayVisible = value
                if value then
                    ESOtk.ValidationOverlay.Show()
                else
                    ESOtk.ValidationOverlay.Hide()
                end
            end,
            default = false,
            width = "full",
        },

        -- ---------------------------------------------------------------
        -- Lock position
        -- ---------------------------------------------------------------
        {
            type = "checkbox",
            name = "Lock Overlay Position",
            tooltip = "When enabled, the overlay cannot be dragged. "
                .. "Uncheck to reposition, then re-check to lock in place.",
            getFunc = function() return sv.overlayLocked end,
            setFunc = function(value)
                sv.overlayLocked = value
                ESOtk.ValidationOverlay.SetLocked(value)
            end,
            default = false,
            width = "full",
        },

        -- ---------------------------------------------------------------
        -- Reset position
        -- ---------------------------------------------------------------
        {
            type = "button",
            name = "Reset Overlay Position",
            tooltip = "Move the overlay back to its default position (top-right corner).",
            func = function()
                ESOtk.ValidationOverlay.ResetPosition()
            end,
            width = "full",
        },
    }

    LAM2:RegisterAddonPanel("ESOtk_Settings", panelData)
    LAM2:RegisterOptionControls("ESOtk_Settings", optionsTable)
end
