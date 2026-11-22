-- Offline simulation of the Sediment sort. Not loaded by the game.
-- Usage: lua dev/sim.lua <path to WTF SavedVariables/Sediment.lua> [seed] [show|bench]
-- SEDIMENT_ORDER=stable, stableSets or stableFill (environment) swaps in an experimental
-- within-weight order: current position instead of class/subclass/item ID (stableSets keeps set
-- names first; stableFill also moves one whole group of identical items to fill a hole). "bench"
-- runs realistic events from a sorted bag and reports the average moves each costs.
-- Loads the bag scan saved by /sed scan, shuffles it into simulated bags, runs the real sort code
-- against mocked game APIs, and checks the result.

local svPath, seed = arg[1], tonumber(arg[2] or "1")
local root = arg[0]:match("^(.*)/dev/") or "."
dofile(svPath)
local scan = SedimentDB.lastScan.rows
SedimentDB = {}
math.randomseed(seed)

-- Bags 0-4 are the normal bag slots; 5 is the reagent bag slot. By seed, slot 5 holds a big
-- reagent bag, a small one (reagents overflow), or an herb bag (the bug: Forever lets a profession
-- bag sit there). Every fourth seed, bag 3 is a mining bag instead of a normal bag.
local bag5 = ({ [0] = "reagent", "reagentSmall", "herb" })[seed % 3]
local bag3Mining = seed % 4 == 3
local HERB, MINING = 32, 1024
local BAG_SIZES = { [0] = 20, 16, 16, 16, 16, bag5 == "reagent" and 24 or 6 }
local bags = {}
for b = 0, 5 do bags[b] = {} end
local function IsSpecial(b) return b == 5 or (b == 3 and bag3Mining) end
-- What each bag accepts. "Simple Wood" is flagged as a crafting reagent but the reagent bag refuses
-- it, to exercise the case where Forever's rule differs from the flag.
local function Fits(b, t)
	if b == 5 then
		if bag5 == "herb" then return (t.family or 0) & HERB ~= 0 end
		return t.isCraftingReagent and not t.refuse
	end
	if b == 3 and bag3Mining then return (t.family or 0) & MINING ~= 0 end
	return true
end
local FAMILIES = { ["Light Leather"] = HERB, ["Rough Stone"] = MINING, ["Copper Bar"] = MINING }

-- Item templates from the scan.
local templates = {}
for _, r in ipairs(scan) do
	local stack = (r.classID == 7 or r.classID == 0 or r.classID == 12) and 20 or 1
	templates[#templates + 1] = {
		itemID = r.itemID, name = r.name, link = r.link, count = r.count, quality = r.quality,
		isBound = r.bound or r.isBound or false, classID = r.classID, subclassID = r.subclassID,
		equipLoc = r.equipLoc or "", isQuestItem = r.isQuestItem, maxStack = stack,
		isCraftingReagent = r.classID == 7, refuse = r.name == "Simple Wood", family = FAMILIES[r.name] or 0,
	}
