-- Weights: resolve an item's weight through the cascade.
--   item weight > flags (Equipment set > Quest > Gray > BoE gear) > subclass > class > default
-- A level applies only if it has a weight. Weights are account-wide (SedimentDB.weights).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Weights.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Weights = {}
ns.Weights = Weights

-- Text.lua (the words) is new in 0.17.1, and a /reload doesn't load new files. Without it, words show as
-- their keys instead of erroring, and Sediment.lua's login check says to restart the game.
if not ns.L then
	ns.L = function(key) return key end
	ns.Noun, ns.Btn = ns.L, ns.L
end

-- The default rule set: no rules. Copied into SedimentDB on first load, and by Start Fresh; after
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
	-- The single backup slot before History (0.16.0): it becomes the oldest version.
	local b = SedimentDB.rulesBackup
	if b then
		local h = Weights.History()
		h[#h + 1] = { time = b.time or "?", reason = b.reason, weights = b.weights, keepOut = b.keepOut }
		SedimentDB.rulesBackup = nil
	end
	-- Older entries: ids (for Active / Previous); one pin only, the most recently pinned (0.17.0 "Kept"
	-- entries, named, count as pinned).
	local keep, keepTime
	for _, e in ipairs(Weights.History()) do
		if not e.id then
			SedimentDB.nextSaveId = (SedimentDB.nextSaveId or 0) + 1
			e.id = SedimentDB.nextSaveId
		end
		local t = (e.pinned or (e.name and e.keptTime ~= nil) or e.name) and (e.pinnedTime or e.keptTime or e.time or "")
		if t and (not keepTime or t > keepTime) then
			keep, keepTime = e, t
		end
		e.pinned, e.pinnedTime, e.keptTime = nil, nil, nil
	end
	if keep then
		keep.pinned = true
	end
	Weights.PurgeDeleted() -- deletes not undone before the last logout
	Weights.NoteActive()
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

-- History ------------------------------------------------------------------------------------
-- A safety net of the rules (weights, sink line, default, keep-out), newest first, in SedimentDB.history.
-- Two kinds of entry (user, 2026-11-25; a design with named rulesets was parked as "Profiles"):
--   Created:  made when Setup is done. Always a new entry, even if identical to another.
--   Snapshot: made automatically at logout (and /reload), before Load and Start Fresh, and at login as a
--             safety net; only if no entry already holds the rules in use.
-- Each entry: { id, kind, character, time, pinned, deleted, weights, keepOut }; entries from before this
-- (0.17.0/early 0.17.1) may have reason/name instead of kind/character and show those. One entry can be
-- pinned: it's listed first and never dropped. Of the rest, the newest 20 are kept. A delete only marks the
-- entry (the row shows Undo) until the settings window closes (PurgeDeleted). Auto-sort settings aren't part
-- of an entry. Titles: "Rook — Snapshot — Nov 25, 10:32" (EntryTitle).
local HISTORY_KEEP = 20

-- The same text for the same contents, whatever order pairs() visits them in.
local function Serialize(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = tostring(k) .. "=" .. Serialize(v[k])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function VersionKey(weights, keepOut)
	keepOut = keepOut or {}
	return Serialize(weights) .. "|" .. Serialize({ items = keepOut.items or {}, subclasses = keepOut.subclasses or {} })
end

local function CurrentKey()
	return VersionKey(SedimentDB.weights, SedimentDB.keepOut)
end

local function Now()
	return date("%Y-%m-%d %H:%M")
end

-- The character entries are labelled with (set at login; rules themselves are account-wide).
function Weights.SetCharacter(name)
	Weights.character = name
end

function Weights.History()
	SedimentDB.history = SedimentDB.history or {}
	return SedimentDB.history
end

-- Are these the rules in use now?
function Weights.IsCurrent(entry)
	return VersionKey(entry.weights, entry.keepOut) == CurrentKey()
end

local function Prune(h)
	local unpinned, i = 0, 1
	while i <= #h do
		if h[i].pinned then
			i = i + 1
		else
			unpinned = unpinned + 1
			if unpinned > HISTORY_KEEP then
				table.remove(h, i)
			else
				i = i + 1
			end
		end
	end
end

-- The entry holding the rules in use, if any (the newest such).
function Weights.ActiveSave()
	for _, e in ipairs(Weights.History()) do
		if not e.deleted and Weights.IsCurrent(e) then
			return e
		end
	end
end

local function SaveById(id)
	if id then
		for _, e in ipairs(Weights.History()) do
			if e.id == id and not e.deleted then
				return e
			end
		end
	end
end

-- Which entry is Active, and which was Active before it (Previous: what you'd roll back to). Kept by id
-- (SedimentDB.activeSaveId / previousSaveId; table references don't survive a reload), updated whenever the
-- rules or History change. While the rules match no entry (edited, not saved yet), the last Active one stays
-- recorded, so it's Previous: the rules from before the edits.
function Weights.NoteActive()
	local a = Weights.ActiveSave()
	if a and a.id ~= SedimentDB.activeSaveId then
		SedimentDB.previousSaveId = SedimentDB.activeSaveId
		SedimentDB.activeSaveId = a.id
	end
end

local function AddEntry(kind)
	local h = Weights.History()
	SedimentDB.nextSaveId = (SedimentDB.nextSaveId or 0) + 1
	table.insert(h, 1, {
		id = SedimentDB.nextSaveId,
		kind = kind,
		character = Weights.character,
		time = Now(),
		weights = DeepCopy(SedimentDB.weights),
		keepOut = SedimentDB.keepOut and DeepCopy(SedimentDB.keepOut) or nil,
	})
	Prune(h)
	Weights.NoteActive()
	return h[1]
end

-- A Snapshot of the rules in use, unless an entry already holds them (then that one is returned second) or
-- there are no rules at all.
function Weights.Snapshot()
	local same = Weights.ActiveSave()
	if same then
		Weights.NoteActive()
		return nil, same
	end
	if not Weights.HasRules() then
		return nil
	end
	return AddEntry("snapshot")
end

-- A Created entry (Setup done): always new.
function Weights.Created()
	return AddEntry("created")
end

-- One pin at a time: pinning an entry unpins any other (user, 2026-11-25).
function Weights.Pin(entry)
	for _, e in ipairs(Weights.History()) do
		e.pinned = nil
	end
	entry.pinned = true
end

function Weights.Unpin(entry)
	entry.pinned = nil
end

-- History as the section lists it: the pinned entry first, then the rest newest first. Entries waiting to be
-- deleted stay in place (shown greyed, with Undo).
function Weights.HistoryForDisplay()
	local list, pinned = {}, nil
	for _, e in ipairs(Weights.History()) do
		if e.pinned and not pinned then
			pinned = e
		else
			list[#list + 1] = e
		end
	end
	if pinned then
		table.insert(list, 1, pinned)
	end
	return list
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "2026-11-25 10:32" -> "Nov 25, 10:32".
local function ShortTime(t)
	local _, m, d, hm = (t or ""):match("^(%d+)%-(%d+)%-(%d+) (%d+:%d+)$")
	if not m then
		return t or "?"
	end
	return ("%s %d, %s"):format(MONTHS[tonumber(m)] or m, tonumber(d), hm)
end

-- "Rook — Snapshot — Nov 25, 10:32". Older entries without kind/character show their name or reason.
function Weights.EntryTitle(entry)
	local parts = {}
	if entry.character then
		parts[#parts + 1] = entry.character
	elseif entry.name or entry.reason then
		parts[#parts + 1] = entry.name or entry.reason
	end
	parts[#parts + 1] = ns.L(entry.kind == "created" and "EntryCreated" or "EntrySnapshot")
	parts[#parts + 1] = ShortTime(entry.time)
	return table.concat(parts, " — ")
end

-- x marks an entry; Undo unmarks it; closing the settings window removes the marked ones for good.
function Weights.DeleteVersion(entry)
	entry.deleted = true
end

function Weights.UndeleteVersion(entry)
	entry.deleted = nil
end

function Weights.PurgeDeleted()
	local h = Weights.History()
	for i = #h, 1, -1 do
		if h[i].deleted then
			table.remove(h, i)
		end
	end
end

-- What you'd roll back to (History marks it Previous): the entry that was Active before the current one; or,
-- while the rules match no entry, the last Active one. Falls back to the newest entry that isn't in use.
function Weights.PreviousSave()
	Weights.NoteActive()
	local active = Weights.ActiveSave()
	local p = SaveById(active and SedimentDB.previousSaveId or SedimentDB.activeSaveId)
	if p and not Weights.IsCurrent(p) then
		return p
	end
	for _, e in ipairs(Weights.History()) do
		if not e.deleted and not Weights.IsCurrent(e) then
			return e
		end
	end
end

-- Put an entry's rules back. The rules in use get a Snapshot first (if not saved), so loading can be undone.
function Weights.LoadVersion(entry)
	Weights.Snapshot()
	SedimentDB.weights = DeepCopy(entry.weights)
	SedimentDB.keepOut = entry.keepOut and DeepCopy(entry.keepOut) or nil
	Weights.NoteActive()
end

-- How an entry reads in a list: "23 Weights, sink line 40, 1 kept out".
function Weights.VersionSummary(entry)
	local w, n = entry.weights, 0
	for _, t in ipairs({ w.items, w.flags, w.subclasses, w.classes }) do
		for _ in pairs(t) do
			n = n + 1
		end
	end
	local ko, k = entry.keepOut or {}, 0
	for _, t in ipairs({ ko.items or {}, ko.subclasses or {} }) do
		for _ in pairs(t) do
			k = k + 1
		end
	end
	local text = ("%d %s, %s at %s"):format(n, n == 1 and ns.L("SortValue") or ns.L("SortValues"), ns.L("LootGap"),
		tostring(w.sinkLine))
	if k > 0 then
		text = text .. (", %d kept out"):format(k) -- short: the row has little room; hover lists them
	end
	return text
end

-- Start Fresh: a Snapshot of the rules (if not saved), then the default (empty) weights and no keep-out rules.
function Weights.ClearAll()
	Weights.Snapshot()
	SedimentDB.weights = DeepCopy(DEFAULTS)
	SedimentDB.keepOut = nil
	Weights.NoteActive()
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
Weights.ItemFlags = ItemFlags

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
	Add("default", nil, "Not set (default)", w.default, true)

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
	return w.default, "Not set (default)"
end

-- Does this item have a rule of its own (anything but the default)? The setup questions outline the
-- bag slots that don't.
function Weights.HasOwnRule(item)
	local levels, winner = Weights.Explain(item)
	return levels[winner].kind ~= "default"
end

-- A copy of the weights, and putting one back (the setup questions' Back).
function Weights.CopyWeights()
	return DeepCopy(SedimentDB.weights)
end

function Weights.SetWeights(copy)
	SedimentDB.weights = DeepCopy(copy)
end

-- Ranking ------------------------------------------------------------------------------------
-- The same rules seen as an order instead of numbers, which is how the setup questions work: a list of
-- rungs, light to heavy, each rung the rules sharing one weight (the default is a rule too), with one
-- divider between the start half and the end half. In the middle layout the divider is the sink line;
-- in the packed layouts (sink line 100 or 0: everything floats, or everything sinks) it only splits
-- "near the start" from "near the end". Writing a list back gives every rung a tidy weight: start-half
-- rungs between 0 and 50, end-half rungs between 50 and 100, in list order, and a sink line between 0
-- and 100 becomes 50. So after the setup questions every rule's weight is just its place in the order.

local KIND_RANK = { item = 1, flag = 2, subclass = 3, class = 4, default = 5 }

-- Where the list splits: the sink line in the middle layout, else 50.
function Weights.RankSplit()
	local s = SedimentDB.weights.sinkLine
	if s > 0 and s < 100 then
		return s
	end
	return 50
end

-- "middle" (sink line between 0 and 100: the empty space is in the middle), "bottom" (100 or more:
-- everything packs from the top, the space is at the bottom) or "top" (0 or less).
function Weights.Layout()
	local s = SedimentDB.weights.sinkLine
	if s >= 100 then
		return "bottom"
	elseif s <= 0 then
		return "top"
	end
	return "middle"
end

-- Every rule with a weight as a ranking list: rungs { weight, rules = { { kind, key }, ... } } and one
-- { divider = true }.
function Weights.RankingList()
	local w = SedimentDB.weights
	local rules = {}
	local function Add(kind, key, weight)
		rules[#rules + 1] = { kind = kind, key = key, weight = weight }
	end
	for k, v in pairs(w.items) do
		Add("item", k, v)
	end
	for k, v in pairs(w.flags) do
		Add("flag", k, v)
	end
	for k, v in pairs(w.subclasses) do
		Add("subclass", k, v)
	end
	for k, v in pairs(w.classes) do
		Add("class", k, v)
	end
	Add("default", nil, w.default)
	table.sort(rules, function(a, b)
		if a.weight ~= b.weight then
			return a.weight < b.weight
		end
		if KIND_RANK[a.kind] ~= KIND_RANK[b.kind] then
			return KIND_RANK[a.kind] < KIND_RANK[b.kind]
		end
		return tostring(a.key) < tostring(b.key)
	end)
	local split = Weights.RankSplit()
	local list, rung, divided = {}, nil, false
	for _, r in ipairs(rules) do
		if not divided and r.weight >= split then
			list[#list + 1] = { divider = true }
			divided, rung = true, nil
		end
		if not rung or rung.weight ~= r.weight then
			rung = { weight = r.weight, rules = {} }
			list[#list + 1] = rung
		end
		rung.rules[#rung.rules + 1] = { kind = r.kind, key = r.key }
	end
	if not divided then
		list[#list + 1] = { divider = true }
	end
	return list
end

-- n evenly spaced weights above base, all below base + 50: steps of 10 while they fit, else smaller,
-- else fractions (rounded to hundredths; still distinct for thousands of rungs).
local function Spread(n, base)
	local step = math.floor(49 / (n + 1))
	if step > 10 then
		step = 10
	end
	if step < 1 then
		step = 49 / (n + 1)
		return function(i)
			return math.floor((base + i * step) * 100 + 0.5) / 100
		end
	end
	return function(i)
		return base + i * step
	end
end

local function FindRule(list, kind, key)
	for i, e in ipairs(list) do
		if e.rules then
			for j, r in ipairs(e.rules) do
				if r.kind == kind and r.key == key then
					return i, j
				end
			end
		end
	end
end
Weights.FindRule = FindRule

local function DividerIndex(list)
	for i, e in ipairs(list) do
		if e.divider then
			return i
		end
	end
end

local function TakeOut(list, kind, key)
	local i, j = FindRule(list, kind, key)
	if i then
		table.remove(list[i].rules, j)
		if #list[i].rules == 0 then
			table.remove(list, i)
		end
	end
end

-- Everything without a rule (the default) always sits next to the empty space, on a rung of its own: in the
-- middle layout last in the start half, just above the gap, where new loot lands; packed from the top (space
-- at the bottom) last of all; packed from the bottom first of all. It isn't a place you choose. (User,
-- 2026-11-24: as a movable "Everything else" row it put random stuff among the packed items.)
function Weights.PinDefault(list)
	TakeOut(list, "default")
	local rung = { rules = { { kind = "default" } } }
	local layout = Weights.Layout()
	if layout == "bottom" then
		list[#list + 1] = rung
	elseif layout == "top" then
		table.insert(list, 1, rung)
	else
		table.insert(list, DividerIndex(list), rung)
	end
	return list
end

function Weights.WriteRankingList(list)
	Weights.PinDefault(list)
	local w = SedimentDB.weights
	local floatN, sinkN, past = 0, 0, false
	for _, e in ipairs(list) do
		if e.divider then
			past = true
		elseif past then
			sinkN = sinkN + 1
		else
			floatN = floatN + 1
		end
	end
	local floatW, sinkW = Spread(floatN, 0), Spread(sinkN, 50)
	local fi, si = 0, 0
	past = false
	for _, e in ipairs(list) do
		if e.divider then
			past = true
		else
			local weight
			if past then
				si = si + 1
				weight = sinkW(si)
			else
				fi = fi + 1
				weight = floatW(fi)
			end
			e.weight = weight
			for _, r in ipairs(e.rules) do
				if r.kind == "default" then
					w.default = weight
				else
					Weights.SetLevel(r.kind, r.key, weight)
				end
			end
		end
	end
	if w.sinkLine > 0 and w.sinkLine < 100 then
		w.sinkLine = 50
	end
end

-- Which half a rule is in: "float" (start) or "sink" (end); nil if it has no weight.
function Weights.RuleSide(kind, key)
	local list = Weights.RankingList()
	local i = FindRule(list, kind, key)
	if not i then
		return nil
	end
	return i < DividerIndex(list) and "float" or "sink"
end

-- Give a rule its own rung at a place in the order (taking it out of wherever it was), then write the
-- order back (which puts the default next to the empty space). where:
--   "first" / "last":  before / after everything you've set.
--   "float":  last in the start half (in the middle layout, just above the default, next to the gap).
--   "sink":   first in the end half.
--   "bottom": last, but above the anchor rule if that's last (gray junk under everything, except a
--             hearthstone someone put last).
--   "after" / "before": next to the anchor rule (anchorKind, anchorKey).
function Weights.PlaceRule(kind, key, where, anchorKind, anchorKey)
	local list = Weights.RankingList()
	TakeOut(list, kind, key)
	TakeOut(list, "default") -- placed by the write
	local d = DividerIndex(list)
	local at
	if where == "first" then
		at = 1
	elseif where == "last" then
		at = #list + 1
	elseif where == "float" then
		at = d
	elseif where == "sink" then
		at = d + 1
	elseif where == "bottom" then
		at = #list + 1
		local a = anchorKind and FindRule(list, anchorKind, anchorKey)
		if a and a == #list and a > d then
			at = a
		end
	elseif where == "after" or where == "before" then
		local a = FindRule(list, anchorKind, anchorKey)
		at = a and (where == "after" and a + 1 or a) or d
	else
		error("PlaceRule: unknown place " .. tostring(where))
	end
	table.insert(list, at, { rules = { { kind = kind, key = key } } })
	Weights.WriteRankingList(list)
end

-- The setup's first question: where the empty space goes. Tidies the weights into the order first, then
-- sets the sink line: 50 (middle), 100 (everything packs from the top) or 0 (from the bottom).
function Weights.SetLayout(layout)
	local list = Weights.RankingList() -- split by the old sink line
	SedimentDB.weights.sinkLine = layout == "bottom" and 100 or layout == "top" and 0 or 50
	Weights.WriteRankingList(list) -- the default moves next to the new empty space
end
