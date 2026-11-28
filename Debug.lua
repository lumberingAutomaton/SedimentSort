-- Debug: the Debug group's sections (Testing, Tools, Files), the test bench and the bag scan. Shown only
-- while the debug addon is loaded (Settings.DebugOn). Lives in the main addon until it moves into the debug
-- addon (PLAN.md, Phase 3).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Debug.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Debug = {}
ns.Debug = Debug
local Settings = ns.Settings
local UI = Settings.UI
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)
local Flow, Text, HelpText, NewBox, LabeledBox, CheckRow = UI.Flow, UI.Text, UI.HelpText, UI.NewBox, UI.LabeledBox,
	UI.CheckRow
local GAP_HELP, GAP_GROUP, CONTROL_X, CONTENT_W, ROW_HEIGHT, CLICK_GUARD = UI.GAP_HELP, UI.GAP_GROUP, UI.CONTROL_X,
	UI.CONTENT_W, UI.ROW_HEIGHT, UI.CLICK_GUARD
local Changed, WeightChanged, FormatWeight = UI.Changed, UI.WeightChanged, UI.FormatWeight
local ItemLabel, ClassLabel, SubclassLabel, KeepOutLabel = UI.ItemLabel, UI.ClassLabel, UI.SubclassLabel, UI.KeepOutLabel

local Print = function(msg) ns.Print(msg) end

-- The sort trace: every step of every sort (start, rounds, each move with both slots, waits and why, bag
-- updates, how it ended), kept in DisorderItemManagerDB.sortTrace (the last 600 lines) for reading after a
-- /reload. Recorded only while the debug addon is loaded (added 2026-11-27 to find a sort that never finished).
local TRACE_MAX = 600
function ns.SortTrace(...)
	if not Settings.DebugOn() then
		return
	end
	local db = DisorderItemManagerDB
	db.sortTrace = db.sortTrace or {}
	local parts = { ("%.2f"):format(GetTime()) }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	table.insert(db.sortTrace, table.concat(parts, " "))
	while #db.sortTrace > TRACE_MAX do
		table.remove(db.sortTrace, 1)
	end
end

-- Locked items get a red overlay (user, 2026-11-27): any bag item the game has locked (a move waiting for the game, an
-- item in use, or one left locked by a dropped move) gets a red overlay as soon as the game says so, and loses it
-- when it unlocks. A normal move flashes red for a moment; an item that stays red is stuck.
local hookedBags = {}

local function LockMark(button)
	local m = button.DisorderLockMark
	if m then
		return m
	end
	m = CreateFrame("Frame", nil, button)
	m:SetAllPoints(button)
	m:SetFrameLevel(button:GetFrameLevel() + 6) -- over the outlines, under Select Mode's catcher; takes no clicks
	m.tint = m:CreateTexture(nil, "OVERLAY", nil, 2)
	m.tint:SetAllPoints()
	m.tint:SetColorTexture(1, 0.1, 0.1, 0.45)
	button.DisorderLockMark = m
	return m
end

function Debug.RefreshLockMarks()
	local on = Settings.DebugOn()
	for _, f in ipairs(ns.Overlays.ContainerFrames()) do
		if f.EnumerateValidItems then
			if on and not hookedBags[f] and f.UpdateItems then
				hooksecurefunc(f, "UpdateItems", Debug.RefreshLockMarks) -- bag windows rebuild their buttons
				hookedBags[f] = true
			end
			for _, b in f:EnumerateValidItems() do
				local item = on and b and b.GetBagID and f:IsShown() and ns.Bags.ReadSlot(b:GetBagID(), b:GetID())
				if item and item.isLocked then
					LockMark(b):Show()
				elseif b and b.DisorderLockMark then
					b.DisorderLockMark:Hide()
				end
			end
		end
	end
end

-- The game reports every lock and unlock; redraw the overlays on the next frame (once, however many arrive).
local lockWatch = CreateFrame("Frame")
lockWatch:RegisterEvent("ITEM_LOCK_CHANGED")
lockWatch:RegisterEvent("BAG_UPDATE_DELAYED")
local lockRedrawPending = false
lockWatch:SetScript("OnEvent", function()
	if lockRedrawPending or not Settings.DebugOn() then
		return
	end
	lockRedrawPending = true
	C_Timer.After(0, function()
		lockRedrawPending = false
		Debug.RefreshLockMarks()
	end)
end)
Debug.lockWatch = lockWatch -- for dev/setup_check.lua

-- A sort's smoothness numbers are final a second after it ends (see Sort.lua); show them.
function ns.OnBenchRun()
	Debug.BenchRefresh()
end

