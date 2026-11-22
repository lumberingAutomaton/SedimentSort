-- Popup: Alt+right-click a bag item to see and edit its weight cascade.
--
-- Each level that applies to the item gets a box. Type a number and press Enter (or click away)
-- to set it; clear the box to make that level inherit. The winning level is marked.

local _, ns = ...
local Popup = {}
ns.Popup = Popup

local ROW_HEIGHT = 24
local WIDTH = 300
local WIN_COLOR = { 0.4, 1, 0.4 }
local NORMAL_COLOR = { 1, 0.82, 0 }
local DIM_COLOR = { 0.6, 0.6, 0.6 }

local frame
local rows = {}
local current -- { bag, slot }

local function FormatWeight(w)
	if w == nil then
		return ""
	end
	return tostring(w)
end

local function Build()
	frame = CreateFrame("Frame", "SedimentWeightPopup", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 100)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
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
	frame.hint:SetText("Enter a number to set a level. Clear it to inherit.")
	frame.hint:SetJustifyH("LEFT")

	frame.sortButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.sortButton:SetSize(90, 22)
	frame.sortButton:SetText("Sort now")
	frame.sortButton:SetScript("OnClick", function()
		ns.Sort.Start()
	end)

	frame:SetScript("OnHide", function()
		current = nil
	end)
end

