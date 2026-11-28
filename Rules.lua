-- Weights: resolve an item's weight through the cascade.
--   item weight > flags (Equipment set > Quest > Gray > BoE gear) > subclass > class > default
-- A level applies only if it has a weight. Weights are account-wide (DisorderItemManagerDB.weights).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Rules.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Weights = {}
ns.Weights = Weights

-- Text.lua (the words) is new in 0.17.1, and a /reload doesn't load new files. Without it, words show as
-- their keys instead of erroring, and Sediment.lua's login check says to restart the game.
if not ns.L then
	ns.L = function(key) return key end
	ns.Noun, ns.Btn = ns.L, ns.L
end

-- The default rule set: no rules. Copied into DisorderItemManagerDB on first load, and by Start Fresh; after
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
local FLAG_LABELS = { -- Title Case, like the game's own group names (user, 2026-11-25)
	equipmentSet = "Equipment Set",
	quest = "Quest Items",
	gray = "Gray Quality",
	unboundGear = "BoE Gear", -- equippable and not soulbound yet (internal name unboundGear)
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
	if not DisorderItemManagerDB.weights then
		-- A new install: the default (empty) rules, already up to date, so no migration below adds anything.
		DisorderItemManagerDB.weights = DeepCopy(DEFAULTS)
		DisorderItemManagerDB.weightsVersion = WEIGHTS_VERSION
	end
	local w = DisorderItemManagerDB.weights
	-- Fill any level a newer version added, without touching the user's values.
	for k, v in pairs(DEFAULTS) do
		if w[k] == nil then
			w[k] = type(v) == "table" and DeepCopy(v) or v
		end
	end
	-- Migrations for saved rules from older versions; each runs once.
	DisorderItemManagerDB.weightsVersion = DisorderItemManagerDB.weightsVersion or 1
	if DisorderItemManagerDB.weightsVersion < 2 then
		-- 0.3.0 added the Equipment set flag to the starter set of the time.
		if w.flags.equipmentSet == nil then
			w.flags.equipmentSet = 35
		end
	end
	DisorderItemManagerDB.weightsVersion = WEIGHTS_VERSION
	-- The single backup slot before History (0.16.0): it becomes the oldest version.
	local b = DisorderItemManagerDB.rulesBackup
	if b then
		local h = Weights.History()
		h[#h + 1] = { time = b.time or "?", reason = b.reason, weights = b.weights, keepOut = b.keepOut }
		DisorderItemManagerDB.rulesBackup = nil
	end
	-- Older entries: ids (for Active / Previous); one pin only, the most recently pinned (0.17.0 "Kept"
	-- entries, named, count as pinned).
	local keep, keepTime
	for _, e in ipairs(Weights.History()) do
		if not e.id then
			DisorderItemManagerDB.nextSaveId = (DisorderItemManagerDB.nextSaveId or 0) + 1
			e.id = DisorderItemManagerDB.nextSaveId
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
	-- The Setup window (0.17-0.18) became the settings' Order section: its saved state goes.
	DisorderItemManagerDB.setup, DisorderItemManagerDB.setupHidden, DisorderItemManagerDB.setupPos = nil, nil, nil
	DisorderItemManagerDB.popupPos = nil -- the weight popup always opens above the bag now (0.19)
	-- Settings that are fixed since 0.20 (user, 2026-11-26): auto-sort always on, the full order always,
	-- bags opening mid-sort always finish; debug tools come with the debug addon, not a switch.
	DisorderItemManagerDB.autoSort, DisorderItemManagerDB.autoOrder, DisorderItemManagerDB.openBags, DisorderItemManagerDB.testingTools = nil, nil, nil, nil
end


-- For the settings panel: flags in priority order with their labels, and a full reset.
Weights.FLAG_ORDER = FLAG_ORDER

function Weights.FlagLabel(flag)
	return FLAG_LABELS[flag] or flag
end

-- Do these rules say anything (any item, flag, subclass or class rule, or a keep-out rule)?
function Weights.HasRules()
	local w = DisorderItemManagerDB.weights
	for _, t in ipairs({ w.items, w.flags, w.subclasses, w.classes }) do
		if next(t) then
			return true
		end
	end
	local ko = DisorderItemManagerDB.keepOut
	return ko ~= nil and ((ko.items and next(ko.items)) or (ko.subclasses and next(ko.subclasses))) and true or false
end

-- History ------------------------------------------------------------------------------------
-- A safety net of the rules (weights, sink line, default, keep-out), newest first, in DisorderItemManagerDB.history.
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
	return VersionKey(DisorderItemManagerDB.weights, DisorderItemManagerDB.keepOut)
end

local function Now()
	return date("%Y-%m-%d %H:%M")
end

-- The character entries are labelled with (set at login; rules themselves are account-wide).
function Weights.SetCharacter(name)
	Weights.character = name
end

function Weights.History()
	DisorderItemManagerDB.history = DisorderItemManagerDB.history or {}
	return DisorderItemManagerDB.history
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
-- (DisorderItemManagerDB.activeSaveId / previousSaveId; table references don't survive a reload), updated whenever the
-- rules or History change. While the rules match no entry (edited, not saved yet), the last Active one stays
-- recorded, so it's Previous: the rules from before the edits.
function Weights.NoteActive()
	local a = Weights.ActiveSave()
	if a and a.id ~= DisorderItemManagerDB.activeSaveId then
		DisorderItemManagerDB.previousSaveId = DisorderItemManagerDB.activeSaveId
		DisorderItemManagerDB.activeSaveId = a.id
	end
end

local function AddEntry(kind)
	local h = Weights.History()
	DisorderItemManagerDB.nextSaveId = (DisorderItemManagerDB.nextSaveId or 0) + 1
	table.insert(h, 1, {
		id = DisorderItemManagerDB.nextSaveId,
		kind = kind,
		character = Weights.character,
		time = Now(),
		weights = DeepCopy(DisorderItemManagerDB.weights),
		keepOut = DisorderItemManagerDB.keepOut and DeepCopy(DisorderItemManagerDB.keepOut) or nil,
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
	local p = SaveById(active and DisorderItemManagerDB.previousSaveId or DisorderItemManagerDB.activeSaveId)
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
	DisorderItemManagerDB.weights = DeepCopy(entry.weights)
	DisorderItemManagerDB.keepOut = entry.keepOut and DeepCopy(entry.keepOut) or nil
	Weights.NoteActive()
end

-- How an entry reads in a list: "23 ordered, 1 kept out" (no "Weight" and no number for the Empty Space,
-- which is always 50 since 0.18: user, 2026-11-26; hovering the entry lists the order).
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
	local text = ("%d ordered"):format(n)
	if k > 0 then
		text = text .. (", %d kept out"):format(k) -- short: the row has little room; hover lists them
	end
	return text
end

-- Start Fresh: a Snapshot of the rules (if not saved), then the default (empty) weights and no keep-out rules.
function Weights.ClearAll()
	Weights.Snapshot()
	DisorderItemManagerDB.weights = DeepCopy(DEFAULTS)
	DisorderItemManagerDB.keepOut = nil
	Weights.NoteActive()
end

function Weights.SinkLine()
	return DisorderItemManagerDB.weights.sinkLine
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
	local w = DisorderItemManagerDB.weights
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
	local w = DisorderItemManagerDB.weights
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
	local w = DisorderItemManagerDB.weights
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
	return DeepCopy(DisorderItemManagerDB.weights)
end

function Weights.SetWeights(copy)
	DisorderItemManagerDB.weights = DeepCopy(copy)
end

-- Ranking ------------------------------------------------------------------------------------
-- The rules seen as an order instead of numbers, which is how the Order list works: a list of rungs, light to heavy, each rung the rules sharing one weight (the
-- default is a rule too), and one divider: the Empty Space. Rungs above it float, rungs below it sink, so its
-- position is the layout (user, 2026-11-25): at the top, everything packs toward the bottom; at the bottom,
-- everything packs from the top; in between, the gap is in the middle. Writing a list back gives every rung a
-- tidy weight by position (above the divider 0-50, below 50-100) and the sink line is always 50. Saves from
-- before used 100 / 0 for the packed layouts; RankingList reads those with the divider at the end / start, so
-- the first write converts them without changing the order.

local KIND_RANK = { item = 1, flag = 2, subclass = 3, class = 4, default = 5 }

-- How an old save's sink line reads: "bottom" (100 or more: the space at the bottom), "top" (0 or less) or
-- "middle". After any write it's always "middle", with the divider's position doing the work.
function Weights.Layout()
	local s = DisorderItemManagerDB.weights.sinkLine
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
	local w = DisorderItemManagerDB.weights
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
	local layout = Weights.Layout()
	local split = w.sinkLine
	local list, rung, divided = {}, nil, false
	if layout == "top" then
		list[1] = { divider = true }
		divided = true
	end
	for _, r in ipairs(rules) do
		if not divided and layout == "middle" and r.weight >= split then
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

-- Everything without a rule (the default) is attached to the Empty Space, on its own rung, on the side that
-- has items: just below it when nothing is above it, else just above it. It isn't a row you move (user,
-- 2026-11-24/25: a movable "Everything else" put random stuff among the packed items).
function Weights.PinDefault(list)
	TakeOut(list, "default")
	local rung = { rules = { { kind = "default" } } }
	local d = DividerIndex(list)
	if d == 1 then
		table.insert(list, 2, rung)
	else
		table.insert(list, d, rung)
	end
	return list
end

function Weights.WriteRankingList(list)
	Weights.PinDefault(list)
	local w = DisorderItemManagerDB.weights
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
	w.sinkLine = 50
end

-- Move the Empty Space one row up (dir -1) or down (+1) past the next rung, then write the order back (the
-- default follows it). Returns true if it moved.
function Weights.MoveEmptySpace(dir)
	local list = Weights.RankingList()
	TakeOut(list, "default")
	local d = DividerIndex(list)
	local j = d + dir
	if j < 1 or j > #list then
		return false
	end
	list[d], list[j] = list[j], list[d]
	Weights.WriteRankingList(list)
	return true
end

-- Can the Empty Space move that way (is there a row other than the unset items to pass)?
function Weights.CanMoveEmptySpace(dir)
	local list = Weights.RankingList()
	TakeOut(list, "default")
	local j = DividerIndex(list) + dir
	return j >= 1 and j <= #list
end

-- Setup's Pick from Bags: give a rule its own row right above the row that decides this item today, so the
-- sort barely changes until it's moved (for an unset item, next to the unset items by the Empty Space).
-- Returns false if the rule already has a row.
function Weights.AddRuleAbove(kind, key, item)
	local list = Weights.PinDefault(Weights.RankingList())
	if FindRule(list, kind, key) then
		return false
	end
	local levels, winner = Weights.Explain(item)
	local deciding = levels[winner]
	local at = FindRule(list, deciding.kind, deciding.key)
	if deciding.kind == "default" and at > DividerIndex(list) then
		at = at + 1 -- unset items below the Empty Space: just after them
	end
	table.insert(list, at, { rules = { { kind = kind, key = key } } })
	Weights.WriteRankingList(list)
	return true
end

-- Widening a pick: the new rule takes the old one's place in its row (all Cloth where Mageweave Cloth was).
-- If the new rule already has a row, the old one just goes.
function Weights.ReplaceRule(oldKind, oldKey, newKind, newKey)
	local list = Weights.PinDefault(Weights.RankingList())
	local i, j = FindRule(list, oldKind, oldKey)
	if not i then
		return
	end
	Weights.SetLevel(oldKind, oldKey, nil)
	if FindRule(list, newKind, newKey) then
		TakeOut(list, oldKind, oldKey)
	else
		list[i].rules[j] = { kind = newKind, key = newKey }
	end
	Weights.WriteRankingList(list)
end

-- Start Fresh's order (user, 2026-11-27): only the Hearthstone first and Gray Quality last, the Empty Space between
-- them; everything else isn't ordered yet and sorts by type next to the Empty Space, close to WoW's own sort, so
-- nothing jarring on the first open. (It used to lay out ten groups.)
function Weights.DefaultOrder()
	Weights.WriteRankingList({
		{ rules = { { kind = "item", key = 6948 } } }, -- Hearthstone
		{ divider = true },
		{ rules = { { kind = "flag", key = "gray" } } }, -- Gray Quality
	})
end

-- Move a row (any rung but the unset items', or the Empty Space) to a new place among the rows shown: drag
-- and drop in the Order list. from / to are positions in the list without the unset items' rung; to is where it ends
-- up. The unset items re-attach to the Empty Space on the write.
function Weights.MoveRow(from, to)
	local list = Weights.RankingList()
	TakeOut(list, "default")
	if from < 1 or from > #list or to < 1 or to > #list or from == to then
		return false
	end
	local e = table.remove(list, from)
	table.insert(list, to, e)
	Weights.WriteRankingList(list)
	return true
end
