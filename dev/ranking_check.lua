-- Checks the ranking the setup questions use (Weights.RankingList / PlaceRule / WriteRankingList /
-- SetLayout): answers land where they should, weights stay on the right side of the sink line in every
-- layout, ties stay tied, and items sort in the order the ranking shows.
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

-- The order as a string: rule ids per rung, "|" for the divider.
local function Order()
	local parts = {}
	for _, e in ipairs(W.RankingList()) do
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

-- Every weight is on the side of the sink line its place says, in the current layout.
local function CheckSides()
	local w = SedimentDB.weights
	local layout, past = W.Layout(), false
	for _, e in ipairs(W.RankingList()) do
		if e.divider then
			past = true
		else
			for _, r in ipairs(e.rules) do
				local v = e.weight
				assert(v > 0 and v < 100, "weight out of 0..100: " .. tostring(v))
				if layout == "middle" then
					assert((v >= w.sinkLine) == past, "rule on the wrong side of the sink line")
				elseif layout == "bottom" then
					assert(v < w.sinkLine, "packed-from-top layout has a sinker")
				else
					assert(v >= w.sinkLine, "packed-from-bottom layout has a floater")
				end
			end
		end
	end
end

-- A new install answering the questions in order.
Fresh(nil)
Expect("default |", "new install")
W.SetLayout("middle")
assert(SedimentDB.weights.sinkLine == 50)
W.PlaceRule("item", HS, "first")
Expect("item:6948 default |", "hearthstone first")
W.PlaceRule("item", 4540, "after", "item", HS)
W.PlaceRule("item", 117, "after", "item", 4540)
Expect("item:6948 item:4540 item:117 default |", "neighbours in click order")
W.PlaceRule("flag", "gray", "bottom", "item", HS)
Expect("item:6948 item:4540 item:117 default | flag:gray", "gray at the bottom")
W.PlaceRule("class", 7, "sink")
Expect("item:6948 item:4540 item:117 default | class:7 flag:gray", "trade goods sink next to the gap")
W.PlaceRule("class", 0, "float")
Expect("item:6948 item:4540 item:117 class:0 default | class:7 flag:gray", "consumables float above the default")
CheckSides()