-- Turn the text in a box into a value. Returns ok, value (value nil = clear).
local function ParseBox(text)
	text = strtrim(text or "")
	if text == "" then
		return true, nil
	end
	local n = tonumber(text)
	if n then
		return true, n
	end
	return false
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
	row.label:SetJustifyH("LEFT")

	row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.box:SetSize(60, 20)
	row.box:SetPoint("RIGHT", -40, 0)
	row.box:SetAutoFocus(false)
	row.box:SetMaxLetters(10)

	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.mark:SetPoint("LEFT", row.box, "RIGHT", 6, 0)

	local function Commit(box)
		if not row.level then
			return
		end
		local ok, value = ParseBox(box:GetText())
		local level = row.level
		if ok and (value ~= nil or (level.kind ~= "default" and level.kind ~= "sinkLine")) then
			ns.Weights.SetLevel(level.kind, level.key, value)
		end
		Popup.Refresh()
	end
	row.box:SetScript("OnEnterPressed", function(box)
		Commit(box)
		box:ClearFocus()
	end)
	row.box:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		Popup.Refresh()
	end)
	row.box:SetScript("OnEditFocusLost", Commit)

	rows[i] = row
	return row
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
	local weight = levels[winner].weight
	local sinkLine = ns.Weights.SinkLine()
	frame.summary:SetText(("Weight %s from %s: %s"):format(FormatWeight(weight), levels[winner].label,
		weight < sinkLine and "floats" or "sinks"))

	-- Rows: every level that applies to this item, then the sink line.
	local shown = {}
	for i, level in ipairs(levels) do
		if level.applies then
			shown[#shown + 1] = { level = level, wins = i == winner }
		end
	end
	shown[#shown + 1] = { level = { kind = "sinkLine", label = "Sink line", weight = sinkLine } }

	local y = -76
	for i, entry in ipairs(shown) do
		local row = GetRow(i)
		local level = entry.level
		row.level = level
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 12, y)
		row:Show()
		local label = level.label
		if level.kind == "subclass" or level.kind == "class" then
			label = label .. (level.kind == "subclass" and " |cff999999(subclass)|r" or " |cff999999(class)|r")
		end
		row.label:SetText(label)
		local color = entry.wins and WIN_COLOR or (level.kind == "sinkLine" and DIM_COLOR or NORMAL_COLOR)
		row.label:SetTextColor(unpack(color))
		row.mark:SetText(entry.wins and "|cff66ff66< wins|r" or "")
		if not row.box:HasFocus() then
			row.box:SetText(FormatWeight(level.weight))
			row.box:SetCursorPosition(0)
		end
		y = y - ROW_HEIGHT
		if level.kind == "default" then
			y = y - 6 -- a little space before the sink line
		end
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
		rows[i].level = nil
	end

	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", 12, y - 6)
	frame.hint:SetWidth(WIDTH - 24)
	frame.sortButton:ClearAllPoints()
	frame.sortButton:SetPoint("TOPRIGHT", -12, y - 24)
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
	if not frame:IsShown() then
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
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

-- Keep an open popup current when the item moves or the bags change.
function Popup.OnBagUpdate()
	if frame and frame:IsShown() then
		Popup.Refresh()
	end
end

-- Test bench ----------------------------------------------------------------------------------
-- A small dice button next to the bag sort button opens a tiny window: a mode button (Minimal,
-- Full, Maximal), a seed box and Scramble. Scrambles are seeded, so the same seed on the same
-- sorted bag always makes the same mess, which makes before/after comparisons fair:
--   Minimal: swap a few items between the top and bottom thirds (everyday drift).
--   Full:    shuffle every normal-bag slot.
--   Maximal: reverse the whole order, then a few top/bottom swaps (worst case for a full sort).
-- Only the normal bags are scrambled. The line underneath shows the last sort's cost; the last 20
-- runs are kept in SedimentDB.benchHistory.

local BENCH_MODES = { "Minimal", "Full", "Maximal" }
local bench

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
	if modeName == "Minimal" then
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

local function BenchRunText(run)
	if not run then
		return "No sorts measured yet."
	end
	return ("%s: %d moves, %d rounds, %.1fs\nworst frame %.0fms, %.0f fps (before %.0f)"):format(
		run.kind, run.moves, run.rounds, run.seconds, run.worstMs, run.fps, run.beforeFps)
end

local function BuildBench(anchor)
	bench = CreateFrame("Frame", "SedimentBench", UIParent, "BackdropTemplate")
	bench:SetSize(250, 112)
	bench:SetFrameStrata("DIALOG")
	bench:SetClampedToScreen(true)
	bench:SetMovable(true)
	bench:EnableMouse(true)
	bench:RegisterForDrag("LeftButton")
	bench:SetScript("OnDragStart", bench.StartMoving)
	bench:SetScript("OnDragStop", bench.StopMovingOrSizing)
	bench:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	bench:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	bench:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	bench:Hide()
	tinsert(UISpecialFrames, "SedimentBench")

	local title = bench:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("Sediment test bench")
	local close = CreateFrame("Button", nil, bench, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScale(0.8)

	local modeButton = CreateFrame("Button", nil, bench, "UIPanelButtonTemplate")
	modeButton:SetSize(76, 22)
	modeButton:SetPoint("TOPLEFT", 10, -28)
	local function ShowMode()
		modeButton:SetText(SedimentDB.benchMode or "Minimal")
	end
	modeButton:SetScript("OnClick", function()
		local current = SedimentDB.benchMode or "Minimal"
		for i, m in ipairs(BENCH_MODES) do
			if m == current then
				SedimentDB.benchMode = BENCH_MODES[i % #BENCH_MODES + 1]
				break
			end
		end
		ShowMode()
	end)
	modeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Scramble mode (click to change)")
		GameTooltip_AddNormalLine(GameTooltip, "Minimal: swap a few items between top and bottom.")
		GameTooltip_AddNormalLine(GameTooltip, "Full: shuffle everything.")
		GameTooltip_AddNormalLine(GameTooltip, "Maximal: reverse the order, then a few swaps.")
		GameTooltip:Show()
	end)
	modeButton:SetScript("OnLeave", GameTooltip_Hide)
	ShowMode()

	local seedBox = CreateFrame("EditBox", nil, bench, "InputBoxTemplate")
	seedBox:SetSize(46, 20)
	seedBox:SetPoint("LEFT", modeButton, "RIGHT", 12, 0)
	seedBox:SetAutoFocus(false)
	seedBox:SetNumeric(true)
	seedBox:SetMaxLetters(6)
	seedBox:SetText(tostring(SedimentDB.benchSeed or 42))
	seedBox:SetScript("OnEnterPressed", seedBox.ClearFocus)
	seedBox:SetScript("OnEscapePressed", seedBox.ClearFocus)
	seedBox:SetScript("OnEditFocusLost", function(self)
		SedimentDB.benchSeed = tonumber(self:GetText()) or 42
		self:SetText(tostring(SedimentDB.benchSeed))
	end)
	seedBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Seed")
		GameTooltip_AddNormalLine(GameTooltip, "The same seed on the same sorted bag always makes the same mess.")
		GameTooltip:Show()
	end)
	seedBox:SetScript("OnLeave", GameTooltip_Hide)

	local scramble = CreateFrame("Button", nil, bench, "UIPanelButtonTemplate")
	scramble:SetSize(80, 22)
	scramble:SetPoint("LEFT", seedBox, "RIGHT", 8, 0)
	scramble:SetText("Scramble")
	scramble:SetScript("OnClick", function()
		seedBox:ClearFocus()
		local seed = tonumber(seedBox:GetText()) or 42
		SedimentDB.benchSeed = seed
		ns.Sort.Scramble(ScrambleTargets(SedimentDB.benchMode or "Minimal", seed))
	end)

	bench.result = bench:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bench.result:SetPoint("TOPLEFT", modeButton, "BOTTOMLEFT", 0, -10)
	bench.result:SetPoint("RIGHT", -10, 0)
	bench.result:SetJustifyH("LEFT")
end

function Popup.BenchRefresh()
	if bench and bench:IsShown() then
		bench.result:SetText(BenchRunText(ns.Sort.lastRun or (SedimentDB.benchHistory or {})[1]))
	end
end

function Popup.ToggleBench(anchor)
	if not bench then
		BuildBench(anchor or UIParent)
	end
	bench:SetShown(not bench:IsShown())
	Popup.BenchRefresh()
end

-- The dice button, a child of the bag sort button so it shows and moves with it.
function Popup.CreateBenchButton()
	local sortButton = BagItemAutoSortButton
	if not sortButton or Popup.benchButton then
		return
	end
	local dice = CreateFrame("Button", nil, sortButton)
	dice:SetSize(20, 20)
	dice:SetPoint("RIGHT", sortButton, "LEFT", -2, 0)
	dice:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
	dice:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down")
	dice:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight", "ADD")
	dice:SetScript("OnClick", function(self)
		Popup.ToggleBench(self)
	end)
	dice:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Sediment test bench")
		GameTooltip_AddNormalLine(GameTooltip, "Scramble the bags to test a full cleanup.")
		GameTooltip:Show()
	end)
	dice:SetScript("OnLeave", GameTooltip_Hide)
	Popup.benchButton = dice
end
