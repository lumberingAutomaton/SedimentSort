-- Weights: resolve an item's weight through the cascade.
--   item weight > flags (Equipment set > Quest > Gray > BoE gear) > subclass > class > default
-- A level applies only if it has a weight. Weights are account-wide (SedimentDB.weights).

local _, ns = ...
local Weights = {}
ns.Weights = Weights

-- The default rule set: no rules. Copied into SedimentDB on first load, and by "Reset to default"; after
-- that the saved copy is what counts. With no rules every item ties, and ties fall back to the full order
-- (class > subclass > item), so Sediment starts out as an ordinary by-type bag sort; rules add the
-- player's own preferences. (It used to ship with the developer's own opinions, hearthstone on top and
-- weights for specific tools; the first outside tester found those unhelpful, 2026-11-24.)
local DEFAULTS = {
	sinkLine = 50,
	default = 20,
	items = {},
	flags = {},
	subclasses = {},
	classes = {},
}
local WEIGHTS_VERSION = 3 -- bump when a migration below is added

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
		-- A new install: the default (empty) rules, the Full auto-sort order (with no rules everything ties,
		-- and Partial keeps tied items where they are, so a messy bag would never get organized), and
		-- already up to date, so no migration below adds anything.
		SedimentDB.weights = DeepCopy(DEFAULTS)
		SedimentDB.weightsVersion = WEIGHTS_VERSION
		if SedimentDB.autoOrder == nil then
			SedimentDB.autoOrder = "full"
		end
	end
	local w = SedimentDB.weights
	-- Fill any level a newer version added, without touching the user's values.
	for k, v in pairs(DEFAULTS) do
		if w[k] == nil then
			w[k] = type(v) == "table" and DeepCopy(v) or v
		end
	end
	-- Migrations for saved rules from older versions; each runs once.
	SedimentDB.weightsVersion = SedimentDB.weightsVersion or 1
	if SedimentDB.weightsVersion < 2 then
		-- 0.3.0 added the Equipment set flag to the starter set of the time.
		if w.flags.equipmentSet == nil then
			w.flags.equipmentSet = 35
		end
	end
	SedimentDB.weightsVersion = WEIGHTS_VERSION
end

-- For the settings panel: flags in priority order with their labels, and a full reset.
Weights.FLAG_ORDER = FLAG_ORDER

function Weights.FlagLabel(flag)
	return FLAG_LABELS[flag] or flag
end

-- Do these rules say anything (any item, flag, subclass or class rule, or a keep-out rule)?
function Weights.HasRules()
	local w = SedimentDB.weights
	for _, t in ipairs({ w.items, w.flags, w.subclasses, w.classes }) do
		if next(t) then
			return true
		end
	end
	local ko = SedimentDB.keepOut
	return ko ~= nil and ((ko.items and next(ko.items)) or (ko.subclasses and next(ko.subclasses))) and true or false
end

-- One backup of the rules (weights and keep-out), taken before something replaces them wholesale: "Reset
-- to default" now, the onboarding questionnaire later. Only taken if there's something to keep.
function Weights.Backup(reason)
	if not Weights.HasRules() then
		return
	end
	SedimentDB.rulesBackup = {
		time = date("%Y-%m-%d %H:%M"),
		reason = reason,
		weights = DeepCopy(SedimentDB.weights),
		keepOut = SedimentDB.keepOut and DeepCopy(SedimentDB.keepOut) or nil,
	}
end

function Weights.BackupInfo()
	return SedimentDB.rulesBackup
end

-- Restore swaps: the current rules become the backup, so a restore can itself be undone. Unless the
-- current rules are empty (e.g. right after "Reset to default"): then there's nothing to keep, the backup
-- is cleared and the Restore button goes away, rather than offering to restore "no rules".
function Weights.RestoreBackup()
	local b = SedimentDB.rulesBackup
	if not b then
		return false
	end
	local current
	if Weights.HasRules() then
		current = {
			time = date("%Y-%m-%d %H:%M"),
			reason = "before restoring",
			weights = DeepCopy(SedimentDB.weights),
			keepOut = SedimentDB.keepOut and DeepCopy(SedimentDB.keepOut) or nil,
		}
	end
	SedimentDB.weights = DeepCopy(b.weights)
	SedimentDB.keepOut = b.keepOut and DeepCopy(b.keepOut) or nil
	SedimentDB.rulesBackup = current
	return true
end

-- "Reset to default": back up, then the default (empty) rules and no keep-out rules.
function Weights.ResetToDefault()
	Weights.Backup("before Reset to default")
	SedimentDB.weights = DeepCopy(DEFAULTS)
	SedimentDB.keepOut = nil
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

	-- Labelled with the item's name (covers every stack of that item).
	Add("item", item.itemID, item.name or "This item", w.items[item.itemID], true)
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
		return v, item.name or "This item"
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
