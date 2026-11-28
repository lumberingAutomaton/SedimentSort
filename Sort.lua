-- Sort: the gravity sort. Light items (weight below the sink line) pack from the top, heavy items
-- pack from the bottom, free space stays in the middle.
--
-- It works in rounds. Each round sends every move that can go out at once (no slot used twice) and
-- waits for the game to confirm them. Phases: merge partial stacks, place items (always two rounds,
-- see PlanPlacement), put partial stacks last. Every round re-reads the bags and checks them against
-- the plan, so looting or the user moving something mid-sort just triggers a fresh plan.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Sort.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Sort = {}
ns.Sort = Sort

local TICK = 0.05         -- seconds between checks
local UPDATE_TIMEOUT = 2  -- seconds to wait for the game to confirm a move
local CURSOR_TIMEOUT = 3  -- seconds to wait for the user to drop something from the cursor
local MAX_MOVES = 1000
local MAX_REPEATS = 3     -- same batch this many times in a row = stuck
local MAX_IN_FLIGHT = 1   -- our swaps waiting for the game at once (2026-11-27). Every lockup today had several
                          -- swaps waiting at once: one went unanswered and every swap sent behind it was lost too,
                          -- each leaving its items locked until a client restart. Auto-sort, which never failed,
                          -- in effect has one at a time. (Bag Master allows 4; we tried 4 and lost 4.)
local LAND_WAIT = 2       -- seconds to wait for our swaps to land before carrying on around whatever is still locked
local LAND_CHECK = 0.05   -- seconds between looks at the bags while waiting for swaps to land
local SETTLE = 0.5        -- seconds after the last edit before its sort starts, so a burst of edits makes one sort

local ticker
local moves, rounds, startedAt, lastKey, repeats
local waitingForUpdate, waitStarted, cursorSince
local flying, flyingSince, lastLandCheck -- our swaps sent and not yet landed (see Fly), and since when
local skipTraced -- locked slots this sort has already noted in the trace

-- The debug addon's sort trace (Debug.lua, ns.SortTrace): what the sort does, step by step. Nothing without it.
local function Trace(...)
	if ns.SortTrace then
		ns.SortTrace(...)
	end
end

local function SlotText(s)
	return ("%d/%d %s"):format(s.bag, s.slot, s.item and (s.item.link or s.item.itemID) or "empty")
end
local plan -- { rounds, round, n }: placement rounds still to send
local quiet    -- auto-sort: no chat on success, and stream the swaps
local cpuMs = 0 -- our own Lua time during the current sort
local movesByKind = {} -- this sort's moves per phase (merge, transfer, place, restack), for tests
local sendMs, maxSwapMs = 0, 0 -- of which: making the swaps (including handlers the game runs inside them)
local movesDone = 0 -- swaps sent so far in this sort, for the progress sweep
local sending  -- { batch, keys, i }: a round being streamed out over several frames
local hurry    -- an auto-sort finishing at full speed because the bags opened
local mode = "sort" -- or "scramble": a test-bench scramble aimed at scrambleTargets
local scrambleTargets, scrambleCount, scramblePlanned

-- Frame timing for the test bench: while a sort runs, count frames and track the slowest one;
-- otherwise keep a running average frame time as the "before" baseline.
local perfFrames, perfTime, perfWorst, baselineFrame = 0, 0, 0, 1 / 60
local perfBase
-- Smoothness metrics (see Sort.perf below): frames noticeably slower than normal ("hitches"), and the
-- worst one-second stretch, which is what an eye (or an FPS counter) actually judges.
local HITCH_FACTOR = 1.5   -- a frame this many times the normal frame time counts as a hitch
local perfHitches = 0
local perfMinWindowFps = math.huge
local trackUntil = 0       -- keep watching the one-second window until a second after the sort ends

local function Print(msg)
	ns.Print(msg)
end

-- Planning ------------------------------------------------------------------------------------

