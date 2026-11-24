-- Offline simulation of the Sediment sort. Not loaded by the game.
-- Usage: lua dev/sim.lua <path to WTF SavedVariables/SedimentSort.lua> [seed] [show|bench]
-- SEDIMENT_AUTO=full (environment) makes auto-sorts use the full order instead of the default partial
-- one, for comparison. "bench"
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
simBagsOpen = false
local ns = { Print = function(m) messages[#messages + 1] = m end, OnSortStateChanged = function() end,
	OnSortFinished = function() end, OnSortProgress = function() end,
	OnBenchRun = function() end,
	OnSortPaused = function() simPauses = (simPauses or 0) + 1 end,
	AutoSort = { BagsOpen = function() return simBagsOpen end, QuietLongEnough = function() return true end,
		Resume = function() end } }

MuteSoundFile, UnmuteSoundFile = function() end, function() end
C_Timer.After = function(_, fn) fn() end
-- SEDIMENT_AUTO=full makes auto-sorts use the full order (as the test bench's toggle does), to
-- compare against the default partial order.
local ORDER = os.getenv("SEDIMENT_AUTO") or "partial"
-- SEDIMENT_MEASURE=1: after every placement plan, compare Sediment's swap count with the proven
-- minimum for the same target (dev/min_swaps.lua). Results in Measured, printed by bench mode.
local MEASURE = os.getenv("SEDIMENT_MEASURE") == "1"
local MinSwaps = MEASURE and dofile(root .. "/dev/min_swaps.lua").MinSwaps
Measured = { plans = 0, ours = 0, best = 0, worse = 0, unproven = 0, oursUnproven = 0, worst = 0 }
for _, f in ipairs({ "Weights.lua", "Bags.lua", "Sound.lua", "Sort.lua" }) do
	local fh = assert(io.open(root .. "/" .. f))
	local src = fh:read("a")
	fh:close()
	if MEASURE and f == "Sort.lua" then
		src = src:gsub("(\t\twant%[p%] = targets%[p%] or EMPTY\n\tend\n)", "%1\tlocal cur0 = {} for i = 1, n do cur0[i] = cur[i] end\n", 1)
		src = src:gsub("(\n\tlocal rounds = {}\n)", "\n\tif SimMeasure then SimMeasure(cur0, want, #round1 + #round2, slots) end%1", 1)
		assert(src:find("SimMeasure%(cur0"), "measurement hook not inserted")
	end
	assert(load(src, "@" .. f))("Sediment", ns)
end
if MEASURE then
	-- Target-choice bracket (bench events only, tagged with SimEvent): for each placement plan,
	-- "ours" = proven minimum swaps to the partial order's chosen layout; "found" = best layout a
	-- local search finds (move whole groups of identical items within each weight band, keep any
	-- change that lowers the proven count); "floor" = contents outside the region that may hold them
	-- must move, and one swap moves at most two, so no valid layout needs fewer.
	Bracket = {}
	local function GroupsOf(want, from, to)
		local groups, g = {}, nil
		for p = from, to do
			if not g or g.sig ~= want[p] then g = { sig = want[p], size = 0 } groups[#groups + 1] = g end
			g.size = g.size + 1
		end
		return groups
	end
	local function Fill(want, from, groups)
		local p = from
		for _, g in ipairs(groups) do for _ = 1, g.size do want[p] = g.sig p = p + 1 end end
	end
	function SimMeasure(cur, want, ours, slots)
		if ours == 0 then return end
		local best = MinSwaps(cur, want)
		Measured.plans = Measured.plans + 1
		if not best then
			Measured.unproven = Measured.unproven + 1
			Measured.oursUnproven = Measured.oursUnproven + ours
			return
		end
		assert(ours >= best, "Sediment beat the proven minimum: the solver is wrong")
		Measured.ours, Measured.best = Measured.ours + ours, Measured.best + best
		if ours > best then
			Measured.worse = Measured.worse + 1
			Measured.worst = math.max(Measured.worst, ours - best)
		end
		if not SimEvent then return end
		-- Band regions in the chosen layout: runs of equal weight; empties are the gap.
		local weightOf = {}
		for _, sl in ipairs(slots) do if sl.item then weightOf[sl.item.sig] = sl.item.weight end end
		local function Region(sig) return sig == "" and "gap" or weightOf[sig] end
		local n = #want
		local bands, p = {}, 1
		while p <= n do
			local w = Region(want[p])
			local q = p
			while q + 1 <= n and Region(want[q + 1]) == w do q = q + 1 end
			bands[#bands + 1] = { from = p, to = q, weight = w }
			p = q + 1
		end
		local regionAt = {}
		for _, b in ipairs(bands) do for k = b.from, b.to do regionAt[k] = b.weight end end
		local mustMove = 0
		for k = 1, n do if regionAt[k] ~= Region(cur[k]) then mustMove = mustMove + 1 end end
		local floor = math.ceil(mustMove / 2)
		local cand = {}
		for k = 1, n do cand[k] = want[k] end
		local found, improved, passes = best, true, 0
		while improved and passes < 20 do
			improved, passes = false, passes + 1
			for _, b in ipairs(bands) do
				if b.weight ~= "gap" then
					local groups = GroupsOf(cand, b.from, b.to)
					for i = 1, #groups do
						for j = 1, #groups do
							if i ~= j then
								local order = {}
								for k = 1, #groups do order[k] = groups[k] end
								table.insert(order, j, table.remove(order, i))
								Fill(cand, b.from, order)
								local c = MinSwaps(cur, cand)
								if c and c < found then
									found, improved, groups = c, true, order
								else
									Fill(cand, b.from, groups)
								end
							end
						end
					end
				end
			end
		end
		local e = Bracket[SimEvent] or { plans = 0, ours = 0, found = 0, floor = 0, better = 0 }
		e.plans, e.ours, e.found, e.floor = e.plans + 1, e.ours + best, e.found + found, e.floor + floor
		if found < best then e.better = e.better + 1 end
		Bracket[SimEvent] = e
	end
end
ns.Weights.Init()
SedimentDB.autoOrder = ORDER

local function Total()
	local n = {}
	for b = 0, 5 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
		if t then n[t.itemID] = (n[t.itemID] or 0) + t.count end end end
	return n
end

local function Run(quiet, interrupt, starter)
	local before = Total()
	if starter then starter() else ns.Sort.Start(quiet) end
	local ticks = 0
	while tickFn do
		now = now + 0.05; ticks = ticks + 1
		-- interrupt: the user's pattern, bags opened and closed again on alternate ticks.
		if interrupt then simBagsOpen = ticks % 2 == 0 end
		tickFn()
		-- Frames drawn between ticks: run any OnUpdate handlers (the streaming sender).
		for _ = 1, 3 do
			for _, f in ipairs(frames) do
				if f.shown and f.OnUpdate then f:OnUpdate() end
			end
		end
		-- Only the sort's sender streams swaps; other frames (frame timing) always update.
		local streaming = ns.Sort.sender.shown
		if not streaming then
			locked = {}
			ns.Sort.OnBagUpdateDelayed()
		end
		assert(ticks < 20000, "sort never finished")
	end
	simBagsOpen = false
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
-- Within each run of identical stacks, a partial stack comes after the full ones.
local function CheckPartialLast(bagList)
	local prevSig, sawPartial = nil, false
	for _, b in ipairs(bagList) do
		for s = 1, BAG_SIZES[b] do
			local t = bags[b][s]
			local sig = t and (t.link .. tostring(t.isBound) .. (t.set or "")) or nil
			if sig ~= prevSig then sawPartial = false end
			if t and t.maxStack > 1 then
				if t.count < t.maxStack then
					sawPartial = true
				else
					assert(not sawPartial, ("partial stack before a full one: %s at %d/%d"):format(t.name, b, s))
				end
			end
			prevSig = sig
		end
	end
end
CheckPartialLast(mainBags)
for b = 0, 5 do if IsSpecial(b) then CheckPartialLast({ b }) end end
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
-- Auto-sort must be satisfied by its own result: right after an auto-sort, another auto-sort
-- (triggered by any later bag or quest-log event) must find nothing to move. Messed up first so the
-- auto-sort has real work to do.
do
	local function Mess()
		local filled, empty = {}, {}
		for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do
			if bags[b][s] then filled[#filled + 1] = { b, s } else empty[#empty + 1] = { b, s } end
		end end end
		for _ = 1, 4 do
			if #filled == 0 or #empty == 0 then break end
			local f = table.remove(filled, math.random(#filled))
			local e = table.remove(empty, 1)
			bags[e[1]][e[2]], bags[f[1]][f[2]] = bags[f[1]][f[2]], nil
		end
	end
	for round = 1, 15 do
		Mess()
		Run(true)
		Run(true)
		assert(ns.Sort.lastMoves == 0, ("auto-sort moved %d more after its own result (round %d)"):format(ns.Sort.lastMoves, round))
	end
	print("auto-sort settles: 15 rounds, a second auto-sort never moved anything")
end

-- Scramble test: shuffle the normal bags into a seeded target (as the test bench does), check every
-- slot got its target, then let auto-sort clean up.
do
	local mainSlots = {}
	for _, sl in ipairs(ns.Bags.Read()) do
		if sl.zone == "main" then mainSlots[#mainSlots + 1] = sl end
	end
	local layout = {}
	for i, sl in ipairs(mainSlots) do layout[i] = sl.item and sl.item.sig or false end
	for i = #layout, 2, -1 do
		local j = math.random(i)
		layout[i], layout[j] = layout[j], layout[i]
	end
	local targets = {}
	for i = 1, #layout do targets[i] = layout[i] or nil end
	local msg = Run(false, false, function() ns.Sort.Scramble(targets, #layout) end)
	for i, sl in ipairs(ns.Bags.Read()) do
		if sl.zone ~= "main" then break end
		local got = sl.item and sl.item.sig or nil
		assert(got == targets[i], ("scramble missed slot %d"):format(i))
	end
	print("scramble test: " .. msg)
	print("cleanup after scramble: " .. Run(true))
	Check(false)
	local run = SedimentDB.benchHistory and SedimentDB.benchHistory[1]
	assert(run and run.kind == "auto", "bench history not recorded")
end

-- Pause test: the same messy start sorted twice by auto-sort, once uninterrupted and once with the
-- bags opened and closed on alternate ticks. Keeping the plan across pauses means the same moves.
do
	local function Snapshot()
		local copy = {}
		for b = 0, 5 do copy[b] = {} for s = 1, BAG_SIZES[b] do copy[b][s] = bags[b][s] end end
		return copy
	end
	local function Restore(copy)
		for b = 0, 5 do for s = 1, BAG_SIZES[b] do bags[b][s] = copy[b][s] end end
	end
	-- Make a long chain like the cloak case: the last light item suddenly weighs the least.
	local last
	for b = 0, 4 do if not IsSpecial(b) then for s = 1, BAG_SIZES[b] do local t = bags[b][s]
		if t then
			local it = ns.Bags.ReadSlot(b, s)
			if ns.Weights.Resolve(it) < ns.Weights.SinkLine() then last = it end
		end end end end
	SedimentDB.weights.items[last.itemID] = -2
	local start = Snapshot()
	Run(true)
	local plain = ns.Sort.lastMovesByKind.place or 0
	Check(false)
	Restore(start)
	Run(true, true)
	local interrupted = ns.Sort.lastMovesByKind.place or 0
	Check(false)
	-- Placement is what a pause could break (the old crawl). Which of two same-item stacks ends where
	-- can differ, so the restack phase may differ by a move; Check above verifies both end states.
	print(("pause test: placement moves uninterrupted %d, interrupted every other tick %d (%d pauses)"):format(plain, interrupted, simPauses or 0))
	assert(interrupted == plain, "interruptions changed the number of placement moves")
	-- "Finish now" mode: opening the bags mid-sort sends the rest at once, in auto-sort's own order,
	-- so the placement moves match the uninterrupted run and it never pauses.
	Restore(start)
	SedimentDB.openBags = "finish"
	local pausesBefore = simPauses or 0
	Run(true, true)
	local finished = ns.Sort.lastMovesByKind.place or 0
	Check(false)
	SedimentDB.openBags = nil
	print(("finish-now test: placement moves %d (uninterrupted %d), pauses %d"):format(finished, plain, (simPauses or 0) - pausesBefore))
	assert(finished == plain, "finish-now changed the number of placement moves")
	assert((simPauses or 0) == pausesBefore, "finish-now paused")
	SedimentDB.weights.items[last.itemID] = nil
	Run(true)
end

if arg[3] == "bench" then
	-- Realistic events from a sorted bag; each followed by an auto-sort. Moves per event averaged.
	Measured = { plans = 0, ours = 0, best = 0, worse = 0, unproven = 0, oursUnproven = 0, worst = 0 } -- everyday events only
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
		SimEvent = nil
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
		SimEvent = "loot + use" Record("loot + use", Moves())
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
		SimEvent = "set swap" Record("set swap", Moves())
		-- 3. Weight edit: nudge one subclass's weight, sort, put it back, sort.
		local any = RandomItemSlot()
		if any then
			local item = ns.Bags.ReadSlot(any[1], any[2])
			local w = SedimentDB.weights.subclasses
			local old = w[item.subKey]
			w[item.subKey] = ns.Weights.Resolve(item) + (math.random() < 0.5 and -3 or 3)
			SimEvent = "weight edit" Record("weight edit", Moves())
			w[item.subKey] = old
			SimEvent = "weight edit" Record("weight edit", Moves())
		end
		-- 4. Multi-loot: three items arrive at once (half match something here), then later three
		-- random items are used up. Bands shift by up to 3, where group rotations should matter.
		for _ = 1, 3 do
			local f = FirstFree()
			if f then bags[f[1]][f[2]] = Clone(templates[math.random(#templates)], math.random() < 0.5) end
		end
		SimEvent = "loot 3" Record("loot 3", Moves())
		for _ = 1, 3 do
			local u = RandomItemSlot()
			if u then bags[u[1]][u[2]] = nil end
		end
		SimEvent = "use 3" Record("use 3", Moves())
		Check(false)
	end
	if MEASURE then
		for name, e in pairs(Bracket) do
			print(("BRACKET\t%s\t%d\t%d\t%d\t%d\t%d"):format(name, e.plans, e.ours, e.found, e.floor, e.better))
		end
		local m = Measured
		print(("MEASURE plans %d ours %d best %d worse %d worst %d unproven %d oursUnproven %d"):format(
			m.plans, m.ours, m.best, m.worse, m.worst, m.unproven, m.oursUnproven))
	end
	for _, name in ipairs({ "loot + use", "set swap", "weight edit", "loot 3", "use 3" }) do
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
