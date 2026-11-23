-- Weights: resolve an item's weight through the cascade.
--   item weight > flags (Equipment set > Quest > Gray > BoE gear) > subclass > class > default
-- A level applies only if it has a weight. Weights are account-wide (SedimentDB.weights).

local _, ns = ...
local Weights = {}
ns.Weights = Weights

-- Starter preset. Copied into SedimentDB on first load; after that the saved copy is what counts.
local PRESET = {
	sinkLine = 50,
	default = 20,
	items = {
		[6948] = 0,    -- Hearthstone
		[2901] = 0.01, -- Mining Pick
		[6206] = 0.01, -- Rock Chipper
		[5956] = 0.01, -- Blacksmith Hammer
		[6256] = 0.02, -- Fishing Pole
		[4471] = 0.03, -- Flint and Tinder
	},
	flags = {
		equipmentSet = 35,
		quest = 51,
		gray = 100,
		unboundGear = 45,
	},
	subclasses = { -- key "classID:subclassID"
		["0:1"] = 8, -- Consumable > Potion
		["0:5"] = 9, -- Consumable > Food & Drink
	},
	classes = {
		[0] = 10,  -- Consumable
		[2] = 40,  -- Weapon
		[4] = 40,  -- Armor
		[7] = 30,  -- Trade Goods
		[12] = 51, -- Quest
		[15] = 15, -- Miscellaneous
	},
}

-- Equipment set comes first: if you put something in a set, you're keeping it, even if it's gray.
local FLAG_ORDER = { "equipmentSet", "quest", "gray", "unboundGear" }
local FLAG_LABELS = {
	equipmentSet = "Equipment set",
	quest = "Quest item",
	gray = "Gray quality",
	unboundGear = "BoE gear", -- equippable and not soulbound yet (internal name unboundGear)
}

-- Equip locations that don't count as gear for the BoE gear flag.
local NOT_GEAR = {
	[""] = true,
	INVTYPE_NON_EQUIP_IGNORE = true,
	INVTYPE_BAG = true,
	INVTYPE_QUIVER = true,
	INVTYPE_AMMO = true,
}

local function DeepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and DeepCopy(v) or v
	end
	return copy
end

function Weights.Init()
	if not SedimentDB.weights then
		SedimentDB.weights = DeepCopy(PRESET)
	end
	local w = SedimentDB.weights
	-- Fill any level a newer version added, without touching the user's values.
	for k, v in pairs(PRESET) do
		if w[k] == nil then
			w[k] = type(v) == "table" and DeepCopy(v) or v
		end
	end
	-- Flags added after the first release get their starter weight once. After that a cleared flag
	-- stays cleared.
	SedimentDB.weightsVersion = SedimentDB.weightsVersion or 1
	if SedimentDB.weightsVersion < 2 then
		if w.flags.equipmentSet == nil then
			w.flags.equipmentSet = PRESET.flags.equipmentSet
		end
		SedimentDB.weightsVersion = 2
	end
end

-- For the settings panel: flags in priority order with their labels, and a full reset.
Weights.FLAG_ORDER = FLAG_ORDER

function Weights.FlagLabel(flag)
	return FLAG_LABELS[flag] or flag
end

function Weights.ResetToPreset()
	SedimentDB.weights = DeepCopy(PRESET)
	SedimentDB.weightsVersion = 2
end

function Weights.SinkLine()
	return SedimentDB.weights.sinkLine
end

-- Which flags this item carries, in priority order.
local function ItemFlags(item)
	local flags = {}
	if item.inEquipmentSet then
		flags.equipmentSet = true
	end
	if item.isQuestItem then
		flags.quest = true
	end
	if item.quality == Enum.ItemQuality.Poor then
		flags.gray = true
	end
	if not item.isBound and not NOT_GEAR[item.equipLoc or ""] then
		flags.unboundGear = true
	end
	return flags
end

-- Returns every level of the cascade for this item, most specific first:
-- { { kind, key, label, weight = number or nil, applies = bool }, ... }
-- plus the index of the winning level. kind/key say where the weight is stored (see SetLevel).
function Weights.Explain(item)
	local w = SedimentDB.weights
	local levels = {}
	local function Add(kind, key, label, weight, applies)
		levels[#levels + 1] = { kind = kind, key = key, label = label, weight = weight, applies = applies }
	end

	Add("item", item.itemID, "This item", w.items[item.itemID], true)
	local flags = ItemFlags(item)
	for _, flag in ipairs(FLAG_ORDER) do
		Add("flag", flag, FLAG_LABELS[flag], w.flags[flag], flags[flag] or false)
	end
	local subKey = item.classID .. ":" .. item.subclassID
	Add("subclass", subKey, item.subclassName or ("Subclass " .. subKey), w.subclasses[subKey], true)
	Add("class", item.classID, item.className or ("Class " .. item.classID), w.classes[item.classID], true)
	Add("default", nil, "Default", w.default, true)

	for i, level in ipairs(levels) do
		if level.applies and level.weight ~= nil then
			return levels, i
		end
	end
	return levels, #levels
end

-- Store a weight for one level. nil clears it (that level then inherits), except for the default,
-- which must always have a value.
function Weights.SetLevel(kind, key, value)
	local w = SedimentDB.weights
	if kind == "item" then
		w.items[key] = value
	elseif kind == "flag" then
		w.flags[key] = value
	elseif kind == "subclass" then
		w.subclasses[key] = value
	elseif kind == "class" then
		w.classes[key] = value
	elseif kind == "default" and value ~= nil then
		w.default = value
	elseif kind == "sinkLine" and value ~= nil then
		w.sinkLine = value
	end
end

-- The same answer as Explain, without building any tables: the sort calls this for every item
-- on every planning pass, and Explain's tables were garbage for Lua to clean up each time.
-- Returns weight, label of the winning level.
function Weights.Resolve(item)
	local w = SedimentDB.weights
	local v = w.items[item.itemID]
	if v ~= nil then
		return v, "This item"
	end
	local flags = w.flags
	if item.inEquipmentSet and flags.equipmentSet ~= nil then
		return flags.equipmentSet, FLAG_LABELS.equipmentSet
	end
	if item.isQuestItem and flags.quest ~= nil then
		return flags.quest, FLAG_LABELS.quest
	end
	if item.quality == Enum.ItemQuality.Poor and flags.gray ~= nil then
		return flags.gray, FLAG_LABELS.gray
	end
	if flags.unboundGear ~= nil and not item.isBound and not NOT_GEAR[item.equipLoc or ""] then
		return flags.unboundGear, FLAG_LABELS.unboundGear
	end
	v = w.subclasses[item.subKey or (item.classID .. ":" .. item.subclassID)]
	if v ~= nil then
		return v, item.subclassName or "Subclass"
	end
	v = w.classes[item.classID]
	if v ~= nil then
		return v, item.className or "Class"
	end
	return w.default, "Default"
end
