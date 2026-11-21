-- Sort: the gravity sort. Light items (weight below the sink line) pack from the top, heavy items
-- pack from the bottom, free space stays in the middle.
--
-- It works in rounds. Each round sends every move that can go out at once (no slot used twice) and
-- waits for the game to confirm them. Phases: merge partial stacks, place items (always two rounds,
-- see PlanPlacement), put partial stacks last. Every round re-reads the bags and checks them against
-- the plan, so looting or the user moving something mid-sort just triggers a fresh plan.

local _, ns = ...
local Sort = {}
ns.Sort = Sort

local TICK = 0.05         -- seconds between checks
local UPDATE_TIMEOUT = 2  -- seconds to wait for the game to confirm a move
local CURSOR_TIMEOUT = 3  -- seconds to wait for the user to drop something from the cursor
local MAX_MOVES = 1000
local MAX_REPEATS = 3     -- same batch this many times in a row = stuck

local ticker
local moves, rounds, startedAt, lastKey, repeats
local waitingForUpdate, waitStarted, cursorSince
local plan -- { rounds, round, n }: placement rounds still to send
local quiet    -- auto-sort: no chat on success, and stream the swaps
local cpuMs = 0 -- our own Lua time during the current sort
local sendMs, maxSwapMs = 0, 0 -- of which: making the swaps (including handlers the game runs inside them)
local sending  -- { batch, keys, i }: a round being streamed out over several frames

local function Print(msg)
	ns.Print(msg)
end

-- Planning ------------------------------------------------------------------------------------

-- Order for items: lighter first, then by equipment set (so each set stays together), then by
-- category, then by item, then bigger stacks first.
local function Compare(a, b)
	if a.weight ~= b.weight then
		return a.weight < b.weight
	end
	if a.equipmentSets ~= b.equipmentSets then
		return a.equipmentSets < b.equipmentSets
	end
	if a.classID ~= b.classID then
		return a.classID < b.classID
	end
	if a.subclassID ~= b.subclassID then
		return a.subclassID < b.subclassID
	end
	if a.itemID ~= b.itemID then
		return a.itemID < b.itemID
	end
	if a.count ~= b.count then
		return a.count > b.count
	end
	if a.sig ~= b.sig then
		return a.sig < b.sig
	end
	return a.index < b.index
end

