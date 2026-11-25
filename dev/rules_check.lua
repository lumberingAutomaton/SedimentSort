-- Checks the rule set's lifecycle: a new install starts empty with the Full order, older saves migrate
-- once, and backup / reset to default / restore behave. Run: lua dev/rules_check.lua (from the addon folder).
Enum = { ItemQuality = { Poor = 0 } }
date = os.date
local function Load()
	local ns = {}
	assert(loadfile("Text.lua"))("Sediment", ns)
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

-- History (user, 2026-11-25): Created at Setup done (always new); Snapshot before Load / Start Fresh and at
-- logout / login, only if no entry holds the rules in use; one pin; Active / Previous.
local function Count() return #W.History() end
W.SetCharacter("Rook")
SedimentDB.keepOut = { items = {}, subclasses = { ["7:5"] = true } }
local before = Count()
W.ClearAll() -- Start Fresh
assert(not W.HasRules() and SedimentDB.keepOut == nil, "Start Fresh left rules behind")
assert(Count() == before + 1, "Start Fresh didn't take a Snapshot first")
local saved = W.History()[1]
assert(saved.kind == "snapshot" and saved.character == "Rook" and saved.weights.classes[7] == 80
	and saved.keepOut.subclasses["7:5"], "the Snapshot lacks kind, character, rules or keep-out")
assert(W.EntryTitle(saved):match("^Rook — Snapshot — %a%a%a %d+, %d+:%d+$"), "title: " .. W.EntryTitle(saved))
W.LoadVersion(saved)
assert(SedimentDB.weights.classes[7] == 80 and SedimentDB.keepOut.subclasses["7:5"], "loading didn't bring rules back")
assert(W.ActiveSave() == saved, "the loaded entry isn't Active")
assert(Count() == before + 1, "loading took a Snapshot of empty rules")

-- Load when the rules in use are already an entry: no Snapshot; Previous follows what was Active.
SedimentDB.weights.classes[7] = 61
local x = W.Snapshot()
SedimentDB.weights.classes[7] = 62
local y = W.Snapshot()
assert(x and y and x ~= y, "Snapshots of different rules weren't made")
assert(W.Snapshot() == nil and Count() == Count(), "a Snapshot of rules already saved")
W.LoadVersion(x)
local count = Count()
W.LoadVersion(y)
assert(Count() == count, "Load took a Snapshot of rules already saved")
assert(W.ActiveSave() == y and W.PreviousSave() == x, "Previous isn't the entry Active before the Load")
SedimentDB.weights.classes[7] = 63 -- an edit: nothing Active
assert(W.ActiveSave() == nil and W.PreviousSave() == y, "after an edit, Previous isn't the last Active entry")
W.LoadVersion(x)
assert(Count() == count + 1 and W.History()[1].weights.classes[7] == 63, "Load didn't take a Snapshot of unsaved rules")

-- Created: always a new entry, even with rules identical to another.
local n = Count()
local c1 = W.Created()
local c2 = W.Created()
assert(Count() == n + 2 and c1.kind == "created" and c2 ~= c1, "Created didn't always add an entry")
assert(W.EntryTitle(c1):match("^Rook — Created — "), "Created title: " .. W.EntryTitle(c1))
assert(W.Snapshot() == nil, "a Snapshot right after Created (same rules)")

-- One pin: pinning another moves it; pinned is listed first.
W.Pin(x)
W.Pin(y)
local pins = 0
for _, e in ipairs(W.History()) do if e.pinned then pins = pins + 1 end end
assert(pins == 1 and y.pinned and not x.pinned, "more than one pin, or the pin didn't move")
assert(W.HistoryForDisplay()[1] == y, "the pinned entry isn't first")
W.Unpin(y)
assert(not y.pinned, "Unpin didn't")
W.Pin(y)

-- x marks; Undo unmarks; purge removes.
W.DeleteVersion(x)
assert(x.deleted, "x removed at once")
W.UndeleteVersion(x)
assert(not x.deleted, "Undo didn't")
W.DeleteVersion(x)
W.PurgeDeleted()
for _, e in ipairs(W.History()) do assert(e ~= x, "purge didn't remove") end
W.ClearAll()
assert(W.Snapshot() == nil, "a Snapshot of no rules")

-- The newest 20 unpinned entries are kept; the pinned one isn't dropped.
for i = 1, 30 do
	SedimentDB.weights.classes[9] = i
	W.Snapshot()
end
local unpinned = 0
for _, e in ipairs(W.History()) do if not e.pinned then unpinned = unpinned + 1 end end
assert(unpinned == 20 and y.pinned and W.HistoryForDisplay()[1] == y, "limit or pin wrong: " .. unpinned)

-- Upgrading: older named / pinned entries keep only the most recently pinned; ids are given; marked deletes go.
W.History()[2].pinned, W.History()[2].name, W.History()[2].pinnedTime = true, "old", "2099-01-01 00:00"
W.History()[2].character, W.History()[2].kind = nil, nil -- as an entry from before kinds existed
W.History()[3].deleted = true
local gone = W.History()[3]
W.Init()
pins = 0
for _, e in ipairs(W.History()) do
	if e.pinned then pins = pins + 1 end
	assert(e ~= gone, "a marked delete survived login")
	assert(e.id, "an entry without an id")
end
assert(pins == 1 and W.History()[2].pinned, "upgrade didn't keep exactly the most recently pinned entry")
assert(W.EntryTitle(W.History()[2]):match("^old — Snapshot — "), "legacy title: " .. W.EntryTitle(W.History()[2]))

-- Upgrading from 0.16.0's single backup slot: it becomes the oldest entry.
SedimentDB = { weightsVersion = 3, weights = { sinkLine = 50, default = 20, items = {}, flags = {}, subclasses = {},
	classes = { [9] = 99 } } }
SedimentDB.rulesBackup = { time = "old", reason = "before Reset to default", weights = { sinkLine = 40, default = 39,
	items = {}, flags = {}, subclasses = {}, classes = { [7] = 1 } } }
W.Init()
W.Snapshot() -- login safety net
local h = W.History()
assert(#h == 2, "upgrade should give two entries (the old backup, the rules at login), got " .. #h)
assert(h[1].kind == "snapshot" and h[1].weights.classes[9] == 99, "login didn't snapshot changed rules")
assert(h[#h].time == "old" and h[#h].weights.classes[7] == 1, "the old backup didn't become the oldest entry")
assert(SedimentDB.rulesBackup == nil, "the old backup slot is still there")
print("rules check: new install, migrations, history, reset and restore all OK")
