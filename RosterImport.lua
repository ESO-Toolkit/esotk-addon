-- ESOtk RosterImport - Roster data import and storage
-- See ESO-654 for full implementation

ESOtk = ESOtk or {}
ESOtk.RosterImport = {}

local RosterImport = ESOtk.RosterImport

--- Handle /esotk roster <subcommand> commands.
--- @param args string  Remaining arguments after "roster"
function RosterImport.HandleCommand(args)
    local subcommand = args and args:match("^(%S+)") or ""

    if subcommand == "import" then
        RosterImport.Import(args:match("^%S+%s*(.*)$") or "")
    elseif subcommand == "list" then
        RosterImport.List()
    elseif subcommand == "clear" then
        RosterImport.Clear()
    else
        ESOtk.Util.Print("Roster commands: import <data> | list | clear")
    end
end

--- Import roster data from an encoded string.
--- @param data string  Encoded roster data
function RosterImport.Import(data)
    ESOtk.Util.Print("Roster import not yet implemented. (ESO-654)")
end

--- List stored rosters.
function RosterImport.List()
    ESOtk.Util.Print("Roster list not yet implemented. (ESO-654)")
end

--- Clear all stored rosters.
function RosterImport.Clear()
    ESOtk.Util.Print("Roster clear not yet implemented. (ESO-654)")
end
