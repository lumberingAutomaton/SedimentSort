-- Popup: Alt+right-click a bag item: what decides where it goes, and a way to give it a row of its own.
--
-- The levels that apply to the item, most specific first: the item, its flags (Equipment Set, Quest Items,
-- Gray Quality, BoE Gear), its group/part, its group, and "Not set" if nothing has a row. The winner (the
-- most specific level with a row in Order) is marked; levels above it, which could override it, get Add,
-- which puts that level's row right above the deciding row in Order; levels below it are dimmed (adding them
-- couldn't change this item). No numbers (user, 2026-11-25: Order replaced them).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Popup.lua"] = true -- see ns.FILES (Core.lua) and the Files section
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
	frame = CreateFrame("Frame", "DisorderItemManagerPopup", UIParent, "BackdropTemplate")
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
	tinsert(UISpecialFrames, "DisorderItemManagerPopup") -- Escape closes it

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
			if ns.Options.RefreshSpecialList then
				ns.Options.RefreshSpecialList() -- the Special bags section's list (the mouse is here, not there)
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
