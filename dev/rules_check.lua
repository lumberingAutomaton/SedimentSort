-- Checks the rule set's lifecycle: a new install starts empty with the Full order, older saves migrate
-- once, and backup / reset to default / restore behave. Run: lua dev/rules_check.lua (from the addon folder).
Enum = { ItemQuality = { Poor = 0 } }
date = os.date
local function Load()
	local ns = {}
	assert(loadfile("Weights.lua"))("Sediment", ns)
	return ns.Weights
end

-- New install.
SedimentDB = {}
local W = Load()
W.Init()
assert(next(SedimentDB.weights.items) == nil and next(SedimentDB.weights.classes) == nil, "new install isn't empty")
assert(next(SedimentDB.weights.flags) == nil, "new install has flags")
assert(SedimentDB.autoOrder == "full", "new install isn't on the Full order")
assert(not W.HasRules(), "empty rules report as having rules")
W.Init() -- a second load changes nothing
assert(next(SedimentDB.weights.flags) == nil, "a reload added a flag")

-- An old save (version 1, no Equipment set flag) migrates once; its order setting is left alone.
SedimentDB = { weights = { sinkLine = 40, default = 39, items = { [6948] = 0 }, flags = {}, subclasses = {}, classes = { [7] = 80 } } }
W = Load()
W.Init()
assert(SedimentDB.weights.flags.equipmentSet == 35, "old save didn't get the Equipment set flag")
assert(SedimentDB.autoOrder == nil, "an existing user's order setting was changed")
SedimentDB.weights.flags.equipmentSet = nil
W.Init()
assert(SedimentDB.weights.flags.equipmentSet == nil, "a cleared flag came back")

-- A version-2 save is left exactly as it is.
SedimentDB = { weightsVersion = 2, weights = { sinkLine = 40, default = 39, items = {}, flags = {}, subclasses = {}, classes = { [7] = 80 } } }
W = Load()
W.Init()
assert(SedimentDB.weights.classes[7] == 80 and next(SedimentDB.weights.flags) == nil, "a version-2 save changed")

-- Backup, reset to default, restore (and restore again to swap back).
SedimentDB.keepOut = { items = {}, subclasses = { ["7:5"] = true } }
W.ResetToDefault()
assert(not W.HasRules(), "reset left rules behind")
assert(SedimentDB.keepOut == nil, "reset left keep-out rules")
local b = W.BackupInfo()
assert(b and b.weights.classes[7] == 80 and b.keepOut.subclasses["7:5"], "reset didn't back up rules and keep-out")
assert(W.RestoreBackup(), "restore failed")
assert(SedimentDB.weights.classes[7] == 80 and SedimentDB.keepOut.subclasses["7:5"], "restore didn't bring rules back")
assert(W.HasRules(), "restored rules not seen")
assert(W.BackupInfo() == nil, "restoring over an empty rule set kept an empty backup")

-- Restoring over real rules keeps them as the backup, so the restore can be undone.
W.Backup("test")
SedimentDB.weights.classes[7] = 55
assert(W.RestoreBackup() and SedimentDB.weights.classes[7] == 80, "restore didn't bring the backup back")
assert(W.BackupInfo() and W.BackupInfo().weights.classes[7] == 55, "restoring over real rules didn't keep them")

-- Nothing to back up: no backup is taken over an existing one.
SedimentDB = { weightsVersion = 3, weights = { sinkLine = 50, default = 20, items = {}, flags = {}, subclasses = {}, classes = {} } }
W = Load()
W.Init()
W.Backup("test")
assert(W.BackupInfo() == nil, "backed up an empty rule set")
print("rules check: new install, migrations, backup, reset and restore all OK")
