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
        -- Validation
        -- ---------------------------------------------------------------
        {
            type = "header",
            name = "Validation",
        },
        {
            type = "checkbox",
            name = "Auto-Validate on Group Change",
            tooltip = "Automatically re-run roster validation when group members join, leave, change role, or go online/offline. "
                .. "Requires at least one roster to be imported. Results are shown in the overlay (if visible) and printed to chat.",
            getFunc = function() return sv.autoValidate end,
            setFunc = function(value)
                sv.autoValidate = value
                ESOtk.ValidationOverlay.SyncAutoValidateEvents()
            end,
            default = false,
            width = "full",
        },
        {
            type = "checkbox",
            name = "Match Unassigned Players by Role",
            tooltip = "When a roster slot can't be matched by player name, automatically match "
                .. "unassigned group members by their current role (Tank/Healer/DPS). "
                .. "Disable to require exact name or explicit /esotk map assignments only.",
            getFunc = function() return sv.matchByRole ~= false end,
            setFunc = function(value) sv.matchByRole = value end,
            default = true,
            width = "full",
        },
        {
            type = "description",
            text = "Use |c00FF00/esotk map|r to explicitly assign players to slots:\n"
                .. "  |cFFFF00/esotk map tank1 @AccountName|r — Map a slot\n"
                .. "  |cFFFF00/esotk map list|r — Show mappings\n"
                .. "  |cFFFF00/esotk map clear|r — Clear all mappings\n"
                .. "Explicit mappings take priority over name and role matching.",
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
            getFunc = function() return sv.lastRosterInput or "" end,
            setFunc = function(value)
                Settings._pendingRoster = value
                sv.lastRosterInput = value
            end,
            default = "",
            width = "full",
        },
        {
            type = "button",
            name = "Import Roster",
            tooltip = "Decode and import the roster data above.",
            func = function()
                local data = Settings._pendingRoster or sv.lastRosterInput
                if not data or data == "" then
                    ESOtk.Util.Error("Paste roster data into the editbox first.")
                    return
                end
                ESOtk.RosterImport.Import(data)
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
