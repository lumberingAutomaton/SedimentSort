-- Checks the ranking that Setup's "Your order" list and the Weights page's Empty Space buttons use
-- (Weights.RankingList / WriteRankingList / PinDefault / MoveEmptySpace / MoveRow / DefaultOrder): the Empty Space's
-- position is the layout, unset items stay attached to it, old packed saves convert without changing order,
-- ties stay tied, and items sort the way the list shows.
-- Run: lua dev/ranking_check.lua (from the addon folder).
Enum = { ItemQuality = { Poor = 0 } }
date = os.date
local ns = {}
assert(loadfile("Text.lua"))("Sediment", ns)
assert(loadfile("Weights.lua"))("Sediment", ns)
local W = ns.Weights
local HS = 6948

local function Fresh(weights)
	SedimentDB = { weights = weights, weightsVersion = weights and 3 or nil }
	W.Init()
end

-- The order as a string: rule ids per rung, "|" for the Empty Space.
local function Order()
	local parts = {}
	for _, e in ipairs(W.PinDefault(W.RankingList())) do
		if e.divider then
			parts[#parts + 1] = "|"
		else
			local ids = {}
			for _, r in ipairs(e.rules) do
				ids[#ids + 1] = r.kind == "default" and "default" or (r.kind .. ":" .. tostring(r.key))
			end
			parts[#parts + 1] = table.concat(ids, "+")
		end
	end
	return table.concat(parts, " ")
end

local function Expect(want, what)
	local got = Order()
	assert(got == want, ("%s:\n  want %s\n  got  %s"):format(what, want, got))
end

-- After a write: weights above the Empty Space are under 50, below it 50 or more, the line is 50.
local function CheckSides()
	local w = SedimentDB.weights
	assert(w.sinkLine == 50, "sink line isn't 50: " .. tostring(w.sinkLine))
	local past = false
	for _, e in ipairs(W.RankingList()) do
		if e.divider then
			past = true
		else
			assert(e.weight > 0 and e.weight < 100, "weight out of 0..100: " .. tostring(e.weight))
			assert((e.weight >= 50) == past, "a rung on the wrong side of the Empty Space")
		end
	end
end

-- One row per class, the Empty Space at the bottom (a normal bag sort).
local function ClassRows(classIDs)
	local list = {}
	for _, c in ipairs(classIDs) do
		list[#list + 1] = { rules = { { kind = "class", key = c } } }
	end
	list[#list + 1] = { divider = true }
	W.WriteRankingList(list)
end
Fresh(nil)
ClassRows({ 0, 2, 4, 7 })
Expect("class:0 class:2 class:4 class:7 default |", "fresh order")
CheckSides()

-- Moving the Empty Space: one row at a time; unset items stay attached on the side with items.
assert(W.MoveEmptySpace(-1))
Expect("class:0 class:2 class:4 default | class:7", "Empty Space up one")
CheckSides()
while W.MoveEmptySpace(-1) do end
Expect("| default class:0 class:2 class:4 class:7", "Empty Space at the top")
assert(not W.CanMoveEmptySpace(-1) and W.CanMoveEmptySpace(1), "can-move at the top")
CheckSides()
while W.MoveEmptySpace(1) do end
Expect("class:0 class:2 class:4 class:7 default |", "Empty Space back at the bottom")
assert(not W.CanMoveEmptySpace(1) and W.CanMoveEmptySpace(-1), "can-move at the bottom")

-- Old saves from the packed layouts (sink line 100 / 0) keep their order; the first write makes it 50.
Fresh({ sinkLine = 100, default = 20, items = { [HS] = 10 }, flags = {}, subclasses = {}, classes = { [7] = 60 } })
Expect("item:6948 class:7 default |", "old packed-from-top save (unset items shown by the Empty Space)")
W.WriteRankingList(W.RankingList())
Expect("item:6948 class:7 default |", "converted")
CheckSides()
Fresh({ sinkLine = 0, default = 20, items = { [HS] = 10 }, flags = {}, subclasses = {}, classes = { [7] = 60 } })
Expect("| default item:6948 class:7", "old packed-from-bottom save")
W.WriteRankingList(W.RankingList())
Expect("| default item:6948 class:7", "converted")
CheckSides()

-- Hand-set rules with ties and an odd sink line: ties stay tied, the line becomes 50, the order holds.
Fresh({ sinkLine = 40, default = 39, items = { [HS] = 0, [5] = 45 }, flags = { gray = 90 },
	subclasses = { ["0:1"] = 30, ["0:5"] = 30 }, classes = { [7] = 80, [2] = 45 } })
Expect("item:6948 subclass:0:1+subclass:0:5 default | item:5+class:2 class:7 flag:gray", "existing rules")
W.WriteRankingList(W.RankingList())
Expect("item:6948 subclass:0:1+subclass:0:5 default | item:5+class:2 class:7 flag:gray", "tidied")
assert(SedimentDB.weights.subclasses["0:1"] == SedimentDB.weights.subclasses["0:5"], "a tie was broken")
CheckSides()

-- Many rungs: weights stay distinct and inside their half.
Fresh(nil)
local many = {}
for id = 1, 120 do
	many[#many + 1] = { rules = { { kind = "item", key = id } } }
	if id == 60 then many[#many + 1] = { divider = true } end
end
W.WriteRankingList(many)
local seen = {}
for _, e in ipairs(W.RankingList()) do
	if e.rules then
		assert(#e.rules == 1, "two rules fell onto one rung")
		assert(not seen[e.weight], "duplicate weight " .. e.weight)
		seen[e.weight] = true
	end
end
CheckSides()

-- Items sort in the order the list shows.
Fresh(nil)
ClassRows({ 0, 7, 15 })
assert(W.MoveEmptySpace(-1)) -- class 15 (Miscellaneous) below the Empty Space
local function Item(itemID, classID)
	return { itemID = itemID, classID = classID, subclassID = 0, subKey = classID .. ":0", quality = 1,
		isBound = true, equipLoc = "" }
end
local potion, cloth, misc = Item(1, 0), Item(2, 7), Item(3, 15)
local function Wt(item) return (W.Resolve(item)) end
assert(Wt(potion) < Wt(cloth) and Wt(cloth) < 50 and Wt(misc) >= 50, "items don't follow the order")
assert(W.HasOwnRule(potion) and not W.HasOwnRule(Item(4, 9)), "HasOwnRule wrong")

-- Start Fresh's default order: the always-listed groups, other classes just above the Empty Space, the Quest
-- Items row holding both quest rules.
Fresh(nil)
W.DefaultOrder({ 0, 1, 2, 9, 12 })
Expect("item:6948 subclass:0:1 subclass:0:7 class:0 flag:quest+class:12 flag:unboundGear class:1 class:9 default | "
	.. "class:2 class:4 class:7 class:15 flag:gray", "default order")
CheckSides()
assert(SedimentDB.weights.flags.quest == SedimentDB.weights.classes[12], "the quest rules aren't on one row")

-- MoveRow (drag and drop): positions among the shown rows (unset items not counted); the Empty Space too.
-- Shown rows now: 1 Hearthstone ... 8 class:9, 9 Empty Space, 10 Weapon ... 14 Gray.
assert(W.MoveRow(14, 1))
Expect("flag:gray item:6948 subclass:0:1 subclass:0:7 class:0 flag:quest+class:12 flag:unboundGear class:1 class:9 "
	.. "default | class:2 class:4 class:7 class:15", "Gray dragged to the top")
assert(W.MoveRow(10, 1)) -- the Empty Space to the top
Expect("| default flag:gray item:6948 subclass:0:1 subclass:0:7 class:0 flag:quest+class:12 flag:unboundGear class:1 "
	.. "class:9 class:2 class:4 class:7 class:15", "Empty Space dragged to the top")
assert(not W.MoveRow(3, 3) and not W.MoveRow(0, 2) and not W.MoveRow(2, 99), "bad moves accepted")
CheckSides()

-- Copy and restore.
local copy = W.CopyWeights()
W.SetLevel("class", 99, 1)
W.SetWeights(copy)
assert(SedimentDB.weights.classes[99] == nil, "restoring a copy didn't undo")
SedimentDB.weights.classes[3] = 1
assert(copy.classes[3] == nil, "the copy shares tables with the live weights")

print("ranking OK")