-- Test bench (shown in the settings window's Testing tab) ------------------------------------
-- Seeded scrambles, so the same seed on the same sorted bag always makes the same mess, which makes
-- before/after comparisons fair:
--   Drift:   a few items leave their spot for the top of the gap, where loot lands: a hole plus an
--            arrival, the everyday case auto-sort really faces.
--   Minimal: swap a few items between the top and bottom thirds.
--   Full:    shuffle every normal-bag slot.
--   Maximal: reverse the whole order, then a few top/bottom swaps (worst case for a full sort).
-- Only the normal bags are scrambled. A one-line status text under the bag's search box shows what the
-- last sort cost (the debug addon loaded + "Status text"); the last 20 runs are kept in DisorderItemManagerDB.benchHistory.

local BENCH_MODES = { "Drift", "Minimal", "Full", "Maximal" }
Debug.BENCH_MODES = BENCH_MODES

-- Park-Miller generator: WoW's math.random can't be seeded. Returns a function giving 1..n.
local function SeededRandom(seed)
	local state = math.floor(math.abs(seed)) % 2147483647
	if state == 0 then
		state = 1
	end
	return function(n)
		state = state * 16807 % 2147483647
		return state % n + 1
	end
end

-- The scrambled layout for the normal bags: one item signature (or nil = empty) per slot.
local function ScrambleTargets(modeName, seed)
	local layout = {}
	for _, s in ipairs(ns.Bags.Read()) do
		if s.zone ~= "main" then
			break -- normal-bag slots come first
		end
		layout[#layout + 1] = s.item and s.item.sig or false
	end
	local n = #layout
	local roll = SeededRandom(seed)
	local function SwapEnds(count)
		local third = math.max(1, math.floor(n / 3))
		for _ = 1, count do
			local a, b = roll(third), n - roll(third) + 1
			layout[a], layout[b] = layout[b], layout[a]
		end
	end
	if modeName == "Drift" then
		-- Four different items move to the first empty slot (the top of the gap), each leaving a hole.
		local arrived = {}
		for _ = 1, 4 do
			local filled, empty = {}, nil
			for i = 1, n do
				if layout[i] and not arrived[i] then
					filled[#filled + 1] = i
				elseif not layout[i] and not empty then
					empty = i
				end
			end
			if not empty or #filled == 0 then
				break
			end
			local from = filled[roll(#filled)]
			layout[empty], layout[from] = layout[from], false
			arrived[empty] = true
		end
	elseif modeName == "Minimal" then
		SwapEnds(4)
	elseif modeName == "Full" then
		for i = n, 2, -1 do
			local j = roll(i)
			layout[i], layout[j] = layout[j], layout[i]
		end
	else
		for i = 1, math.floor(n / 2) do
			layout[i], layout[n - i + 1] = layout[n - i + 1], layout[i]
		end
		SwapEnds(4)
	end
	local targets = {}
	for i = 1, n do
		targets[i] = layout[i] or nil
	end
	return targets, n -- n travels separately: empty slots are nil, and # stops at a gap
end

local function RunLabel(run)
	return run.kind == "auto" and "Auto" or run.kind == "button" and "Button" or "Scramble"
end

-- One short line for the bag: what ran, moves, time, worst-second drop, worst frame.
local function BenchRunText(run)
	if not run then
		return L("AddonName") .. ": no sorts measured yet"
	end
	if not run.dropPct then
		return ("%s: %d moves, %.1fs"):format(RunLabel(run), run.moves, run.seconds)
	end
	return ("%s: %d moves, %.1fs, -%.0f%%, %.0fms"):format(
		RunLabel(run), run.moves, run.seconds, run.dropPct, run.worstMs)
end

-- The full detail, for the tooltip on the status text.
local function BenchRunTooltip(run)
	GameTooltip_SetTitle(GameTooltip, "Last sort: " .. RunLabel(run))
	GameTooltip_AddNormalLine(GameTooltip, ("%d moves in %d rounds, %.1f seconds"):format(
		run.moves, run.rounds, run.seconds))
	if run.dropPct then
		GameTooltip_AddNormalLine(GameTooltip, ("Worst second: -%.0f%% (%.0f fps, normally %.0f)"):format(
			run.dropPct, run.worstSecondFps, run.beforeFps))
		GameTooltip_AddNormalLine(GameTooltip, ("Hitches: %.1f per second"):format(run.hitchRate))
		GameTooltip_AddNormalLine(GameTooltip, ("Worst frame: %.0fms (normally %.0fms)"):format(
			run.worstMs, run.normalMs))
	end
end

-- The status text: one line in the strip between the bag's search box and its first row.
-- Shown with the bag while the debug addon is loaded and the Testing tab's "Status text"
-- checkbox is on (DisorderItemManagerDB.benchStatusText, on by default). Display only, just text.
local readout

local function Readout()
	if readout then
		return readout
	end
	local bag, search = ContainerFrameCombinedBags, BagItemSearchBox
	if not bag then
		return nil
	end
	readout = CreateFrame("Frame", nil, bag)
	readout:SetFrameLevel(bag:GetFrameLevel() + 20)
	readout:SetHeight(14)
	if search then
		readout:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -3)
	else
		readout:SetPoint("TOPLEFT", bag, "TOPLEFT", 12, -60)
	end
	readout:SetPoint("RIGHT", bag, "RIGHT", -60, 0) -- stop short of the slot at the top right
	readout.text = readout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	readout.text:SetPoint("LEFT", 4, 0)
	readout.text:SetPoint("RIGHT", -4, 0)
	readout.text:SetJustifyH("LEFT")
	readout.text:SetWordWrap(false) -- one line; anything too long is cut off, never wrapped
	readout:EnableMouse(true)
	readout:SetScript("OnEnter", function(self)
		local run = ns.Sort.lastRun or (DisorderItemManagerDB.benchHistory or {})[1]
		if run then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			BenchRunTooltip(run)
			GameTooltip:Show()
		end
	end)
	readout:SetScript("OnLeave", GameTooltip_Hide)
	readout:Hide()
	return readout
end

function Debug.BenchRefresh()
	local r = Readout()
	if r then
		if ns.Settings.DebugOn() and DisorderItemManagerDB.benchStatusText ~= false then
			r.text:SetText(BenchRunText(ns.Sort.lastRun or (DisorderItemManagerDB.benchHistory or {})[1]))
			r:Show()
		else
			r:Hide()
		end
	end
	ns.Settings.RefreshPage("Testing")
end

Debug.ScrambleTargets = ScrambleTargets
Debug.BenchRunText = BenchRunText


local function FormatWeight(w)
	return w == nil and "—" or tostring(w)
end

-- Every item in the bags with its class, subclass, quality, flags and weight, in chat; also saved to
-- DisorderItemManagerDB.lastScan for dev/sim.lua. The Debug group's Tools section has a button for it.
function ns.Scan()
	local rows = {}
	local slots = ns.Bags.Read()
	for _, s in ipairs(slots) do
		local item = s.item
		if item then
			item.weight, item.weightFrom = ns.Weights.Resolve(item)
			rows[#rows + 1] = item
			print(("  %d/%d %s x%d | %s(%d) > %s(%d) | q%s%s%s | w%s from %s"):format(
				item.bag, item.slot, item.link, item.count,
				item.className or "?", item.classID, item.subclassName or "?", item.subclassID,
				tostring(item.quality), item.isQuestItem and " QUEST" or "", item.isBound and " bound" or "",
				FormatWeight(item.weight), item.weightFrom))
		end
	end
	DisorderItemManagerDB.lastScan = { time = date("%Y-%m-%d %H:%M:%S"), rows = rows }
	Print(("%d items in %d sortable slots. /reload to write the scan to disk."):format(#rows, #slots))
end

local function BuildTestingPage(page)
	page.refreshers = {}
	local place = Flow(page)
	place(HelpText(page, "Scramble the bags with a seed (the same seed on the same sorted bag makes the same "
		.. "mess), close them, and let auto-sort clean up. Drift is the everyday case."), 0, 4, true)

	local modeButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	modeButton:SetSize(90, 22)
	place(modeButton, GAP_GROUP, 2)
	local function ShowMode()
		modeButton:SetText(DisorderItemManagerDB.benchMode or "Drift")
	end
	modeButton:SetScript("OnClick", function()
		local modes, current = ns.Debug.BENCH_MODES, DisorderItemManagerDB.benchMode or "Drift"
		for i, m in ipairs(modes) do
			if m == current then
				DisorderItemManagerDB.benchMode = modes[i % #modes + 1]
				break
			end
		end
		ShowMode()
	end)
	page.refreshers[#page.refreshers + 1] = ShowMode

	local seedLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	seedLabel:SetPoint("LEFT", modeButton, "RIGHT", 12, 0)
	seedLabel:SetText("Seed")
	local seedBox = NewBox(page, 50)
	seedBox:SetPoint("LEFT", seedLabel, "RIGHT", 8, 0)
	seedBox:SetNumeric(true)
	seedBox:SetMaxLetters(6)
	seedBox:SetScript("OnEnterPressed", seedBox.ClearFocus)
	seedBox:SetScript("OnEditFocusLost", function(self)
		DisorderItemManagerDB.benchSeed = tonumber(self:GetText()) or 42
		self:SetText(tostring(DisorderItemManagerDB.benchSeed))
	end)
	page.refreshers[#page.refreshers + 1] = function()
		if not seedBox:HasFocus() then
			seedBox:SetText(tostring(DisorderItemManagerDB.benchSeed or 42))
		end
	end

	local scramble = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	scramble:SetSize(90, 22)
	scramble:SetPoint("LEFT", seedBox, "RIGHT", 12, 0)
	scramble:SetText("Scramble")
	scramble:SetScript("OnClick", function()
		seedBox:ClearFocus()
		local seed = tonumber(seedBox:GetText()) or 42
		DisorderItemManagerDB.benchSeed = seed
		ns.Sort.Scramble(ns.Debug.ScrambleTargets(DisorderItemManagerDB.benchMode or "Drift", seed))
	end)

	CheckRow(page, place, GAP_GROUP, "Status text in the bag (last sort's cost)",
		function() return DisorderItemManagerDB.benchStatusText ~= false end,
		function(on) DisorderItemManagerDB.benchStatusText = on ns.Debug.BenchRefresh() end)

	place(Text(page, "GameFontNormal", "Recent sorts"), GAP_GROUP, 4)
	page.history = {}
	for i = 1, 10 do
		local line = place(Text(page, "GameFontHighlightSmall"), i == 1 and GAP_HELP or 4, 8, true)
		line:SetWordWrap(false)
		page.history[i] = line
	end
	page.refreshers[#page.refreshers + 1] = function()
		local history = DisorderItemManagerDB.benchHistory or {}
		for i, line in ipairs(page.history) do
			line:SetText(history[i] and ns.Debug.BenchRunText(history[i]) or " ")
		end
	end
end

-- Tools (debug addon): what used to be /sed commands, as buttons. Output goes to chat.
local function BuildToolsPage(page)
	page.refreshers = {}
	local place = Flow(page)
	local function Tool(label, help, run, gap)
		local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
		b:SetSize(160, 22)
		place(b, gap, 2)
		b:SetText(label)
		b:SetScript("OnClick", run)
		place(HelpText(page, help), GAP_HELP, 4, true)
		return b
	end
	page.status = Tool("Auto-sort status", "What auto-sort is waiting for, and what the last sort cost.",
		function() ns.AutoSort.Status() end, 0)
	page.scan = Tool("Scan bags", "Every item's class, subclass, quality, flags and weight, in chat; saved for "
		.. "dev/sim.lua after a /reload.", function() ns.Scan() end, GAP_GROUP)
	page.mute = Tool("Mute test", "Mutes the item pick-up and put-down sounds for 15 seconds, to check muting works.",
		function() ns.Sound.Test() end, GAP_GROUP)
	page.cancel = Tool("Cancel sort", "Stops a sort that's running.", function() ns.Sort.Cancel() end, GAP_GROUP)
	page.clearTrace = Tool("Clear sort trace", "Empties the sort trace (every step of every sort, kept for reading "
		.. "after a /reload).", function()
		DisorderItemManagerDB.sortTrace = nil
		Print("sort trace cleared.")
	end, GAP_GROUP)
end

-- Files (debug addon): the version the game read from the .toc, and every file Sediment expects with whether
-- it loaded (user, 2026-11-25: "how would I know if it worked?" after a /reload with a new file).
local function AddonVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	return get and get(ns.ADDON, "Version") or "?"
end

local function BuildFilesPage(page)
	page.refreshers = {}
	local place = Flow(page)
	local version = place(Text(page, "GameFontHighlight"), 0, 4, true)
	local summary = place(Text(page, "GameFontNormal"), GAP_GROUP, 4, true)
	place(HelpText(page, "Each file marks itself as it loads. A missing one usually means the game needs a full "
		.. "restart: a /reload may not pick up a file that's new to the addon."), GAP_HELP, 4, true)
	local lines = {}
	for i, file in ipairs(ns.FILES) do
		lines[i] = place(Text(page, "GameFontHighlight"), i == 1 and GAP_GROUP or 4, 12)
		lines[i].file = file
	end
	page.refreshers[#page.refreshers + 1] = function()
		version:SetText(("%s %s (the version in the .toc)"):format(L("AddonName"), AddonVersion()))
		local missing = #ns.MissingFiles()
		summary:SetText(missing == 0 and ("|cff66ff66All %d files loaded.|r"):format(#ns.FILES)
			or ("|cffff6666%d of %d files missing.|r"):format(missing, #ns.FILES))
		for _, line in ipairs(lines) do
			local ok = ns.loadedFiles[line.file]
			line:SetText(("%s   %s"):format(line.file, ok and "|cff66ff66loaded|r"
				or "|cffff6666missing (restart the game)|r"))
		end
	end
end

Settings.AddPage("Testing", { build = BuildTestingPage })
Settings.AddPage("Tools", { build = BuildToolsPage })
Settings.AddPage("Files", { build = BuildFilesPage })
