-- Popup: Alt+right-click a bag item: what decides where it goes, and a way to give it a row of its own.
--
-- The levels that apply to the item, most specific first: the item, its flags (Equipment Set, Quest Items,
-- Gray Quality, BoE Gear), its group/part, its group, and "Not set" if nothing has a row. The winner (the
-- most specific level with a row in Order) is marked; levels above it, which could override it, get Add,
-- which puts that level's row right above the deciding row in Order; levels below it are dimmed (adding them
-- couldn't change this item). No numbers (user, 2026-11-25: Order replaced them).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Popup.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Popup = {}
ns.Popup = Popup
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)

local ROW_HEIGHT = 24
local WIDTH = 300
local WIN_COLOR = { 0.4, 1, 0.4 }
local NORMAL_COLOR = { 1, 0.82, 0 }
local DIM_COLOR = { 0.6, 0.6, 0.6 }

local frame
local rows = {}
local current -- { bag, slot }


local function Build()
	frame = CreateFrame("Frame", "SedimentWeightPopup", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 100)
	frame:SetFrameStrata("DIALOG") -- above the settings window (HIGH), so the two never interleave
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	-- Not draggable: it always opens above the bag (see Place).
	frame:SetBackdrop({
		-- A solid texture, like the settings window: the tooltip art is translucent, so text showed through.
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 1)
	frame:Hide()
	tinsert(UISpecialFrames, "SedimentWeightPopup") -- Escape closes it

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(28, 28)
	frame.icon:SetPoint("TOPLEFT", 12, -12)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
	frame.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
	frame.title:SetJustifyH("LEFT")

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.summary:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -8)
	frame.summary:SetPoint("RIGHT", -12, 0)
	frame.summary:SetJustifyH("LEFT")

	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.hint:SetText(B("AddLevelButton") .. " gives it a row; arrange rows in " .. N("OrderSection") .. ".")
	frame.hint:SetJustifyH("LEFT")

	frame.keepOutHeading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.keepOutHeading:SetText(L("KeepOutRule") .. ":")
	frame.keepOutHeading:Hide()
	local function KeepOutBox(tip)
		local box = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		box:SetSize(24, 24)
		box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
		box.label:SetJustifyH("LEFT")
		box.label:SetWordWrap(false)
		box:SetScript("OnClick", function(self)
			local on = self:GetChecked()
			ns.Bags.SetKeepOut(self.kind, self.key, on)
			if on then
				-- One or the other: ticking this one clears the other's rule.
				ns.Bags.SetKeepOut(self.other.kind, self.other.key, false)
			end
			ns.AutoSort.Resume()
			Popup.Refresh()
			if ns.Settings.RefreshSpecialList then
				ns.Settings.RefreshSpecialList() -- the Special bags section's list (the mouse is here, not there)
			end
			ns.Settings.Refresh()
		end)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip_SetTitle(GameTooltip, "Keep " .. self.label:GetText() .. " out of special bags")
			GameTooltip_AddNormalLine(GameTooltip, tip)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", GameTooltip_Hide)
		box:Hide()
		return box
	end
	frame.keepOutSub = KeepOutBox("Never move any of these into a reagent or profession bag. Ones already in one "
		.. "move back out (when there's room).")
	frame.keepOutItem = KeepOutBox("Never move this item (every stack of it) into a reagent or profession bag; "
		.. "the others like it still go in.")

	frame.settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.settingsButton:SetSize(80, 22)
	frame.settingsButton:SetText(L("OpenSettingsButton"))
	frame.settingsButton:SetScript("OnClick", function()
		ns.Settings.Open("Order")
		if frame.winner then
			ns.Order.Select(frame.winner.kind, frame.winner.key) -- the deciding row, selected and in view
		end
	end)

	frame:SetScript("OnHide", function()
		current = nil
	end)
end

