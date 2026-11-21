-- Sort: the gravity sort. Light items (weight below the sink line) pack from the top, heavy items
-- pack from the bottom, free space stays in the middle.
--
-- It works in rounds. Each round re-reads the bags, works out every move that can go out at once
-- (no slot used twice), sends them all, and waits for the game to confirm them. Re-reading every
-- round means looting, or the user moving something mid-sort, can't throw it off: the next round
-- just plans from what's really there.

local _, ns = ...
local Sort = {}
ns.Sort = Sort

local TICK = 0.05         -- seconds between checks
local UPDATE_TIMEOUT = 2  -- seconds to wait for the game to confirm a move
local CURSOR_TIMEOUT = 3  -- seconds to wait for the user to drop something from the cursor
local MAX_MOVES = 1000
local MAX_REPEATS = 3     -- same batch this many times in a row = stuck
local MAX_BATCH = 40      -- most moves sent in one round

local ticker
local moves, rounds, startedAt, lastKey, repeats
local waitingForUpdate, waitStarted, cursorSince

local function Print(msg)
	ns.Print(msg)
end

-- Planning ------------------------------------------------------------------------------------

-- Order for items: lighter first, then grouped by category, then by item, then bigger stacks first.
local function Compare(a, b)
	if a.weight ~= b.weight then
		return a.weight < b.weight
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
		while i < j and #batch < MAX_BATCH do
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

-- All placement moves for this round. Walk the positions holding the wrong thing and fill each
-- from a slot whose item belongs there and isn't already in a correct spot. A slot is used by at
-- most one move per round, so the moves can't interfere and all go out at once.
local function PlaceMoves(slots, targets)
	local batch, used = {}, {}
	for p, s in ipairs(slots) do
		if #batch >= MAX_BATCH then
			break
		end
		local want = targets[p]
		local have = s.item and s.item.sig
		if want and have ~= want and not used[p] then
			-- Best source: one whose own target is what p holds now, so the swap fixes both slots.
			local best
			for q, other in ipairs(slots) do
				if not used[q] and q ~= p and other.item and other.item.sig == want and targets[q] ~= want then
					if targets[q] == have then
						best = q
						break
					end
					best = best or q
				end
			end
			if best then
				batch[#batch + 1] = { kind = "place", src = slots[best], dst = s }
				used[p], used[best] = true, true
			end
		end
	end
	return batch
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

local function Stop(msg)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	waitingForUpdate = false
	if GetCursorInfo() then
		ClearCursor()
	end
	if msg then
		Print(msg)
	end
	ns.OnSortStateChanged()
end

local function Execute(move)
	local src, dst = move.src, move.dst
	if move.kind == "merge" and move.amount < src.item.count then
		C_Container.SplitContainerItem(src.bag, src.slot, move.amount)
	else
		C_Container.PickupContainerItem(src.bag, src.slot)
	end
	C_Container.PickupContainerItem(dst.bag, dst.slot)
end

local function Step()
	if InCombatLockdown() then
		Stop("stopped: entered combat. Press sort again afterwards.")
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
	local batch = MergeMoves(slots)
	if #batch == 0 then
		batch = PlaceMoves(slots, PlanTargets(slots))
	end
	if #batch == 0 then
		batch = RestackMoves(slots)
	end
	if #batch == 0 then
		Stop(moves == 0 and "already sorted."
			or ("sorted: %d moves in %d rounds, %.1fs."):format(moves, rounds, GetTime() - startedAt))
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

	for i, move in ipairs(batch) do
		Execute(move)
		if GetCursorInfo() then
			Stop("stopped: a move didn't go through (" .. keys[i] .. ").")
			return
		end
	end
	waitingForUpdate = true
	waitStarted = GetTime()
end

function Sort.OnBagUpdateDelayed()
	waitingForUpdate = false
end

function Sort.IsRunning()
	return ticker ~= nil
end

function Sort.Start()
	if ticker then
		return
	end
	if InCombatLockdown() then
		Print("can't sort in combat.")
		return
	end
	moves, rounds, startedAt, lastKey, repeats = 0, 0, GetTime(), nil, 0
	waitingForUpdate, cursorSince = false, nil
	ticker = C_Timer.NewTicker(TICK, Step)
	ns.OnSortStateChanged()
end

function Sort.Cancel()
	if ticker then
		Stop(("cancelled after %d moves."):format(moves))
	end
end
