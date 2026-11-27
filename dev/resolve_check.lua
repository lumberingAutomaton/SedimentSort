-- Check that Weights.Resolve (fast) always agrees with Weights.Explain (full) on random items.
Enum = { ItemQuality = { Poor = 0 } }
DisorderItemManagerDB = {}
local ns = {}
assert(loadfile("Rules.lua"))("Disorder_ItemManager", ns)
ns.Weights.Init()
local w = DisorderItemManagerDB.weights
math.randomseed(7)
local locs = { "", "INVTYPE_NON_EQUIP_IGNORE", "INVTYPE_WRIST", "INVTYPE_BAG", "INVTYPE_2HWEAPON" }
for i = 1, 20000 do
	-- Randomly clear or set levels so every path gets hit.
	if i % 50 == 0 then
		-- (Not "c and nil or x": that's always x, so levels were never cleared; fixed 2026-11-25.)
		local function Maybe(chance, value)
			if math.random() < chance then
				return nil
			end
			return value
		end
		for _, f in ipairs({ "equipmentSet", "quest", "gray", "unboundGear" }) do
			w.flags[f] = Maybe(0.3, math.random(0, 100))
		end
		w.subclasses["0:1"] = Maybe(0.5, 8)
		w.classes[4] = Maybe(0.5, 40)
		w.items[6948] = Maybe(0.5, 0)
	end
	local item = {
		itemID = math.random() < 0.1 and 6948 or math.random(1, 100),
		classID = math.random(0, 4), subclassID = math.random(0, 2),
		quality = math.random(0, 3), isBound = math.random() < 0.5,
		isQuestItem = math.random() < 0.2, inEquipmentSet = math.random() < 0.2,
		equipLoc = locs[math.random(#locs)], className = "C", subclassName = "S",
	}
	item.subKey = item.classID .. ":" .. item.subclassID
	local levels, winner = ns.Weights.Explain(item)
	local fast = ns.Weights.Resolve(item)
	assert(fast == levels[winner].weight, ("mismatch on case %d"):format(i))
end
print("Resolve matches Explain on 20000 random items")