local function GetRow(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, frame)
	row:SetSize(WIDTH - 24, ROW_HEIGHT)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT")
	row.label:SetPoint("RIGHT", -70, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.mark:SetPoint("RIGHT", -4, 0)
	row.add = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.add:SetSize(60, 20)
	row.add:SetPoint("RIGHT", 0, 0)
	row.add:SetText(L("AddLevelButton"))
	row.add:SetScript("OnClick", function()
		local level, item = row.level, row.item
		if level and item and ns.Weights.AddRuleAbove(level.kind, level.key, item) then
			ns.Settings.Refresh() -- the Order list, if open, and the outlines
			ns.Sort.StartSoon() -- show the outcome now, bags open or not
		end
		Popup.Refresh()
	end)
	rows[i] = row
	return row
end

-- A level's name in the popup: the item, a flag, "Armor/Cloth", "Armor", or "Not set".
local function LevelLabel(level)
	if level.kind == "default" then
		return "Not set"
	elseif level.kind == "item" then
		return level.label
	end
	return ns.Settings.RuleLabel(level.kind, level.key)
end

function Popup.Refresh()
	if not current or not frame:IsShown() then
		return
	end
	local item = ns.Bags.ReadSlot(current.bag, current.slot)
	if not item or item.itemID ~= current.itemID then
		-- The item moved (a sort, or the user). Follow it by item ID.
		item = nil
		for _, s in ipairs(ns.Bags.Read()) do
			if s.item and s.item.itemID == current.itemID then
				item = s.item
				current.bag, current.slot = s.bag, s.slot
				break
			end
		end
		if not item then
			frame:Hide()
			return
		end
	end

	local _, _, _, _, icon = C_Item.GetItemInfoInstant(item.itemID)
	frame.icon:SetTexture(icon)
	frame.title:SetText(item.link)

	local levels, winner = ns.Weights.Explain(item)
	local win = levels[winner]
	frame.winner = win
	if win.kind == "default" then
		frame.summary:SetText("Nothing set: it stays next to the " .. N("LootGap") .. ".")
	else
		-- The row's name as Order shows it (user, 2026-11-25): the Quest group sorts as "Quest Items".
		frame.summary:SetText("Sorted as " .. ns.Order.RowLabel(win.kind, win.key) .. ".")
	end

	-- Rows: every level that applies, most specific first; "Not set" only when it's the winner; a part named
	-- like its group ("Quest/Quest") only if it has a rule (else it's the group line again).
	local shown = {}
	for i, level in ipairs(levels) do
		local echo = level.kind == "subclass" and level.weight == nil and ns.Settings.PartSameAsGroup(level.key)
		if level.applies and (level.kind ~= "default" or i == winner) and not echo then
			shown[#shown + 1] = { level = level, wins = i == winner, above = i < winner }
		end
	end

	-- Rows start below the summary, however many lines it wrapped to (a long group name can take two).
	local y = -(48 + math.max(14, frame.summary:GetStringHeight()) + 14)
	for i, entry in ipairs(shown) do
		local row = GetRow(i)
		local level = entry.level
		row.level, row.item = level, item
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 12, y)
		row:Show()
		row.label:SetText(LevelLabel(level))
		local color = entry.wins and WIN_COLOR or entry.above and NORMAL_COLOR or DIM_COLOR
		row.label:SetTextColor(unpack(color))
		row.mark:SetText(entry.wins and "|cff66ff66< wins|r" or "")
		row.add:SetShown(entry.above) -- only levels that could override the winner
		y = y - ROW_HEIGHT
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
		rows[i].level, rows[i].item = nil, nil
	end

	-- "Keep out of special bags:" a heading, then two short checkboxes on one line: the whole subclass
	-- ("all Cloth", people think "my cloth") and this item ("Mageweave Cloth", every stack of it). The
	-- heading says what they mean once, so the labels stay short; a long item name is cut off rather than
	-- spilling out. They're mutually exclusive (one or the other, or neither). Shown only for items a special
	-- bag would take, or that are in one now.
	local inSpecial = false
	for _, sl in ipairs(ns.Bags.Read()) do
		if sl.bag == current.bag and sl.slot == current.slot then
			inSpecial = sl.zone ~= "main"
		end
	end
	if inSpecial or ns.Bags.SpecialBagItem(item) then
		local subOn = ns.Bags.KeepOutRule("subclass", item.subKey)
		local itemOn = ns.Bags.KeepOutRule("item", item.itemID) and not subOn
		frame.keepOutHeading:ClearAllPoints()
		frame.keepOutHeading:SetPoint("TOPLEFT", 12, y - 4)
		frame.keepOutHeading:Show()
		frame.keepOutSub.label:SetText("all " .. (item.subclassName or "like this"))
		frame.keepOutSub.kind, frame.keepOutSub.key = "subclass", item.subKey
		frame.keepOutSub.other = frame.keepOutItem
		frame.keepOutSub:SetChecked(subOn)
		frame.keepOutSub:ClearAllPoints()
		frame.keepOutSub:SetPoint("TOPLEFT", 8, y - 20)
		frame.keepOutSub:Show()
		frame.keepOutItem.label:SetText(item.name or "this item")
		frame.keepOutItem.kind, frame.keepOutItem.key = "item", item.itemID
		frame.keepOutItem.other = frame.keepOutSub
		frame.keepOutItem:SetChecked(itemOn)
		frame.keepOutItem:ClearAllPoints()
		frame.keepOutItem:SetPoint("LEFT", frame.keepOutSub.label, "RIGHT", 14, 0)
		frame.keepOutItem.label:SetWidth(math.max(40, WIDTH - 24 - (frame.keepOutSub.label:GetStringWidth() + 70)))
		frame.keepOutItem:Show()
		y = y - 46
	else
		frame.keepOutHeading:Hide()
		frame.keepOutSub:Hide()
		frame.keepOutItem:Hide()
	end

	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", 12, y - 6)
	frame.hint:SetWidth(WIDTH - 24)
	frame.settingsButton:ClearAllPoints()
	frame.settingsButton:SetPoint("TOPRIGHT", -12, y - 24)
	frame:SetHeight(-y + 56)
end

function Popup.Open(bag, slot)
	if not frame then
		Build()
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		return
	end
	current = { bag = bag, slot = slot, itemID = info.itemID }
	-- Always just above the bag window, left edges lined up (user, 2026-11-25), growing upward as rows are
	-- added. Clamped to the screen, so with the bag near the top it sits on the bag instead. No bag window
	-- (not expected: it opens from a bag click): next to the cursor.
	frame:ClearAllPoints()
	local bagWindow = ns.Settings.BagWindow()
	if bagWindow then
		frame:SetPoint("BOTTOMLEFT", bagWindow, "TOPLEFT", 0, 4)
	else
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / scale - 16, y / scale + 16)
	end
	frame:Show()
	Popup.Refresh()
end

-- Every modified click on a bag item calls HandleModifiedItemClick. Alt+right-click does nothing
-- there by default, so a post-hook is safe (no taint, Blizzard's own handling still runs).
function Popup.Hook()
	hooksecurefunc("HandleModifiedItemClick", function(link, itemLocation)
		if not (IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then
			return
		end
		if GetMouseButtonClicked and GetMouseButtonClicked() ~= "RightButton" then
			return
		end
		if not (itemLocation and itemLocation.IsBagAndSlot and itemLocation:IsBagAndSlot()) then
			return
		end
		Popup.Open(itemLocation:GetBagAndSlot())
	end)
end

function Popup.Close()
	if frame then
		frame:Hide()
	end
end

-- Keep an open popup current when the item moves or the bags change.
function Popup.OnBagUpdate()
	if frame and frame:IsShown() then
		Popup.Refresh()
	end
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
-- last sort cost (the debug addon loaded + "Status text"); the last 20 runs are kept in SedimentDB.benchHistory.

local BENCH_MODES = { "Drift", "Minimal", "Full", "Maximal" }
Popup.BENCH_MODES = BENCH_MODES

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
		return "Sediment: no sorts measured yet"
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
-- checkbox is on (SedimentDB.benchStatusText, on by default). Display only, just text.
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
		local run = ns.Sort.lastRun or (SedimentDB.benchHistory or {})[1]
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

function Popup.BenchRefresh()
	local r = Readout()
	if r then
		if ns.Settings.DebugOn() and SedimentDB.benchStatusText ~= false then
			r.text:SetText(BenchRunText(ns.Sort.lastRun or (SedimentDB.benchHistory or {})[1]))
			r:Show()
		else
			r:Hide()
		end
	end
	ns.Settings.RefreshTesting()
end

Popup.ScrambleTargets = ScrambleTargets
Popup.BenchRunText = BenchRunText

-- The bag button: a small icon left of the sort button (a child of it, so it shows and moves with
-- it) that opens the settings window on the Sorting tab. Picked in game (2026-11-24):
-- - Blizzard's button-style gear: people read a gear as "settings", and a button graphic has
--   transparent padding like the old dice, so it sits lightly where a full-square item icon looked heavy.
-- - 15 units, not 16: an empirical fit (16 looked about half a pixel low). The search bar is 18 units
--   tall, so not an odd/even centring issue; most likely its border art isn't centred in its frame, or
--   the UI scale's rounding onto screen pixels. Sizes are in UI units, so the gear scales with the bag
--   at any UI scale; at other scales the rounding may land half a pixel differently.
-- - Vertically centred on the search bar (the sort button sits a little lower), re-measured when shown
--   and whenever Blizzard repositions the sort button.
local ICON = "Interface\\Buttons\\UI-OptionsButton"
local ICON_SIZE = 15

function Popup.CreateBagButton()
	local sortButton = BagItemAutoSortButton
	if not sortButton or Popup.bagButton then
		return
	end
	-- Values left over from tuning the icon in game (/sed icon, nudge, iconsize, now removed).
	SedimentDB.bagIcon, SedimentDB.bagIconNudge, SedimentDB.bagIconSize, SedimentDB.bagIconVersion = nil, nil, nil, nil
	local b = CreateFrame("Button", nil, sortButton)
	b:SetSize(20, 20)
	b:SetPoint("RIGHT", sortButton, "LEFT", -2, 0)
	local function Align()
		local search = BagItemSearchBox
		local searchY, sortY
		if search and search:IsVisible() then
			searchY = select(2, search:GetCenter()) -- GetCenter returns x, y; "a and f()" would keep only x
		end
		sortY = select(2, sortButton:GetCenter())
		local dy = (searchY and sortY) and (searchY - sortY) or 0
		b:ClearAllPoints()
		b:SetPoint("RIGHT", sortButton, "LEFT", -2, dy)
	end
	b:SetScript("OnShow", function()
		Align()
		C_Timer.After(0, Align) -- again once the bag has finished laying itself out
	end)
	hooksecurefunc(sortButton, "SetPoint", function() C_Timer.After(0, Align) end)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON_SIZE, ICON_SIZE)
	b.icon:SetPoint("CENTER")
	b.icon:SetTexture(ICON)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnClick", function()
		ns.Settings.OpenDefault() -- the settings at Order
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Sediment settings")
		GameTooltip_AddNormalLine(GameTooltip, N("OrderSection") .. " and the other settings.")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	Popup.bagButton = b
	Popup.BenchRefresh() -- put the status text in the bag from the start, if it's on
end