-- The full order (button sorts): lighter first, then by equipment set (so each set stays together),
-- then by category, then by item, then bigger stacks first. Same bag in, same layout out.
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
		-- Stacks in special bags (reagent, profession) first, so they're the ones topped up and strays
		-- from the normal bags get folded in. A stable move-to-front. Items kept out of special bags go
		-- the other way: normal-bag stacks first, so stacks drain out of the special bag.
		local keptOut = ns.Bags.KeepOut(list[1].item)
		local first = {}
		for _, s in ipairs(list) do
			if (s.zone ~= "main") ~= keptOut then first[#first + 1] = s end
		end
		for _, s in ipairs(list) do
			if (s.zone ~= "main") == keptOut then first[#first + 1] = s end
		end
		list = first
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

-- Every sort, button or auto, uses the one full order (Compare above): every item always has the same spot.
-- (A partial order for auto-sorts, keeping equal-weight items where they were for fewer moves, was removed
-- in 0.20: user, 2026-11-26, "no partial sort".)

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

-- Items kept out of special bags ("Keep in my normal bags") that are in one move to empty normal-bag
-- slots; placement then sorts them by weight. Plain moves into empty slots, one round. If the normal bags
-- are full, the rest stay where they are until there's room.
local function EvictMoves(slots)
	local empties, batch = {}, {}
	for _, s in ipairs(slots) do
		if s.zone == "main" and not s.item then
			empties[#empties + 1] = s
		end
	end
	for _, s in ipairs(slots) do
		if #batch >= #empties then
			break
		end
		if s.zone ~= "main" and s.item and ns.Bags.KeepOut(s.item) then
			batch[#batch + 1] = { kind = "evict", src = s, dst = empties[#batch + 1] }
		end
	end
	return batch
end

-- Items in the normal bags move into empty slots of a special bag that accepts them: reagents into
-- the reagent bag (as Blizzard's sort used to do), herbs into an herb bag, and so on. Slots are
-- listed profession bags before the reagent bag, so an herb that's also a crafting reagent goes to
-- the herb bag first. Plain moves into empty slots, so they all go out in one round. What doesn't
-- fit anywhere stays in the normal bags and sorts there by weight. Nothing leaves a special bag.
local function TransferMoves(slots)
	local batch, taken = {}, {}
	local empties = {} -- zone -> list of empty slots, in zone order
	local zoneOrder = {}
	for _, s in ipairs(slots) do
		if s.zone ~= "main" then
			if not empties[s.zone] then
				empties[s.zone] = {}
				zoneOrder[#zoneOrder + 1] = s.zone
			end
			if not s.item then
				table.insert(empties[s.zone], s)
			end
		end
	end
	for _, zone in ipairs(zoneOrder) do
		local free = empties[zone]
		local used = 0
		for _, s in ipairs(slots) do
			if used >= #free then
				break
			end
			if s.zone == "main" and s.item and not taken[s] and ns.Bags.ShouldTransfer(s.item, free[1].info) then
				used = used + 1
				taken[s] = true
				batch[#batch + 1] = { kind = "transfer", src = s, dst = free[used] }
			end
		end
	end
	return batch
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

-- Plan each zone (normal bags, reagent bag) on its own and send their rounds together. A chain
-- that crossed zones could route a non-reagent through a reagent bag slot mid-sort, which the game
-- refuses; planned apart, every item stays inside its own zone the whole time.
local function PlanZones(slots)
	local zones, order = {}, {}
	for index, s in ipairs(slots) do
		local z = zones[s.zone]
		if not z then
			z = { slots = {}, map = {} }
			zones[s.zone] = z
			order[#order + 1] = s.zone
		end
		z.slots[#z.slots + 1] = s
		z.map[#z.slots] = index
	end
	local combined = {}
	for _, name in ipairs(order) do
		local z = zones[name]
		local rounds = PlanPlacement(z.slots, PlanTargets(z.slots))
		for r, round in ipairs(rounds) do
			combined[r] = combined[r] or {}
			for _, swap in ipairs(round) do
				-- Zone positions back to positions in the full slot list.
				swap.a, swap.b = z.map[swap.a], z.map[swap.b]
				table.insert(combined[r], swap)
			end
		end
	end
	return combined
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
			while slots[q] and slots[q].zone == s.zone and slots[q].item and slots[q].item.sig == item.sig do
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
	Trace("stop", success and "ok" or "not ok", msg)
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	waitingForUpdate = false
	plan = nil
	sending = nil
	flying = nil
	hurry = false
	if Sort.sender then
		Sort.sender:Hide()
	end
	if GetCursorInfo() then
		ClearCursor()
	end
	ns.Sound.UnmuteItemSounds()
	Sort.lastCpuMs, Sort.lastMoves, Sort.lastRounds = cpuMs, moves, rounds
	Sort.lastMovesByKind = movesByKind
	Sort.lastSendMs, Sort.lastMaxSwapMs = sendMs, maxSwapMs
	local wasScramble = mode == "scramble"
	if moves and moves > 0 then
		-- Test bench history: what this sort cost. The worst-second figure needs the second after the
		-- sort too (a short sort's hitches sit in a window that runs past its end), so the run is
		-- finished off a second later.
		local seconds = GetTime() - startedAt
		local beforeFps = perfBase and 1 / perfBase or 0
		local run = {
			kind = wasScramble and "scramble" or (quiet and "auto" or "button"),
			moves = moves, rounds = rounds, seconds = seconds, ourMs = cpuMs,
			worstMs = perfWorst * 1000,
			normalMs = perfBase and perfBase * 1000 or 0,
			hitches = perfHitches,
			hitchRate = perfHitches / math.max(seconds, 1),
			beforeFps = beforeFps,
			finished = success or false,
		}
		trackUntil = GetTime() + 1
		C_Timer.After(1.05, function()
			run.worstSecondFps = perfMinWindowFps < math.huge and perfMinWindowFps or beforeFps
			run.dropPct = beforeFps > 0 and math.max(0, (1 - run.worstSecondFps / beforeFps) * 100) or 0
			Sort.lastRun = run
			DisorderItemManagerDB.benchHistory = DisorderItemManagerDB.benchHistory or {}
			table.insert(DisorderItemManagerDB.benchHistory, 1, run)
			DisorderItemManagerDB.benchHistory[21] = nil
			ns.OnBenchRun()
		end)
	end
	mode, scrambleTargets, scrambleCount, scramblePlanned = "sort", nil, 0, false
	if msg and not (success and quiet) then
		Print(msg)
	end
	ns.OnSortStateChanged()
	ns.OnSortFinished(success)
	if wasScramble and success then
		ns.AutoSort.Resume() -- the scramble's own moves didn't count as changes; let auto-sort clean up
	end
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

-- An auto-sort that finds the bags open finishes at full speed: everything left goes out at once, in the
-- same order, so the bags settle within a round or two of opening (user, 2026-11-26: always "finish"; the
-- old "pause" mode, which waited with the plan kept until the bags closed, was removed in 0.20).
local function HurryIfBagsOpen()
	if quiet and not hurry and ns.AutoSort.BagsOpen() then
		hurry = true
	end
end

function Sort.IsQuiet()
	return quiet
end

function Sort.OnCombatStart()
	if ticker then
		CombatStop()
	end
end

-- A move left the item on the cursor: the game refused it. A refused transfer into a special bag
-- means that bag doesn't take that item after all, so put it back, remember it for the session,
-- and carry on. Anything else stops the sort. Returns true if the sort can continue.
local function HandleFailedMove(move, key)
	if move.kind == "transfer" then
		ClearCursor()
		ns.Bags.refused[move.dst.zone .. ":" .. move.src.item.itemID] = true
		return true
	end
	Stop("stopped: a move didn't go through (" .. key .. ").")
	return false
end

local ExecuteSwap

-- Moves in flight (user, 2026-11-27): once a swap is sent, neither of its slots is touched again until the game
-- shows it landed, and no more than MAX_IN_FLIGHT swaps wait for the game at once. Each swap records what its two
-- slots should hold once it lands (bag*1000+slot -> { sig, count }).
local function Fly(move)
	local src, dst = move.src, move.dst
	local si, di = src.item, dst.item
	local f = {}
	if move.kind == "merge" then
		-- Part (or all) of the source stack onto the destination stack of the same item.
		local left = si.count - move.amount
		f[src.bag * 1000 + src.slot] = { sig = left > 0 and si.sig or EMPTY, count = left > 0 and left or 0 }
		f[dst.bag * 1000 + dst.slot] = { sig = di.sig, count = di.count + move.amount }
	else
		-- A swap (or a move into an empty slot): the two slots trade contents.
		f[src.bag * 1000 + src.slot] = { sig = di and di.sig or EMPTY, count = di and di.count or 0 }
		f[dst.bag * 1000 + dst.slot] = { sig = si.sig, count = si.count }
	end
	flying = flying or {}
	flying[#flying + 1] = f
	flyingSince = GetTime()
end

-- Drop the swaps that have landed: both slots hold what they should and neither is locked.
local function Land(slots)
	if not flying then
		return
	end
	local now = {}
	for _, sl in ipairs(slots) do
		now[sl.bag * 1000 + sl.slot] = sl
	end
	local still = {}
	for _, f in ipairs(flying) do
		local landed = true
		for key, e in pairs(f) do
			local item = now[key] and now[key].item
			if (item and item.sig or EMPTY) ~= e.sig or (item and item.count or 0) ~= e.count or (item and item.isLocked) then
				landed = false
			end
		end
		if not landed then
			still[#still + 1] = f
		end
	end
	flying = #still > 0 and still or nil
end

-- Wait for our swaps to land: true while still waiting (at most LAND_WAIT); after that, carry on: whatever is
-- still locked is planned around.
local function WaitingToLand(need)
	if not flying or #flying < need then
		return false
	end
	local now = GetTime()
	if now - (lastLandCheck or 0) >= LAND_CHECK then
		lastLandCheck = now
		Land((ns.Bags.Read()))
	end
	if not flying or #flying < need then
		return false
	end
	if now - flyingSince < LAND_WAIT then
		return true
	end
	Trace("not landed after", LAND_WAIT, "s:", #flying, "swaps; carrying on around them")
	flying = nil
	return false
end

-- Is this slot locked right now (a swap of ours landing, an item in use, anything the game holds)?
local function IsLocked(s)
	local item = ns.Bags.ReadSlot(s.bag, s.slot)
	return item and item.isLocked or false
end

-- One swap, timed. The time includes every event handler the game runs inside the pick-up and
-- drop calls (Blizzard's UI and other addons), since those run before the call returns.
local function Execute(move)
	Trace("move", move.kind, SlotText(move.src), "->", SlotText(move.dst))
	local t = debugprofilestop()
	ExecuteSwap(move)
	local spent = debugprofilestop() - t
	sendMs = sendMs + spent
	if spent > maxSwapMs then
		maxSwapMs = spent
	end
	movesDone = movesDone + 1
end

-- Progress for the sweep: swaps done out of swaps known (done + left in this round + planned rounds).
-- Work, not a time estimate: estimates made the sweep finish early (then start a second one) or
-- crawl long after the sort was done.
local function ReportProgress(leftInRound)
	local planned = 0
	if plan then
		for r = plan.round, #plan.rounds do
			planned = planned + #plan.rounds[r]
		end
	end
	ns.OnSortProgress(movesDone, movesDone + leftInRound + planned)
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
	HurryIfBagsOpen()
	if InCombatLockdown() then
		CombatStop()
		return
	end

	if waitingForUpdate then
		if GetTime() - waitStarted < UPDATE_TIMEOUT then
			return
		end
		Trace("no bag update after", UPDATE_TIMEOUT, "s")
		waitingForUpdate = false -- no confirmation; carry on and let the re-read sort it out
	end

	if GetCursorInfo() then
		if not cursorSince then
			Trace("cursor holds", GetCursorInfo())
		end
		cursorSince = cursorSince or GetTime()
		if GetTime() - cursorSince > CURSOR_TIMEOUT then
			cursorSince = nil
			Stop("stopped: something is on the cursor.")
		end
		return
	end
	cursorSince = nil

	-- Our last round has to land before anything new is planned (up to LAND_WAIT).
	if WaitingToLand(1) then
		return
	end
	-- Locked slots, whatever the reason, are left out of this plan: their items stay where they are for now and
	-- everything else sorts around them. No waiting and no message (user, 2026-11-27); once a slot unlocks it's
	-- planned again. (Bag Master does the same.)
	local all, lockedList = ns.Bags.Read()
	local slots = all
	if lockedList then
		local skip = {}
		for _, s in ipairs(lockedList) do
			local key = s.bag * 1000 + s.slot
			skip[key] = true
			if not skipTraced[key] then
				skipTraced[key] = true
				Trace("skipping locked", SlotText(s))
			end
		end
		slots = {}
		for _, s in ipairs(all) do
			if not skip[s.bag * 1000 + s.slot] then
				slots[#slots + 1] = s
			end
		end
	end

	-- One phase per round: merge stacks, move kept-out items out of special bags, move items into special
	-- bags, place, restack.
	-- Each phase changes what the next one plans from.
	local batch = plan and TakePlanned(slots)
	if mode == "scramble" then
		-- A scramble is placement only, toward its targets, planned once. The normal bags come first
		-- in the slot list, so their positions are the same in both lists.
		if not batch and not scramblePlanned then
			scramblePlanned = true
			local mainSlots = {}
			-- scrambleCount, not #scrambleTargets: empty slots are nil, and # stops at a gap.
			for i = 1, scrambleCount do
				mainSlots[i] = slots[i]
			end
			local placement = PlanPlacement(mainSlots, scrambleTargets)
			if #placement > 0 then
				plan = { rounds = placement, round = 1, n = #slots }
				batch = TakePlanned(slots)
			end
		end
		if not batch or #batch == 0 then
			Stop(("scrambled: %d moves. Close your bags to let auto-sort clean up."):format(moves), true)
			return
		end
	elseif not batch then
		batch = MergeMoves(slots)
		if #batch == 0 then
			batch = EvictMoves(slots)
		end
		if #batch == 0 then
			batch = TransferMoves(slots)
		end
		if #batch == 0 then
			local placement = PlanZones(slots)
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
	Trace("round", rounds, batch[1].kind, #batch, "moves")
	movesByKind[batch[1].kind] = (movesByKind[batch[1].kind] or 0) + #batch
	if moves > MAX_MOVES then
		Stop("stopped: too many moves.")
		return
	end

	ReportProgress(#batch)
	-- Every round streams out through the sender: auto-sorts paced for smoothness, the others as fast as the
	-- in-flight limit allows.
	sending = { batch = batch, keys = keys, i = 1 }
	Sort.sender:Show()
end

-- Streaming. Each swap makes the game fire events right away, and Blizzard's UI and other addons
-- run their handlers inside that same frame: measured in game at about 5ms per swap, nearly all of
-- it outside Sediment. One swap can't be made cheaper, so auto-sort controls how often a swap lands
-- on a frame instead. The budget is an average: every frame adds BudgetMs of allowance, every swap
-- spends what it actually cost (handlers included), and a swap only goes out while the allowance
-- isn't overdrawn. With ~8ms swaps and the 0.3ms default that's one swap every ~27 frames. We don't wait
-- for the server between frames, so the round is still one round to the server.
local DEFAULT_BUDGET_MS = 0.3 -- picked in game 2026-11-24: Drift clean-ups ~1s (was 2s+ at 0.1), worst second about -6%
local MAX_SAVED_MS = 5 -- allowance can't pile up beyond this, so a quiet spell can't buy a burst

function Sort.BudgetMs()
	return DisorderItemManagerDB.streamBudgetMs or DEFAULT_BUDGET_MS
end

local allowance = 0

Sort.sender = CreateFrame("Frame")
Sort.sender:Hide()
-- The allowance is set once when a sort starts (Sort.Start), not per round: resetting it every
-- round let each round's first swap go straight out, so a two-round sort's two hitches landed a
-- quarter-second apart, which reads as one obvious stutter (seen in game after a quest reward).
Sort.sender:SetScript("OnUpdate", function(self)
	if not sending then
		self:Hide()
		return
	end
	Sort.lastFrames = (Sort.lastFrames or 0) + 1
	HurryIfBagsOpen() -- bags opened mid-stream: the rest goes out unpaced
	-- Paced only for an auto-sort that isn't hurrying. A button sort, or one that took over an auto-sort
	-- (Sort.Start), sends the rest at once.
	local paced = quiet and not hurry
	local budget = paced and Sort.BudgetMs() or math.huge
	allowance = math.min(allowance + budget, MAX_SAVED_MS)
	if paced and allowance < budget then
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
		-- No more than MAX_IN_FLIGHT of our swaps waiting for the game at once.
		if WaitingToLand(MAX_IN_FLIGHT) then
			break
		end
		local i = sending.i
		local move = batch[i]
		-- A slot that got locked since the plan (an item put to use, say): drop the rest of this round and
		-- plan again around it.
		if IsLocked(move.src) or IsLocked(move.dst) then
			Trace("locked since planning; planning again", SlotText(IsLocked(move.src) and move.src or move.dst))
			sending, plan = nil, nil
			self:Hide()
			cpuMs = cpuMs + (debugprofilestop() - start)
			return
		end
		local before = debugprofilestop()
		Execute(move)
		allowance = allowance - (debugprofilestop() - before)
		if GetCursorInfo() then
			if not HandleFailedMove(move, sending.keys[i]) then
				cpuMs = cpuMs + (debugprofilestop() - start)
				return
			end
		else
			Fly(move)
		end
		sending.i = i + 1
		ReportProgress(#batch - i)
	until sending.i > #batch or (paced and allowance < budget)
	cpuMs = cpuMs + (debugprofilestop() - start)
	if sending.i > #batch then
		sending = nil
		self:Hide()
		waitingForUpdate = true
		waitStarted = GetTime()
	end
end)

function Sort.OnBagUpdateDelayed()
	if ticker then
		Trace("bag update")
	end
	waitingForUpdate = false
end

function Sort.IsRunning()
	return ticker ~= nil
end

-- isQuiet: don't announce a normal finish (used by auto-sort). why: for the trace ("edit").
function Sort.Start(isQuiet, why)
	if ticker then
		-- A button sort during an auto-sort takes it over: same plan, full speed.
		if quiet and not isQuiet then
			quiet = false
		end
		return
	end
	if InCombatLockdown() then
		Print("can't sort in combat.")
		return
	end
	quiet = isQuiet or false
	movesDone = 0
	perfFrames, perfTime, perfWorst, perfBase = 0, 0, 0, baselineFrame
	perfHitches, perfMinWindowFps = 0, math.huge
	allowance = Sort.BudgetMs() -- the sort's first swap can go straight away
	movesByKind = {}
	cpuMs, sendMs, maxSwapMs = 0, 0, 0
	Sort.lastFrames = 0
	ns.Sound.MuteItemSounds()
	moves, rounds, startedAt, lastKey, repeats = 0, 0, GetTime(), nil, 0
	waitingForUpdate, cursorSince, plan, hurry, flying, skipTraced = false, nil, nil, false, nil, {}
	Trace("start", quiet and "auto" or why or "button", mode)
	ticker = C_Timer.NewTicker(TICK, Step)
	ns.OnSortStateChanged()
end

-- A sort soon, to show the result of a change the player just made (an Ordering edit, the popup's Add, a History
-- save loaded): bags open or not. It starts SETTLE seconds after the last change, so a burst of edits makes one
-- sort, and after any sort still running (which planned with the old rules).
local sortWaiting, settleUntil = false, 0

function Sort.StartSoon()
	if InCombatLockdown() then
		return
	end
	settleUntil = GetTime() + SETTLE
	if sortWaiting then
		return
	end
	sortWaiting = true
	local function Try()
		if GetTime() < settleUntil or ticker then
			C_Timer.After(0.1, Try)
			return
		end
		sortWaiting = false
		if not InCombatLockdown() then
			Sort.Start(false, "edit")
		end
	end
	C_Timer.After(0.1, Try)
end

-- Test bench: rearrange the normal bags into targets (one item signature or nil per normal-bag
-- slot, in on-screen order; count = number of normal-bag slots) at full speed. Built by the bench
-- window from a seeded shuffle.
function Sort.Scramble(targets, count)
	if ticker then
		Print("a sort is already running.")
		return
	end
	Sort.Start(false)
	if ticker then
		mode, scrambleTargets, scrambleCount, scramblePlanned = "scramble", targets, count, false
	end
end

-- Frame timing (see perf locals above).
Sort.perf = CreateFrame("Frame")
local window, windowSum = {}, 0 -- recent frame times covering the last second
Sort.perf:SetScript("OnUpdate", function(_, elapsed)
	elapsed = elapsed or 0
	if elapsed <= 0 then
		return
	end
	window[#window + 1] = elapsed
	windowSum = windowSum + elapsed
	while #window > 1 and windowSum - window[1] >= 1 do
		windowSum = windowSum - window[1]
		table.remove(window, 1)
	end
	local tracking = ticker or GetTime() < trackUntil
	if tracking and windowSum >= 0.9 then
		local fps = #window / windowSum
		if fps < perfMinWindowFps then
			perfMinWindowFps = fps
		end
	end
	if ticker then
		perfFrames = perfFrames + 1
		perfTime = perfTime + elapsed
		if elapsed > perfWorst then
			perfWorst = elapsed
		end
		if perfBase and elapsed > perfBase * HITCH_FACTOR then
			perfHitches = perfHitches + 1
		end
	elseif not tracking then
		baselineFrame = baselineFrame * 0.95 + elapsed * 0.05
	end
end)

function Sort.Cancel()
	if ticker then
		Stop(("cancelled after %d moves."):format(moves))
	end
end