-- Re-answering moves the rule (it isn't duplicated).
W.PlaceRule("class", 7, "float")
Expect("item:6948 item:4540 item:117 class:0 class:7 default | flag:gray", "trade goods re-answered")
CheckSides()

-- Hearthstone last: gray goes above it; neighbours go before it, in click order.
Fresh(nil)
W.SetLayout("middle")
W.PlaceRule("item", HS, "last")
W.PlaceRule("item", 4540, "before", "item", HS)
W.PlaceRule("item", 117, "before", "item", HS)
W.PlaceRule("flag", "gray", "bottom", "item", HS)
Expect("default | item:4540 item:117 flag:gray item:6948", "hearthstone last")
CheckSides()

-- Packed layouts: everything floats (or sinks), order kept; what has no rule (the default) sits next to the
-- empty space: last when the space is at the bottom, first when it's at the top.
local WANT = {
	middle = "item:6948 class:0 default | class:7 flag:gray",
	bottom = "item:6948 class:0 | class:7 flag:gray default",
	top = "default item:6948 class:0 | class:7 flag:gray",
}
for _, layout in ipairs({ "bottom", "top" }) do
	Fresh(nil)
	W.SetLayout(layout)
	W.PlaceRule("item", HS, "first")
	W.PlaceRule("class", 7, "sink")
	W.PlaceRule("class", 0, "float")
	W.PlaceRule("flag", "gray", "bottom", "item", HS)
	Expect(WANT[layout], "packed " .. layout)
	CheckSides()
	assert(W.Layout() == layout)
end

-- Switching layout keeps the order; the default follows the empty space.
for _, layout in ipairs({ "middle", "bottom", "top", "middle" }) do
	W.SetLayout(layout)
	Expect(WANT[layout], "switch to " .. layout)
	CheckSides()
end

-- Bottom layout, hearthstone last: gray stays above it, the default after both (next to the space).
Fresh(nil)
W.SetLayout("bottom")
W.PlaceRule("item", HS, "last")
W.PlaceRule("flag", "gray", "bottom", "item", HS)
Expect("| flag:gray item:6948 default", "bottom layout, hearthstone last")

-- An existing user's hand-set rules: ties stay tied, order kept, sink line 40 becomes 50.
Fresh({ sinkLine = 40, default = 39, items = { [HS] = 0, [5] = 45 }, flags = { gray = 90 },
	subclasses = { ["0:1"] = 30, ["0:5"] = 30 }, classes = { [7] = 80, [2] = 45 } })
Expect("item:6948 subclass:0:1+subclass:0:5 default | item:5+class:2 class:7 flag:gray", "existing rules")
W.WriteRankingList(W.RankingList())
assert(SedimentDB.weights.sinkLine == 50)
Expect("item:6948 subclass:0:1+subclass:0:5 default | item:5+class:2 class:7 flag:gray", "existing rules tidied")
assert(SedimentDB.weights.subclasses["0:1"] == SedimentDB.weights.subclasses["0:5"], "a tie was broken")
CheckSides()

-- A hand-set default that sinks moves next to the gap (above it) at the first answer.
Fresh({ sinkLine = 50, default = 60, items = {}, flags = {}, subclasses = {}, classes = { [2] = 10 } })
W.PlaceRule("class", 0, "float")
W.PlaceRule("class", 7, "sink")
Expect("class:2 class:0 default | class:7", "a sinking default moves above the gap")
CheckSides()
-- A rule tied with the default stays where it was; the default gets a rung of its own.
Fresh({ sinkLine = 50, default = 20, items = {}, flags = {}, subclasses = {}, classes = { [2] = 20, [4] = 10 } })
Expect("class:4 class:2+default |", "tie before")
W.PlaceRule("class", 7, "sink")
Expect("class:4 class:2 default | class:7", "tie split off the default")

-- Many rungs: weights stay distinct and inside their half.
Fresh(nil)
W.SetLayout("middle")
for id = 1, 120 do
	W.PlaceRule("item", id, id % 2 == 0 and "float" or "sink")
end
local seen = {}
for _, e in ipairs(W.RankingList()) do
	if e.rules then
		assert(#e.rules == 1, "two rules fell onto one rung")
		assert(not seen[e.weight], "duplicate weight " .. e.weight)
		seen[e.weight] = true
	end
end
CheckSides()

-- Items sort in the order the ranking shows (full order: lighter first).
Fresh(nil)
W.SetLayout("middle")
W.PlaceRule("item", HS, "first")
W.PlaceRule("class", 7, "sink")
W.PlaceRule("flag", "gray", "bottom", "item", HS)
local function Item(itemID, classID, quality)
	return { itemID = itemID, classID = classID, subclassID = 0, subKey = classID .. ":0", quality = quality or 1,
		isBound = true, equipLoc = "" }
end
local hs, cloth, junk, other = Item(HS, 15), Item(2589, 7), Item(1000, 15, 0), Item(2000, 0)
local w = function(item) return (W.Resolve(item)) end
assert(w(hs) < w(other) and w(other) < w(cloth) and w(cloth) < w(junk), "items don't follow the order")
assert(w(other) < SedimentDB.weights.sinkLine and w(cloth) >= SedimentDB.weights.sinkLine, "float/sink wrong")
assert(W.HasOwnRule(hs) and not W.HasOwnRule(other), "HasOwnRule wrong")
assert(W.RuleSide("item", HS) == "float" and W.RuleSide("class", 7) == "sink" and W.RuleSide("class", 9) == nil)

-- Copy and restore (Back).
local copy = W.CopyWeights()
W.PlaceRule("class", 0, "float")
W.SetWeights(copy)
assert(SedimentDB.weights.classes[0] == nil, "restoring a copy didn't undo")
SedimentDB.weights.classes[3] = 1
assert(copy.classes[3] == nil, "the copy shares tables with the live weights")

print("ranking OK")
