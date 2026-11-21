-- Offline simulation of the Sediment sort. Not loaded by the game.
-- Usage: lua dev/sim.lua <path to WTF SavedVariables/Sediment.lua> [seed]
-- Loads the bag scan saved by /sed scan, shuffles it into simulated bags, runs the real sort code
-- against mocked game APIs, and checks the result.

local svPath, seed = arg[1], tonumber(arg[2] or "1")
local root = arg[0]:match("^(.*)/dev/") or "."
dofile(svPath)
local scan = SedimentDB.lastScan.rows
SedimentDB = {}
math.randomseed(seed)

local BAG_SIZES = { [0] = 20, 16, 16, 16, 16 }
local bags = {}
for b = 0, 4 do bags[b] = {} end

-- Item templates from the scan.
local templates = {}
for _, r in ipairs(scan) do
	local stack = (r.classID == 7 or r.classID == 0 or r.classID == 12) and 20 or 1
	templates[#templates + 1] = {
		itemID = r.itemID, name = r.name, link = r.link, count = r.count, quality = r.quality,
		isBound = r.bound or r.isBound or false, classID = r.classID, subclassID = r.subclassID,
		equipLoc = r.equipLoc or "", isQuestItem = r.isQuestItem, maxStack = stack,
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

-- Scatter into random slots.
local free = {}
for b = 0, 4 do for s = 1, BAG_SIZES[b] do free[#free + 1] = { b, s } end end
for _, t in ipairs(templates) do
	local i = math.random(#free)
	local pos = table.remove(free, i)
	bags[pos[1]][pos[2]] = t
end

-- Mocks ---------------------------------------------------------------------------------------
local now, cursor = 0, nil
-- Slots touched this round stay locked until the round is "confirmed" at the end of the tick,
-- like the real game waiting on the server. Touching a locked slot fails.
local locked = {}
local function Key(b, s) return b * 100 + s end
local tickFn
Enum = { BagIndex = { Backpack = 0, Bag_4 = 4 }, BagSlotFlags = { DisableAutoSort = 1 }, ItemQuality = { Poor = 0 } }
local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local byID = {}
for _, t in ipairs(templates) do byID[t.itemID] = t end
C_Container = {
	GetContainerNumSlots = function(b) return BAG_SIZES[b] or 0 end,
	GetContainerNumFreeSlots = function(b) return 0, 0 end,
	GetBackpackAutosortDisabled = function() return false end,
	GetBagSlotFlag = function() return false end,
	GetContainerItemInfo = function(b, s)
		local t = bags[b][s]
		if not t then return nil end
		return { itemID = t.itemID, itemName = t.name, hyperlink = t.link, stackCount = t.count,
			quality = t.quality, isBound = t.isBound, isLocked = locked[Key(b, s)] or false }
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
	GetItemInfoInstant = function(id) local t = byID[id] return id, nil, nil, t.equipLoc, nil, t.classID, t.subclassID end,
	GetItemClassInfo = function(c) return "class" .. c end,
	GetItemSubClassInfo = function(c, s) return "sub" .. c .. ":" .. s end,
	GetItemMaxStackSizeByID = function(id) return byID[id].maxStack end,
}
GetCursorInfo = function() return cursor and "item" or nil end
ClearCursor = function() cursor = nil end
InCombatLockdown = function() return false end
GetTime = function() return now end
C_Timer = { NewTicker = function(_, fn) tickFn = fn return { Cancel = function() tickFn = nil end } end }
local messages = {}
local ns = { Print = function(m) messages[#messages + 1] = m end, OnSortStateChanged = function() end }

for _, f in ipairs({ "Weights.lua", "Bags.lua", "Sort.lua" }) do
	assert(loadfile(root .. "/" .. f))("Sediment", ns)
end
ns.Weights.Init()

local function Total()
	local n = {}
	for b = 0, 4 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
		if t then n[t.itemID] = (n[t.itemID] or 0) + t.count end end end
	return n
end

local function Run()
	local before = Total()
	ns.Sort.Start()
	local ticks = 0
	while tickFn do
		now = now + 0.05; ticks = ticks + 1
		tickFn()
		locked = {}
		ns.Sort.OnBagUpdateDelayed()
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
	for s = 1, BAG_SIZES[b] do
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
	end
end
-- At most one partial stack per item.
local partial = {}
for b = 0, 4 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
	if t and t.maxStack > 1 and t.count < t.maxStack then
		local k = t.link .. tostring(t.isBound)
		assert(not partial[k], "two partial stacks of " .. t.name)
		partial[k] = true
	end end end
end

print("first sort: " .. Run())
Check(arg[3] == "show")
print("second sort: " .. Run())

-- Scenario: the user's "item 99 goes to the top": the last floater suddenly weighs less than
-- everything, so every floater above it shifts down by one.
local lastFloater
for b = 0, 4 do for s = 1, BAG_SIZES[b] do local t = bags[b][s]
	if t then
		local item = ns.Bags.ReadSlot(b, s)
		if ns.Weights.Resolve(item) < ns.Weights.SinkLine() then lastFloater = item end
	end end end
SedimentDB.weights.items[lastFloater.itemID] = -1
print("to the top (" .. lastFloater.name .. "): " .. Run())
Check(false)
-- And back down again.
SedimentDB.weights.items[lastFloater.itemID] = 1000
print("to the bottom: " .. Run())
Check(false)
print("OK")
