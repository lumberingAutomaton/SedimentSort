-- AutoSort: keep the bags sorted by themselves.
--
-- Rules:
-- - Any bag change (loot, crafting, using something up, selling) makes a sort pending.
-- - Bags open: nothing moves unless you press sort. A pending sort runs when you close them.
-- - Also waits out: combat, an item on the cursor, vendor/bank/mail/trade/auction/guild bank
--   windows, a sort already running, and bag changes in the last few seconds (/sed delay; so a burst
--   of looting gives one sort, and new quest items are known as quest items by then).
-- - A quest log change also makes a sort pending: the quest flag on an item can show up later
--   than the item itself.
-- - On by default. Right-click the bag sort button, or /sed auto, to toggle.
-- So whenever the bags are closed, they're in exact order.

local _, ns = ...
local AutoSort = {}
ns.AutoSort = AutoSort

local CHECK_EVERY = 0.25 -- seconds between checks while a sort is pending
-- Seconds of no bag changes before sorting: long enough for a burst of looting to finish and for
-- the game to mark new quest items as quest items. Adjustable with /sed delay (SedimentDB.autoSortDelay)
-- while the user finds a good value.
local DEFAULT_DELAY = 2
local MIN_DELAY, MAX_DELAY = 0, 30

function AutoSort.Delay()
	return SedimentDB.autoSortDelay or DEFAULT_DELAY
end

-- seconds = nil shows the current value.
function AutoSort.SetDelay(seconds)
	if seconds == nil then
		ns.Print(("auto-sort waits %ss after the last bag change (default %ss). /sed delay <seconds> to change.")
			:format(AutoSort.Delay(), DEFAULT_DELAY))
		return
	end
	seconds = math.max(MIN_DELAY, math.min(MAX_DELAY, seconds))
	SedimentDB.autoSortDelay = seconds
	ns.Print(("auto-sort now waits %ss after the last bag change."):format(seconds))
end

local ready = false      -- false until shortly after login, while the bags are still loading in
local pending = false
local lastBagUpdate = 0

-- Have the bags been quiet for the auto-sort delay? (A paused sort waits for this before going on.)
-- Must come after the lastBagUpdate local above: functions only see locals declared before them.
function AutoSort.QuietLongEnough()
	return GetTime() - lastBagUpdate >= AutoSort.Delay()
end
local ticker

-- Windows where items get clicked a lot (selling, mailing, trading) or come and go from the bank.
local BUSY_FRAMES = {
	"MerchantFrame", "BankFrame", "MailFrame", "SendMailFrame", "TradeFrame",
	"AuctionHouseFrame", "AuctionFrame", "GuildBankFrame",
}

function AutoSort.IsEnabled()
	return SedimentDB.autoSort ~= false
end

local function BagsOpen()
	if IsAnyBagOpen and IsAnyBagOpen() then
		return true
	end
	return ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsVisible() or false
end
AutoSort.BagsOpen = BagsOpen

-- IsVisible, not IsShown: IsShown only checks the frame's own flag, so a tab inside a closed window
-- (SendMailFrame inside MailFrame) can count as shown while nothing is on screen.
local function BusyWindowOpen()
	for _, name in ipairs(BUSY_FRAMES) do
		local f = _G[name]
		if f and f:IsVisible() then
			return name
		end
	end
	return false
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function Check()
	if not pending or not AutoSort.IsEnabled() then
		pending = false
		StopTicker()
		return
	end
	if ns.Sort.IsRunning() or InCombatLockdown() or GetCursorInfo() or BagsOpen() or BusyWindowOpen() then
		return
	end
	if GetTime() - lastBagUpdate < AutoSort.Delay() then
		return
	end
	pending = false
	StopTicker()
	ns.Sort.Start(true)
end

-- At login the bags fill in over a moment, firing lots of bag updates. Ignore those.
function AutoSort.OnEnteringWorld()
	ready = false
	C_Timer.After(2, function()
		ready = true
	end)
end

local function MakePending()
	if not ready or ns.Sort.IsRunning() or not AutoSort.IsEnabled() then
		return -- a running sort's own moves don't count
	end
	pending = true
	if not ticker then
		ticker = C_Timer.NewTicker(CHECK_EVERY, Check)
	end
end

-- A quiet sort stopped by combat: run again once combat is over (Check waits for that).
function AutoSort.Resume()
	MakePending()
end

function AutoSort.OnBagUpdateDelayed()
	lastBagUpdate = GetTime()
	MakePending()
end

-- Quest log changes can turn a bag item into a quest item (or back) without any bag update.
-- Sorting when nothing needs to move makes no moves, so this is cheap.
function AutoSort.OnQuestLogChanged()
	MakePending()
end

-- What auto-sort is doing or waiting for, for /sed auto?.
function AutoSort.Status()
	local reasons = {}
	if not AutoSort.IsEnabled() then reasons[#reasons + 1] = "turned off" end
	if not ready then reasons[#reasons + 1] = "login grace period" end
	if ns.Sort.IsRunning() then reasons[#reasons + 1] = "a sort is running" end
	if InCombatLockdown() then reasons[#reasons + 1] = "in combat" end
	if GetCursorInfo() then reasons[#reasons + 1] = "cursor is holding something" end
	if BagsOpen() then reasons[#reasons + 1] = "bags are open" end
	local busy = BusyWindowOpen()
	if busy then reasons[#reasons + 1] = busy .. " is open" end
	local quietFor = GetTime() - lastBagUpdate
	if quietFor < AutoSort.Delay() then
		reasons[#reasons + 1] = ("bags changed under %ss ago"):format(AutoSort.Delay())
	end
	local S = ns.Sort
	ns.Print(("auto-sort: %s; sort %s. Blocked by: %s."):format(
		AutoSort.IsEnabled() and "on" or "off",
		pending and "pending" or "not pending",
		#reasons > 0 and table.concat(reasons, ", ") or "nothing"))
	ns.Print(("last sort: %d moves, %d rounds, %d frames. Total %.1fms = planning %.1fms + swaps %.1fms"
		.. " (slowest swap %.1fms)."):format(
		S.lastMoves or 0, S.lastRounds or 0, S.lastFrames or 0, S.lastCpuMs or 0,
		(S.lastCpuMs or 0) - (S.lastSendMs or 0), S.lastSendMs or 0, S.lastMaxSwapMs or 0))
end

function AutoSort.Toggle()
	SedimentDB.autoSort = not AutoSort.IsEnabled()
	ns.Print("auto-sort on loot " .. (AutoSort.IsEnabled() and "|cff66ff66ON|r" or "|cffff6666OFF|r") .. ".")
	if not AutoSort.IsEnabled() then
		pending = false
		StopTicker()
	end
	ns.OnAutoSortChanged()
end
