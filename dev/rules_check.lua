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

-- History: reset to default saves a version first; restoring loads it and saves the rules it replaces.
local function Count() return #W.History() end
SedimentDB.keepOut = { items = {}, subclasses = { ["7:5"] = true } }
local before = Count()
W.ResetToDefault()
assert(not W.HasRules(), "reset left rules behind")
assert(SedimentDB.keepOut == nil, "reset left keep-out rules")
assert(Count() == before + 1, "reset didn't save a version")
local saved = W.History()[1]
assert(saved.reason == "before Reset to default" and saved.weights.classes[7] == 80 and saved.keepOut.subclasses["7:5"],
	"the saved version lacks the rules or keep-out")
assert(W.PreviousVersion() == saved, "previous version isn't the one just saved")
W.LoadVersion(W.PreviousVersion())
assert(SedimentDB.weights.classes[7] == 80 and SedimentDB.keepOut.subclasses["7:5"], "loading didn't bring rules back")
assert(W.IsCurrent(saved), "the loaded version isn't marked in use")
assert(Count() == before + 1, "loading saved the empty rules it replaced")

-- Loading over real rules saves them, so it can be undone (restore twice = back where you were).
SedimentDB.weights.classes[7] = 55
W.LoadVersion(W.PreviousVersion())
assert(SedimentDB.weights.classes[7] == 80, "didn't load the saved version")
assert(W.PreviousVersion().weights.classes[7] == 55, "the replaced rules weren't saved")
W.LoadVersion(W.PreviousVersion())
assert(SedimentDB.weights.classes[7] == 55, "loading back didn't undo")

-- No duplicates in a row; nothing empty unless asked; Save a copy names an unchanged version.
W.Snapshot("once")
local n = Count()
assert(W.Snapshot("again") == nil and Count() == n, "saved the same rules twice in a row")
local e, new = W.SaveCopy("  mine ")
assert(not new and e == W.History()[1] and e.name == "mine", "Save a copy didn't name the unchanged version")
SedimentDB.weights.classes[7] = 56
e, new = W.SaveCopy("")
assert(new and e.name == nil and e.reason == "saved by you", "Save a copy didn't save changed rules")
W.RenameVersion(e, "named")
assert(e.name == "named")
W.DeleteVersion(e)
assert(W.History()[1] ~= e, "delete didn't remove the version")
W.ClearWeights()
assert(SedimentDB.keepOut.subclasses["7:5"], "clearing the weights cleared keep-out rules")
SedimentDB.keepOut = nil
assert(W.Snapshot("empty") == nil, "saved an empty rule set")
assert(W.SaveCopy("blank") and W.History()[1].name == "blank", "Save a copy refused an empty rule set")

-- The newest 20 unnamed versions are kept; named ones aren't dropped.
for i = 1, 30 do
	SedimentDB.weights.classes[9] = i
	W.Snapshot("loop " .. i)
end
local unnamed, named = 0, 0
for _, v in ipairs(W.History()) do
	if v.name then named = named + 1 else unnamed = unnamed + 1 end
end
assert(unnamed == 20, "kept " .. unnamed .. " unnamed versions")
assert(named == 2, "a named version was dropped: " .. named)
assert(W.History()[1].reason == "loop 30", "newest isn't first")

-- Login: a version only if the rules changed; the old single backup slot becomes the oldest version.
n = Count()
W.Init()
W.LoginSnapshot("Testchar")
assert(Count() == n, "login saved unchanged rules")
-- (An upgrade from 0.16.0: no History yet, the old backup slot filled.)
SedimentDB = { weightsVersion = 3, weights = { sinkLine = 50, default = 20, items = {}, flags = {}, subclasses = {},
	classes = { [9] = 99 } } }
SedimentDB.rulesBackup = { time = "old", reason = "before Reset to default", weights = { sinkLine = 40, default = 39,
	items = {}, flags = {}, subclasses = {}, classes = { [7] = 1 } } }
W.Init()
W.LoginSnapshot("Testchar")
local h = W.History()
assert(#h == 2, "upgrade should give two versions (the old backup, the rules at login), got " .. #h)
assert(h[1].reason == "Testchar login" and h[1].weights.classes[9] == 99, "login didn't save changed rules")
assert(h[#h].time == "old" and h[#h].weights.classes[7] == 1, "the old backup didn't become the oldest version")
assert(SedimentDB.rulesBackup == nil, "the old backup slot is still there")
print("rules check: new install, migrations, history, reset and restore all OK")