-- All stack merges for this round. For each item with two or more partial stacks, pair them up
-- from both ends (first <- last, second <- second-to-last, ...), so no slot is used twice.
local function MergeMoves(slots)
	local partials, order = {}, {}
	for _, s in ipairs(slots) do
		local item = s.item
		if item and item.maxStack > 1 and item.count < item.maxStack then
			local list = partials[item.sig]
			if not list then
				list = {}
				partials[item.sig] = list
				order[#order + 1] = item.sig
			end
			list[#list + 1] = s
		end
	end
	local batch = {}
	for _, sig in ipairs(order) do
		local list = partials[sig]
		local i, j = 1, #list
		while i < j do
			local dst, src = list[i], list[j]
			local amount = math.min(src.item.count, dst.item.maxStack - dst.item.count)
			batch[#batch + 1] = { kind = "merge", src = src, dst = dst, amount = amount }
			i, j = i + 1, j - 1
		end
	end
	return batch
end

-- The target signature for every position: floaters from the top, sinkers at the bottom.
local function PlanTargets(slots)
	local items = {}
	for index, s in ipairs(slots) do
		local item = s.item
		if item then
			item.weight = ns.Weights.Resolve(item)
			item.index = index
			items[#items + 1] = item
		end
	end
	table.sort(items, Compare)

	local sinkLine = ns.Weights.SinkLine()
	local floaters, sinkers = {}, {}
	for _, item in ipairs(items) do
		if item.weight < sinkLine then
			floaters[#floaters + 1] = item
		else
			sinkers[#sinkers + 1] = item
		end
	end

	local targets = {}
	for i, item in ipairs(floaters) do
		targets[i] = item.sig
	end
	-- Sinkers fill the bottom, ending with the heaviest in the very last slot.
	local first = #slots - #sinkers
	for i, item in ipairs(sinkers) do
		targets[first + i] = item.sig
	end
	return targets
end

-- Placement plan. Work out where every slot's content must go (empty counts as content), which
-- splits the rearrangement into chains: A goes to B's slot, B to C's, ..., the last back to A's.
-- Shifting a chain along by one is the same as reversing it twice: reverse the whole chain, then
-- reverse all of it except the first slot. Each reversal is swaps from the ends inward, and no two
-- of them share a slot. So every chain, however long, is done in two rounds.
-- Returns a list of rounds, each a list of swaps with the slot contents they expect to find.
local EMPTY = ""

local function SigAt(s)
	return s.item and s.item.sig or EMPTY
end

local function PlanPlacement(slots, targets)
	local n = #slots
	local cur, want = {}, {}
	for p = 1, n do
		cur[p] = SigAt(slots[p])
		want[p] = targets[p] or EMPTY
	end

	-- dest[p] = where the content of p goes. Anything already right stays put; the rest is
	-- matched in slot order to positions that want that content.
	local dest, open, taken = {}, {}, {}
	for p = 1, n do
		if cur[p] == want[p] then
			dest[p] = p
		else
			local list = open[want[p]]
			if not list then
				list = {}
				open[want[p]] = list
			end
			list[#list + 1] = p
		end
	end
	-- First, direct pairs: p holds what q wants and q holds what p wants. One swap fixes both,
	-- and every pair found keeps the chains short, which means fewer moves.
	local claimed = {}
	for p = 1, n do
		if not dest[p] then
			for _, q in ipairs(open[cur[p]]) do
				if not claimed[q] and not dest[q] and q ~= p and cur[q] == want[p] then
					dest[p], dest[q] = q, p
					claimed[q], claimed[p] = true, true
					break
				end
			end
		end
	end
	-- Then everything else, in slot order.
	for p = 1, n do
		if not dest[p] then
			local list = open[cur[p]]
			local i = taken[cur[p]] or 0
			repeat
				i = i + 1
			until not claimed[list[i]]
			taken[cur[p]] = i
			claimed[list[i]] = true
			dest[p] = list[i]
		end
	end

	local round1, round2 = {}, {}
	local function AddSwap(round, a, b)
		if cur[a] == cur[b] then
			return -- same content (or both empty): nothing to do
		end
		round[#round + 1] = { a = a, b = b, sigA = cur[a], sigB = cur[b] }
		cur[a], cur[b] = cur[b], cur[a]
	end

	local chains, seen = {}, {}
	for p = 1, n do
		if not seen[p] and dest[p] ~= p then
			local chain, q = {}, p
			while not seen[q] do
				seen[q] = true
				chain[#chain + 1] = q
				q = dest[q]
			end
			chains[#chains + 1] = chain
		end
	end
	-- Round 1 swaps are all applied to cur before round 2 is planned, so round 2's expected
	-- contents are what round 1 leaves behind.
	for _, chain in ipairs(chains) do
		local k = #chain
		for i = 1, math.floor(k / 2) do
			AddSwap(round1, chain[i], chain[k + 1 - i])
		end
	end
	for _, chain in ipairs(chains) do
		local k = #chain
		for i = 1, math.floor((k - 1) / 2) do
			AddSwap(round2, chain[1 + i], chain[k + 1 - i])
		end
	end

	local rounds = {}
	if #round1 > 0 then
		rounds[#rounds + 1] = round1
	end
	if #round2 > 0 then
		rounds[#rounds + 1] = round2
	end
	return rounds
end

-- Placement treats stacks of the same item as interchangeable, so a partial stack can end up
-- in the middle of its group. Fix: drop a later, bigger stack onto it. The game tops the partial
-- up to full and leaves the remainder behind, so in effect the two counts swap.
local function RestackMoves(slots)
	local batch, used = {}, {}
	for p, s in ipairs(slots) do
		local item = s.item
		if not used[p] and item and item.maxStack > 1 and item.count < item.maxStack then
			-- Use the last bigger stack in the group, so the partial jumps straight to the end.
			local best
			local q = p + 1
			while slots[q] and slots[q].item and slots[q].item.sig == item.sig do
				if not used[q] and slots[q].item.count > item.count then
					best = q
				end
				q = q + 1
			end
			if best then
				batch[#batch + 1] = { kind = "restack", src = slots[best], dst = s }
				used[p], used[best] = true, true
			end
		end
	end
	return batch
end

-- Executing ----------------------------------------------------------------------------------

-- success = the sort finished normally. A quiet sort (auto-sort) only prints when something
-- went wrong.
local function Stop(msg, success)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	waitingForUpdate = false
	plan = nil
	sending = nil
	if Sort.sender then
		Sort.sender:Hide()
	end
	if GetCursorInfo() then
		ClearCursor()
	end
	ns.Sound.UnmuteItemSounds()
	Sort.lastCpuMs, Sort.lastMoves, Sort.lastRounds = cpuMs, moves, rounds
	Sort.lastSendMs, Sort.lastMaxSwapMs = sendMs, maxSwapMs
	if msg and not (success and quiet) then
		Print(msg)
	end
	ns.OnSortStateChanged()
	ns.OnSortFinished()
end

-- Moving items is forbidden in combat (the game blocks it with ADDON_ACTION_BLOCKED), so every
-- path that sends a swap checks first. An auto-sort picks up again by itself after combat; a button
-- sort asks the user to press again.
local function CombatStop()
	if quiet then
		Stop("auto-sort paused for combat; it finishes afterwards.")
		ns.AutoSort.Resume()
	else
		Stop("stopped: entered combat. Press sort again afterwards.")
	end
end

function Sort.OnCombatStart()
	if ticker then
		CombatStop()
	end
end

local ExecuteSwap

-- One swap, timed. The time includes every event handler the game runs inside the pick-up and
-- drop calls (Blizzard's UI and other addons), since those run before the call returns.
local function Execute(move)
	local t = debugprofilestop()
	ExecuteSwap(move)
	local spent = debugprofilestop() - t
	sendMs = sendMs + spent
	if spent > maxSwapMs then
		maxSwapMs = spent
	end
end

function ExecuteSwap(move)
	local src, dst = move.src, move.dst
	if move.kind == "merge" and move.amount < src.item.count then
		C_Container.SplitContainerItem(src.bag, src.slot, move.amount)
	else
		C_Container.PickupContainerItem(src.bag, src.slot)
	end
	C_Container.PickupContainerItem(dst.bag, dst.slot)
end

-- The next round of the placement plan, checked against the bags as they are now. If anything
-- doesn't match (the user moved something, loot arrived), drop the plan; the caller re-plans.
-- A round goes out whole: no slot appears twice in it, so it can never be more than half the slots.
local function TakePlanned(slots)
	local round = plan.rounds[plan.round]
	if not round or #slots ~= plan.n then
		plan = nil
		return nil
	end
	local batch = {}
	for _, swap in ipairs(round) do
		local sa, sb = slots[swap.a], slots[swap.b]
		if SigAt(sa) ~= swap.sigA or SigAt(sb) ~= swap.sigB then
			plan = nil
			return nil
		end
		-- The game moves from a slot with an item; if one side is empty, start from the other.
		if sa.item then
			batch[#batch + 1] = { kind = "place", src = sa, dst = sb }
		else
			batch[#batch + 1] = { kind = "place", src = sb, dst = sa }
		end
	end
	plan.round = plan.round + 1
	if not plan.rounds[plan.round] then
		plan = nil
	end
	return batch
end

Sort.lastCpuMs, Sort.lastMoves, Sort.lastRounds = 0, 0, 0
Sort.lastSendMs, Sort.lastMaxSwapMs = 0, 0

local StepWork

local function Step()
	local t = debugprofilestop()
	StepWork()
	cpuMs = cpuMs + (debugprofilestop() - t)
end

function StepWork()
	if sending then
		return -- a round is still streaming out
	end
	if InCombatLockdown() then
		CombatStop()
		return
	end

	if waitingForUpdate then
		if GetTime() - waitStarted < UPDATE_TIMEOUT then
			return
		end
		waitingForUpdate = false -- no confirmation; carry on and let the re-read sort it out
	end

	if GetCursorInfo() then
		cursorSince = cursorSince or GetTime()
		if GetTime() - cursorSince > CURSOR_TIMEOUT then
			cursorSince = nil
			Stop("stopped: something is on the cursor.")
		end
		return
	end
	cursorSince = nil

	local slots, anyLocked = ns.Bags.Read()
	if anyLocked then
		return
	end

	-- One phase per round: merges change counts, which placement depends on.
	local batch = plan and TakePlanned(slots)
	if not batch then
		batch = MergeMoves(slots)
		if #batch == 0 then
			local placement = PlanPlacement(slots, PlanTargets(slots))
			if #placement > 0 then
				plan = { rounds = placement, round = 1, n = #slots }
				batch = TakePlanned(slots) or {}
			end
		end
		if #batch == 0 then
			batch = RestackMoves(slots)
		end
	end
	if #batch == 0 then
		Stop(moves == 0 and ("already sorted (%.1fms)."):format(cpuMs)
			or ("sorted: %d moves in %d rounds, %.1fs (our code: %.1fms)."):format(
				moves, rounds, GetTime() - startedAt, cpuMs), true)
		return
	end

	local keys = {}
	for i, move in ipairs(batch) do
		keys[i] = ("%s %d/%d>%d/%d"):format(move.kind, move.src.bag, move.src.slot, move.dst.bag, move.dst.slot)
	end
	local key = table.concat(keys, ", ")
	repeats = key == lastKey and repeats + 1 or 1
	lastKey = key
	if repeats > MAX_REPEATS then
		Stop("stopped: stuck repeating " .. keys[1] .. ". Bags left as they are.")
		return
	end
	moves = moves + #batch
	rounds = rounds + 1
	if moves > MAX_MOVES then
		Stop("stopped: too many moves.")
		return
	end

	if quiet and not ns.AutoSort.BagsOpen() then
		-- Auto-sort with the bags closed: stream the round out (see Sender below). With the bags
		-- open the user is watching, so send it at once like a button sort.
		sending = { batch = batch, keys = keys, i = 1 }
		Sort.sender:Show()
		return
	end
	-- Button sort: the whole round in one go.
	for i, move in ipairs(batch) do
		if InCombatLockdown() then
			CombatStop()
			return
		end
		Execute(move)
		if GetCursorInfo() then
			Stop("stopped: a move didn't go through (" .. keys[i] .. ").")
			return
		end
	end
	waitingForUpdate = true
	waitStarted = GetTime()
end

-- Streaming. Each swap makes the game fire events right away, and Blizzard's UI and other addons
-- run their handlers inside that same frame: measured in game at about 5ms per swap, nearly all of
-- it outside Sediment. One swap can't be made cheaper, so auto-sort controls how often a swap lands
-- on a frame instead. The budget is an average: every frame adds BudgetMs of allowance, every swap
-- spends what it actually cost (handlers included), and a swap only goes out while the allowance
-- isn't overdrawn. With 5ms swaps and the 0.1ms default that's one swap every ~50 frames. We don't wait
-- for the server between frames, so the round is still one round to the server.
local DEFAULT_BUDGET_MS = 0.1 -- picked in game 2026-11-20: smooth at 144 FPS
local MAX_SAVED_MS = 5 -- allowance can't pile up beyond this, so a quiet spell can't buy a burst

function Sort.BudgetMs()
	return SedimentDB.streamBudgetMs or DEFAULT_BUDGET_MS
end

function Sort.SetBudget(ms)
	if ms == nil then
		Print(("auto-sort spends on average up to %sms per frame on swaps (default %sms). /sed budget <ms> to change.")
			:format(Sort.BudgetMs(), DEFAULT_BUDGET_MS))
		return
	end
	SedimentDB.streamBudgetMs = math.max(0.1, math.min(50, ms))
	Print(("auto-sort now spends on average up to %sms per frame on swaps."):format(SedimentDB.streamBudgetMs))
end

local allowance = 0

Sort.sender = CreateFrame("Frame")
Sort.sender:Hide()
Sort.sender:SetScript("OnShow", function()
	allowance = Sort.BudgetMs() -- the first swap of a round can go straight away
end)
Sort.sender:SetScript("OnUpdate", function(self)
	if not sending then
		self:Hide()
		return
	end
	Sort.lastFrames = (Sort.lastFrames or 0) + 1
	-- Bags opened mid-stream: the user is watching, so send the rest of the round now.
	local hurry = ns.AutoSort.BagsOpen()
	local budget = Sort.BudgetMs()
	allowance = math.min(allowance + budget, MAX_SAVED_MS)
	if allowance < budget and not hurry then
		return -- still paying off the last swap
	end
	local start = debugprofilestop()
	local batch = sending.batch
	repeat
		if InCombatLockdown() then
			cpuMs = cpuMs + (debugprofilestop() - start)
			CombatStop()
			return
		end
		local i = sending.i
		local before = debugprofilestop()
		Execute(batch[i])
		allowance = allowance - (debugprofilestop() - before)
		if GetCursorInfo() then
			cpuMs = cpuMs + (debugprofilestop() - start)
			Stop("stopped: a move didn't go through (" .. sending.keys[i] .. ").")
			return
		end
		sending.i = i + 1
	until sending.i > #batch or (allowance < budget and not hurry)
	cpuMs = cpuMs + (debugprofilestop() - start)
	if sending.i > #batch then
		sending = nil
		self:Hide()
		waitingForUpdate = true
		waitStarted = GetTime()
	end
end)

function Sort.OnBagUpdateDelayed()
	waitingForUpdate = false
end

function Sort.IsRunning()
	return ticker ~= nil
end

-- isQuiet: don't announce a normal finish (used by auto-sort).
function Sort.Start(isQuiet)
	if ticker then
		return
	end
	if InCombatLockdown() then
		Print("can't sort in combat.")
		return
	end
	quiet = isQuiet or false
	cpuMs, sendMs, maxSwapMs = 0, 0, 0
	Sort.lastFrames = 0
	ns.Sound.MuteItemSounds()
	moves, rounds, startedAt, lastKey, repeats = 0, 0, GetTime(), nil, 0
	waitingForUpdate, cursorSince, plan = false, nil, nil
	ticker = C_Timer.NewTicker(TICK, Step)
	ns.OnSortStateChanged()
end

function Sort.Cancel()
	if ticker then
		Stop(("cancelled after %d moves."):format(moves))
	end
end
