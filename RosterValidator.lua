-- ESOtk RosterValidator - Validation engine
-- See ESO-655 for full implementation

ESOtk = ESOtk or {}
ESOtk.RosterValidator = {}

local RosterValidator = ESOtk.RosterValidator

--- Handle /esotk validate <subcommand> commands.
--- @param args string  Remaining arguments after "validate"
function RosterValidator.HandleCommand(args)
    local subcommand = args and args:match("^(%S+)") or ""

    if subcommand == "run" then
        RosterValidator.Run(args:match("^%S+%s*(.*)$") or "")
    elseif subcommand == "status" then
        RosterValidator.Status()
    else
        ESOtk.Util.Print("Validate commands: run [roster_name] | status")
    end
end

--- Run validation against a roster.
--- @param rosterName string  Optional roster name to validate
function RosterValidator.Run(rosterName)
    ESOtk.Util.Print("Roster validation not yet implemented. (ESO-655)")
end

--- Show validation status.
function RosterValidator.Status()
    ESOtk.Util.Print("Validation status not yet implemented. (ESO-655)")
end
