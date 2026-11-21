-- Check that Weights.Resolve (fast) always agrees with Weights.Explain (full) on random items.
Enum = { ItemQuality = { Poor = 0 } }
SedimentDB = {}
local ns = {}
assert(loadfile("Weights.lua"))("Sediment", ns)
ns.Weights.Init()
local w = SedimentDB.weights
math.randomseed(7)
local locs = { "", "INVTYPE_NON_EQUIP_IGNORE", "INVTYPE_WRIST", "INVTYPE_BAG", "INVTYPE_2HWEAPON" }
for i = 1, 20000 do
	-- Randomly clear or set levels so every path gets hit.
	if i % 50 == 0 then
		for _, f in ipairs({ "equipmentSet", "quest", "gray", "unboundGear" }) do
			w.flags[f] = math.random() < 0.3 and nil or math.random(0, 100)
		end
		w.subclasses["0:1"] = math.random() < 0.5 and nil or 8
		w.classes[4] = math.random() < 0.5 and nil or 40
		w.items[6948] = math.random() < 0.5 and nil or 0
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