end
-- Split some full stacks into partials so the merge step gets exercised.
local extra = {}
for _, t in ipairs(templates) do
	if t.maxStack > 1 and t.count >= 6 and math.random() < 0.5 then
		local part = {}
		for k, v in pairs(t) do part[k] = v end
		part.count = 3
		t.count = t.count - 3
		extra[#extra + 1] = part
	end
end
for _, e in ipairs(extra) do templates[#templates + 1] = e end
for _, t in ipairs(templates) do
	if t.classID == 2 or t.equipLoc == "INVTYPE_CLOAK" then t.set = "Tank" end
end

-- Scatter into random slots.
local free = {}
for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do free[#free + 1] = { b, s } end end end
local specialFree = {}
for b = 0, 5 do if IsSpecial(b) then
	specialFree[b] = {}
	for s = 1, BAG_SIZES[b] do table.insert(specialFree[b], s) end
end end
for _, t in ipairs(templates) do
	local placed = false
	for b, list in pairs(specialFree) do
		if not placed and Fits(b, t) and #list > 0 and math.random() < 0.3 then
			bags[b][table.remove(list, math.random(#list))] = t
			placed = true
		end
	end
	if not placed then
		local i = math.random(#free)
		local pos = table.remove(free, i)
		bags[pos[1]][pos[2]] = t
	end
end

-- Mocks ---------------------------------------------------------------------------------------
local now, cursor = 0, nil
-- Slots touched this round stay locked until the round is "confirmed" at the end of the tick,
-- like the real game waiting on the server. Touching a locked slot fails.
local locked = {}
local function Key(b, s) return b * 100 + s end
local tickFn
Enum = { BagIndex = { Backpack = 0, Bag_4 = 4, ReagentBag = 5 }, BagSlotFlags = { DisableAutoSort = 1 }, ItemQuality = { Poor = 0 } }
local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local byID = {}
for _, t in ipairs(templates) do byID[t.itemID] = t end
C_Container = {
	GetContainerNumSlots = function(b) return BAG_SIZES[b] or 0 end,
	GetContainerNumFreeSlots = function(b)
		local family = 0
		if b == 5 and bag5 == "herb" then family = HERB end
		if b == 3 and bag3Mining then family = MINING end
		return 0, family
	end,
	ContainerIDToInventoryID = function(b) return 100 + b end,
	GetBackpackAutosortDisabled = function() return false end,
	GetBagSlotFlag = function() return false end,
	GetContainerItemInfo = function(b, s)
		local t = bags[b][s]
		if not t then return nil end
		return { itemID = t.itemID, itemName = t.name, hyperlink = t.link, stackCount = t.count,
			quality = t.quality, isBound = t.isBound, isLocked = locked[Key(b, s)] or false }
	end,
	GetContainerItemEquipmentSetInfo = function(b, s)
		local t = bags[b][s]
		if t and t.set then return true, t.set end
		return false, ""
	end,
	GetContainerItemQuestInfo = function(b, s)
		local t = bags[b][s]
		return { isQuestItem = t and t.isQuestItem or false }
	end,
	PickupContainerItem = function(b, s)
		if locked[Key(b, s)] then return end -- fails; a held cursor stays held
		local t = bags[b][s]
		if not cursor then
			if t then cursor = { b = b, s = s, count = t.count } end
			return
		end
		local src = bags[cursor.b][cursor.s]
		if cursor.b == b and cursor.s == s then cursor = nil return end
		-- A special bag refuses anything that doesn't fit; the item stays on the cursor.
		if not Fits(b, src) then return end
		if t and not Fits(cursor.b, t) then return end
		if not t then
			if cursor.count == src.count then
				bags[b][s] = src; bags[cursor.b][cursor.s] = nil
			else
				local moved = Copy(src); moved.count = cursor.count
				src.count = src.count - cursor.count; bags[b][s] = moved
			end
		elseif t.link == src.link and t.isBound == src.isBound and t.maxStack > 1 then
			local n = math.min(cursor.count, t.maxStack - t.count)
			t.count = t.count + n; src.count = src.count - n
			if src.count == 0 then bags[cursor.b][cursor.s] = nil end
		else
			assert(cursor.count == src.count, "swap with a split stack on the cursor")
			bags[b][s], bags[cursor.b][cursor.s] = src, t
		end
		locked[Key(b, s)] = true; locked[Key(cursor.b, cursor.s)] = true
		cursor = nil
	end,
	SplitContainerItem = function(b, s, n)
		if locked[Key(b, s)] then return end
		cursor = { b = b, s = s, count = n }
	end,
}
C_Item = {
	GetItemInfoInstant = function(id)
		-- The bags themselves: container class 1, subclass 11 reagent, 2 herb, 6 mining, 0 plain bag.
		local bagSub = ({ [9005] = 11, [9002] = 2, [9006] = 6, [9000] = 0 })[id]
		if bagSub then return id, nil, nil, "INVTYPE_BAG", nil, 1, bagSub end
		local t = byID[id] return id, nil, nil, t.equipLoc, nil, t.classID, t.subclassID
	end,
	GetItemFamily = function(id) return byID[id].family or 0 end,
	GetItemClassInfo = function(c) return "class" .. c end,
	GetItemSubClassInfo = function(c, s) return "sub" .. c .. ":" .. s end,
	GetItemMaxStackSizeByID = function(id) return byID[id].maxStack end,
	GetItemInfo = function(id)
		local t = byID[id]
		return t.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, t.isCraftingReagent
	end,
}
GetCursorInfo = function() return cursor and "item" or nil end
GetInventoryItemID = function(_, inv)
	local b = inv - 100
	if b == 5 then return bag5 == "herb" and 9002 or 9005 end
	if b == 3 and bag3Mining then return 9006 end
	return 9000
end
bit = { band = function(a, b) return a & b end }
ClearCursor = function() cursor = nil end
InCombatLockdown = function() return false end
GetTime = function() return now end
-- A fake clock that advances 0.3ms per reading, so streaming spreads swaps over several frames.
local fakeMs = 0
debugprofilestop = function() fakeMs = fakeMs + 0.3 return fakeMs end
local frames = {}
CreateFrame = function()
	local f = { shown = true }
	function f:Show() if not self.shown and self.OnShow then self.shown = true self:OnShow() end self.shown = true end
	function f:Hide() self.shown = false end
	function f:SetScript(name, fn) self[name] = fn end
	frames[#frames + 1] = f
	return f
end
C_Timer = { NewTicker = function(_, fn) tickFn = fn return { Cancel = function() tickFn = nil end } end }
local messages = {}
local ns = { Print = function(m) messages[#messages + 1] = m end, OnSortStateChanged = function() end,
	OnSortFinished = function() end, OnSortProgress = function() end,
	AutoSort = { BagsOpen = function() return false end, Resume = function() end } }

MuteSoundFile, UnmuteSoundFile = function() end, function() end
C_Timer.After = function(_, fn) fn() end
local ORDER = os.getenv("SEDIMENT_ORDER") or "current"
for _, f in ipairs({ "Weights.lua", "Bags.lua", "Sound.lua", "Sort.lua" }) do
	local fh = assert(io.open(root .. "/" .. f))
	local src = fh:read("a")
	fh:close()
	if f == "Sort.lua" and ORDER ~= "current" then
		-- Experimental order: within a weight, identical items stay together and groups keep their
		-- current order (a group's position = its first member's slot). Light bands then append and
		-- heavy bands prepend, because new loot lands at the top of the gap.
		local a = src:find("local function Compare%(a, b%)")
		local b = select(2, src:find("\nend\n", a))
		local useSets = ORDER == "stableSets"
		local fill = ORDER == "stableFill"
		src = src:sub(1, a - 1) .. [[
local function Compare(a, b)
	if a.weight ~= b.weight then
		return a.weight < b.weight
	end
	]] .. (useSets and [[if a.equipmentSets ~= b.equipmentSets then
		return a.equipmentSets < b.equipmentSets
	end
	]] or "") .. [[if a.groupFirst ~= b.groupFirst then
		return a.groupFirst < b.groupFirst
	end
	if a.count ~= b.count then
		return a.count > b.count
	end
	return a.index < b.index
end
]] .. (fill and [[
-- stableFill: within each weight band, keep groups of identical items whole, and try moving one
-- whole group to the front or back of the band if that leaves fewer slots holding the wrong thing
-- than the current order does. Fills a hole by moving a group instead of shifting the whole band.
local function BestBands(list, start, slots)
	local out, i = {}, 1
	while i <= #list do
		local j = i
		while j + 1 <= #list and list[j + 1].weight == list[i].weight do j = j + 1 end
		local groups, g = {}, nil
		for k = i, j do
			local it = list[k]
			if not g or g.sig ~= it.sig then g = { sig = it.sig, items = {} } groups[#groups + 1] = g end
			table.insert(g.items, it)
		end
		local bandStart = start + (i - 1)
		local function Cost(order)
			local pos, cost = bandStart, 0
			for _, grp in ipairs(order) do
				for _ = 1, #grp.items do
					local sl = slots[pos]
					if not (sl.item and sl.item.sig == grp.sig) then cost = cost + 1 end
					pos = pos + 1
				end
			end
			return cost
		end
		local best, bestCost = groups, Cost(groups)
		for a = 1, #groups do
			for _, toFront in ipairs({ true, false }) do
				local order = {}
				if toFront then order[1] = groups[a] end
				for c = 1, #groups do if c ~= a then order[#order + 1] = groups[c] end end
				if not toFront then order[#order + 1] = groups[a] end
				local cost = Cost(order)
				if cost < bestCost then best, bestCost = order, cost end
			end
		end
		for _, grp in ipairs(best) do for _, it in ipairs(grp.items) do out[#out + 1] = it end end
		i = j + 1
	end
	return out
end
]] or "") .. src:sub(b + 1)
		src = src:gsub("table%.sort%(items, Compare%)", [[
local groupFirst = {}
	for _, it in ipairs(items) do
		if not groupFirst[it.sig] or it.index < groupFirst[it.sig] then groupFirst[it.sig] = it.index end
	end
	for _, it in ipairs(items) do it.groupFirst = groupFirst[it.sig] end
	table.sort(items, Compare)]], 1)
		if fill then
			src = src:gsub("\n\tlocal targets = {}\n", "\n\tfloaters = BestBands(floaters, 1, slots)\n\tsinkers = BestBands(sinkers, #slots - #sinkers + 1, slots)\n\tlocal targets = {}\n", 1)
		end
	end
	assert(load(src, "@" .. f))("Sediment", ns)
end
ns.Weights.Init()

local function Total()
	local n = {}
	for b = 0, 5 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
		if t then n[t.itemID] = (n[t.itemID] or 0) + t.count end end end
	return n
end

local function Run(quiet)
	local before = Total()
	ns.Sort.Start(quiet)
	local ticks = 0
	while tickFn do
		now = now + 0.05; ticks = ticks + 1
		tickFn()
		-- Frames drawn between ticks: run any OnUpdate handlers (the streaming sender).
		for _ = 1, 3 do
			for _, f in ipairs(frames) do
				if f.shown and f.OnUpdate then f:OnUpdate() end
			end
		end
		local streaming = false
		for _, f in ipairs(frames) do if f.shown and f.OnUpdate then streaming = true end end
		if not streaming then
			locked = {}
			ns.Sort.OnBagUpdateDelayed()
		end
		assert(ticks < 20000, "sort never finished")
	end
	local after = Total()
	for id, n in pairs(before) do assert(after[id] == n, "item count changed for " .. id) end
	return messages[#messages]
end

local function Check(show)

-- Print the layout and check it.
local sink = ns.Weights.SinkLine()
local seenGapOrSinker, seenSinker, last = false, false, -math.huge
local lastFloat = -math.huge
for b = 0, 4 do
	if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do
		local t = bags[b][s]
		if t then
			local item = ns.Bags.ReadSlot(b, s)
			local w = ns.Weights.Resolve(item)
			if show then print(("%d/%-2d w%-5s %-30s x%d"):format(b, s, tostring(w), t.name, t.count)) end
			if w < sink then
				assert(not seenGapOrSinker, "floater after a gap or sinker at " .. b .. "/" .. s)
				assert(w >= lastFloat, "floaters out of order at " .. b .. "/" .. s)
				lastFloat = w
			else
				seenGapOrSinker, seenSinker = true, true
				assert(w >= last, "sinkers out of order at " .. b .. "/" .. s)
				last = w
			end
		else
			if seenSinker then error("gap inside the sinker block at " .. b .. "/" .. s) end
			seenGapOrSinker = true
			if show then print(("%d/%-2d   ·"):format(b, s)) end
		end
	end end
end
-- Each special bag: only items it accepts, light-to-heavy with its own gap, and if it has an empty
-- slot, nothing it would take (and hasn't refused) is left in the normal bags.
for sb = 0, 5 do if IsSpecial(sb) then
	local rFloat, rSink, rSeenGap, rSeenSinker, hasEmpty = -math.huge, -math.huge, false, false, false
	for s = 1, BAG_SIZES[sb] do
		local t = bags[sb][s]
		if t then
			assert(Fits(sb, t), ("%s in special bag %d, which doesn't take it"):format(t.name, sb))
			local w = ns.Weights.Resolve(ns.Bags.ReadSlot(sb, s))
			if show then print(("S%d/%-2d w%-5s %-30s x%d"):format(sb, s, tostring(w), t.name, t.count)) end
			if w < sink then
				assert(not rSeenGap and w >= rFloat, "special bag floaters out of order at " .. sb .. "/" .. s)
				rFloat = w
			else
				rSeenGap, rSeenSinker = true, true
				assert(w >= rSink, "special bag sinkers out of order at " .. sb .. "/" .. s)
				rSink = w
			end
		else
			assert(not rSeenSinker, "gap inside a special bag's sinker block at " .. sb .. "/" .. s)
			rSeenGap, hasEmpty = true, true
			if show then print(("S%d/%-2d   ·"):format(sb, s)) end
		end
	end
	if hasEmpty then
		for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do local t = bags[b][s]
			assert(not (t and Fits(sb, t)), ("%s left in the normal bags with room in special bag %d"):format(t and t.name or "", sb))
		end end end
	end
end end
-- Identical stacks are never split: within each bag zone, every item signature forms one unbroken
-- run of slots.
local function CheckRuns(bagList)
	local seen, prev = {}, nil
	for _, b in ipairs(bagList) do
		for s = 1, BAG_SIZES[b] do
			local t = bags[b][s]
			local sig = t and (t.link .. tostring(t.isBound) .. (t.set or "")) or nil
			if sig and sig ~= prev then
				assert(not seen[sig], ("identical stacks split: %s at %d/%d"):format(t.name, b, s))
				seen[sig] = true
			end
			prev = sig
		end
	end
end
local mainBags = {}
for b = 0, 4 do if not IsSpecial(b) then mainBags[#mainBags + 1] = b end end
CheckRuns(mainBags)
for b = 0, 5 do if IsSpecial(b) then CheckRuns({ b }) end end
-- At most one partial stack per item.
local partial = {}
for b = 0, 5 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
	if t and t.maxStack > 1 and t.count < t.maxStack then
		local k = t.link .. tostring(t.isBound)
		assert(not partial[k], "two partial stacks of " .. t.name)
		partial[k] = true
	end end end
end

print("first sort: " .. Run())
Check(arg[3] == "show")
print("second sort: " .. Run())

if arg[3] == "bench" then
	-- Realistic events from a sorted bag; each followed by an auto-sort. Moves per event averaged.
	local nextID = 900000
	local function MainSlots()
		local list = {}
		for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do list[#list + 1] = { b, s } end end end
		return list
	end
	local function FirstFree()
		for _, p in ipairs(MainSlots()) do if not bags[p[1]][p[2]] then return p end end
	end
	local function RandomItemSlot(filter)
		local found = {}
		for _, p in ipairs(MainSlots()) do
			local t = bags[p[1]][p[2]]
			if t and (not filter or filter(t)) then found[#found + 1] = p end
		end
		return #found > 0 and found[math.random(#found)] or nil
	end
	local function Clone(t, fresh)
		local c = {}
		for k, v in pairs(t) do c[k] = v end
		if fresh then
			nextID = nextID + 1
			c.itemID, c.link, c.name = nextID, "item:" .. nextID, t.name .. " (new)"
			byID[nextID] = c
		end
		c.count = 1
		return c
	end
	local function Moves() Run(true) return ns.Sort.lastMoves end
	local results = {}
	local function Record(name, m)
		local r = results[name] or { n = 0, total = 0 }
		r.n, r.total = r.n + 1, r.total + m
		results[name] = r
	end
	local isGear = function(t) return t.classID == 2 or t.classID == 4 end
	for trial = 1, 60 do
		-- 1. Loot and use: one item used up, one new item arrives (half match something already here).
		local used = RandomItemSlot()
		if used then bags[used[1]][used[2]] = nil end
		local pick = templates[math.random(#templates)]
		local p = FirstFree()
		if p then bags[p[1]][p[2]] = Clone(pick, math.random() < 0.5) end
		Record("loot + use", Moves())
		-- 2. Set swap: four gear pieces leave, four set pieces arrive.
		for _ = 1, 4 do
			local g = RandomItemSlot(isGear)
			if g then bags[g[1]][g[2]] = nil end
		end
		for _ = 1, 4 do
			local gearTemplates = {}
			for _, t in ipairs(templates) do if isGear(t) then gearTemplates[#gearTemplates + 1] = t end end
			local c = Clone(gearTemplates[math.random(#gearTemplates)], true)
			c.set = math.random() < 0.5 and "Tank" or "Healer"
			local f = FirstFree()
			if f then bags[f[1]][f[2]] = c end
		end
		Record("set swap", Moves())
		-- 3. Weight edit: nudge one subclass's weight, sort, put it back, sort.
		local any = RandomItemSlot()
		if any then
			local item = ns.Bags.ReadSlot(any[1], any[2])
			local w = SedimentDB.weights.subclasses
			local old = w[item.subKey]
			w[item.subKey] = ns.Weights.Resolve(item) + (math.random() < 0.5 and -3 or 3)
			Record("weight edit", Moves())
			w[item.subKey] = old
			Record("weight edit", Moves())
		end
		Check(false)
	end
	for _, name in ipairs({ "loot + use", "set swap", "weight edit" }) do
		local r = results[name]
		print(("BENCH %s %-12s %.2f moves/event over %d events"):format(ORDER, name, r.total / r.n, r.n))
	end
	os.exit(0)
end

-- Scenario: the user's "item 99 goes to the top": the last floater suddenly weighs less than
-- everything, so every floater above it shifts down by one.
local lastFloater
for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do local t = bags[b][s]
	if t then
		local item = ns.Bags.ReadSlot(b, s)
		if ns.Weights.Resolve(item) < ns.Weights.SinkLine() then lastFloater = item end
	end end end end
SedimentDB.weights.items[lastFloater.itemID] = -1
print("to the top (" .. lastFloater.name .. "): " .. Run())
Check(false)
-- And back down again.
SedimentDB.weights.items[lastFloater.itemID] = 1000
print("to the bottom: " .. Run())
Check(false)
-- Auto-sort path: streamed and quiet. Clearing the weight sends the bracers back down.
SedimentDB.weights.items[lastFloater.itemID] = nil
SedimentDB.streamBudgetMs = 1
Run(true)
Check(false)
print(("streamed: %d moves, %d rounds, over %d frames"):format(ns.Sort.lastMoves, ns.Sort.lastRounds, ns.Sort.lastFrames))
print("OK")
