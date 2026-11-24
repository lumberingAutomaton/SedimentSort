-- Settings: the Sediment window. Opened with /sed, or the Settings button in the weight popup.
--
-- Ladder tab: every weight you've set (items, flags, subclasses, classes, the default), sorted light to
-- heavy, with the sink line drawn across at its value. Edit any number in place, or clear a rule with
-- the x. Under it, "Not set": the categories among your current bag items that fall through to the
-- default weight, with a box to give each one a weight. So you see what's set and what's missing.
-- General tab: auto-sort, its wait and speed, the default weight, the sink line, reset.
--
-- Numbers are still what's stored and edited. The ladder is laid out so it could become a ranking
-- (move rules between rungs instead of typing numbers) without changing anything underneath.

local _, ns = ...
local Settings = {}
ns.Settings = Settings

local WIDTH, HEIGHT = 470, 520
local ROW_HEIGHT = 22

local KIND_ORDER = { item = 1, flag = 2, subclass = 3, class = 4, default = 5 }
local KIND_LABEL = { item = "Item", flag = "Flag", subclass = "Subclass", class = "Class", default = "Default" }
local KIND_COLOR = {
	item = "ffd9b46a", flag = "ff9ad1ff", subclass = "ffb4e0a0", class = "ff8fd18f", default = "ffaaaaaa",
}
local FLOAT_COLOR = { 0.85, 0.85, 0.85 }
local SINK_COLOR = { 0.7, 0.6, 0.5 }

local frame, tabs, pages = nil, {}, {}
local ladderRows, ladderChild = {}, nil

local function FormatWeight(w)
	if w == nil then
		return ""
	end
	return tostring(w)
end

-- Something changed: refresh what's open and let auto-sort apply it once the bags are closed.
local function Changed()
	ns.Popup.Refresh()
	ns.AutoSort.Resume()
	Settings.Refresh()
end

-- Editing safety. The ladder re-sorts when a weight changes, so a row can change hands: the same row
-- frame then shows a different rule. A number box still focused across that used to save its stale
-- text onto the new rule (blank = remove), which silently removed two of the user's weights
-- (2026-11-24). Now: a box remembers which rule it was focused on and what it showed; it only saves
-- if it's still that rule and the text actually changed. Any focused box is finished before the ladder
-- re-sorts. Removing a rule doesn't re-sort at all: the row stays in place, greyed, with Undo.
local rebuilding = false        -- inside RefreshLadder: commits mustn't trigger another refresh
local committedWhileRebuilding = false
local lastRebuild = 0           -- clicks right after a re-sort are ignored (the list just moved)
local CLICK_GUARD = 0.3

local function EntryId(entry)
	return entry and (entry.kind .. ":" .. tostring(entry.key)) or nil
end

local function ItemLabel(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID) -- GET_ITEM_INFO_RECEIVED refreshes the panel
		name = "item " .. itemID
	end
	return name
end

local function ClassLabel(classID)
	return C_Item.GetItemClassInfo(classID) or ("class " .. classID)
end

local function SubclassLabel(key)
	local classID, subclassID = key:match("^(%-?%d+):(%-?%d+)$")
	classID, subclassID = tonumber(classID), tonumber(subclassID)
	local sub = classID and subclassID and C_Item.GetItemSubClassInfo(classID, subclassID)
	return ("%s (%s)"):format(sub or key, classID and ClassLabel(classID) or "?")
end

-- Every rule with a weight, as ladder entries: { kind, key, label, weight, icon }.
local function LadderEntries()
	local w = SedimentDB.weights
	local list = {}
	for itemID, weight in pairs(w.items) do
		list[#list + 1] = { kind = "item", key = itemID, label = ItemLabel(itemID), weight = weight,
			icon = C_Item.GetItemIconByID(itemID) }
	end
	for _, flag in ipairs(ns.Weights.FLAG_ORDER) do
		if w.flags[flag] ~= nil then
			list[#list + 1] = { kind = "flag", key = flag, label = ns.Weights.FlagLabel(flag), weight = w.flags[flag] }
		end
	end
	for key, weight in pairs(w.subclasses) do
		list[#list + 1] = { kind = "subclass", key = key, label = SubclassLabel(key), weight = weight }
	end
	for classID, weight in pairs(w.classes) do
		list[#list + 1] = { kind = "class", key = classID, label = ClassLabel(classID), weight = weight }
	end
	list[#list + 1] = { kind = "default", label = "Default (anything not set)", weight = w.default }
	table.sort(list, function(a, b)
		if a.weight ~= b.weight then
			return a.weight < b.weight
		end
		if KIND_ORDER[a.kind] ~= KIND_ORDER[b.kind] then
			return KIND_ORDER[a.kind] < KIND_ORDER[b.kind]
		end
		return a.label < b.label
	end)
	return list
end

-- Categories among the current bag items that fall through to the default weight: for each, the
-- class and the subclass, with how many items use the default because of it.
local function MissingEntries()
	local seen, list = {}, {}
	local function Add(kind, key, label)
		local e = seen[kind .. ":" .. key]
		if not e then
			e = { kind = kind, key = key, label = label, count = 0 }
			seen[kind .. ":" .. key] = e
			list[#list + 1] = e
		end
		e.count = e.count + 1
	end
	for _, s in ipairs(ns.Bags.Read()) do
		local item = s.item
		if item then
			local levels, winner = ns.Weights.Explain(item)
			if levels[winner].kind == "default" then
				Add("class", item.classID, ClassLabel(item.classID))
				Add("subclass", item.subKey, SubclassLabel(item.subKey))
			end
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.label < b.label
	end)
	return list
end

-- Rows ----------------------------------------------------------------------------------------

local function NewBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 54, 20)
	box:SetAutoFocus(false)
	box:SetMaxLetters(10)
	box:SetScript("OnEditFocusGained", function(self)
		self.startText = self:GetText()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(self.startText or self:GetText()) -- cancel: put back what it showed
		self:ClearFocus()
	end)
	return box
end

-- Parse a box: returns ok, value (nil = clear).
local function ParseBox(text)
	text = strtrim(text or "")
	if text == "" then
		return true, nil
	end
	local n = tonumber(text)
	return n ~= nil, n
end

local function GetRow(i)
	local row = ladderRows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, ladderChild)
	row:SetSize(WIDTH - 60, ROW_HEIGHT)

	row.box = NewBox(row)
	row.box:SetPoint("LEFT", 6, 0)
	row.box:SetScript("OnEditFocusGained", function(box)
		row.editId, row.editStart = EntryId(row.entry), box:GetText()
	end)
	local function Commit(box)
		local entry, editId, editStart = row.entry, row.editId, row.editStart
		row.editId, row.editStart = nil, nil
		if not entry or editId ~= EntryId(entry) or box:GetText() == editStart then
			-- Not an edit of this rule (the row changed hands, or nothing was typed): show its value.
			if entry and not row.removed then
				box:SetText(FormatWeight(entry.weight))
				box:SetCursorPosition(0)
			end
			return
		end
		local ok, value = ParseBox(box:GetText())
		if ok and (value ~= nil or (entry.kind ~= "default" and entry.kind ~= "sinkLine")) then
			ns.Weights.SetLevel(entry.kind, entry.key, value)
		end
		if rebuilding then
			committedWhileRebuilding = true
		else
			Changed()
		end
	end
	row.box:SetScript("OnEnterPressed", function(box)
		box:ClearFocus() -- saves through OnEditFocusLost
	end)
	row.box:SetScript("OnEscapePressed", function(box)
		box:SetText(row.editStart or box:GetText()) -- cancel: unchanged text saves nothing
		box:ClearFocus()
	end)
	row.box:SetScript("OnEditFocusLost", Commit)

	row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.kind:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
	row.kind:SetWidth(58)
	row.kind:SetJustifyH("LEFT")

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row.kind, "RIGHT", 2, 0)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)

	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(20, 20)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetScript("OnClick", function()
		local entry = row.entry
		if GetTime() - lastRebuild < CLICK_GUARD or row.removed then
			return
		end
		if entry and entry.kind ~= "default" and entry.kind ~= "sinkLine" and not entry.missing then
			if row.box:HasFocus() then
				row.box:SetText(row.editStart or row.box:GetText())
				row.box:ClearFocus()
			end
			ns.Weights.SetLevel(entry.kind, entry.key, nil)
			Settings.ShowRemoved(row)
			ns.Popup.Refresh()
			ns.AutoSort.Resume() -- no ladder re-sort: nothing moves under the mouse
		end
	end)

	-- Shown in place of x on a removed row; puts the rule back.
	row.undo = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.undo:SetSize(52, 18)
	row.undo:SetPoint("RIGHT", -2, 0)
	row.undo:SetText("Undo")
	row.undo:Hide()
	row.undo:SetScript("OnClick", function()
		local entry = row.entry
		if entry and row.removed then
			ns.Weights.SetLevel(entry.kind, entry.key, entry.weight)
			row.removed = nil
			Settings.ShowEntryRow(row, entry, row.y)
			ns.Popup.Refresh()
			ns.AutoSort.Resume()
		end
	end)

	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetHeight(2)
	row.line:SetColorTexture(0.9, 0.6, 0.2, 0.9)

	ladderRows[i] = row
	return row
end

local function ShowEntryRow(row, entry, y)
	row.entry, row.y, row.removed = entry, y, nil
	row.undo:Hide()
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, y)
	row:Show()
	row.box:SetText(FormatWeight(entry.weight)) -- no box is focused here: RefreshLadder finished any edit
	row.box:SetCursorPosition(0)
	row.box:Show()
	row.line:Hide()
	row.label:ClearAllPoints()
	if entry.kind == "sinkLine" then
		row.kind:SetText("|cffffb040Sink line|r")
		row.icon:Hide()
		row.label:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
		row.label:SetPoint("RIGHT", -6, 0)
		row.label:SetText("")
		row.line:ClearAllPoints()
		row.line:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
		row.line:SetPoint("RIGHT", -6, 0)
		row.line:Show()
		row.remove:Hide()
		return
	end
	row.kind:SetText(("|c%s%s|r"):format(KIND_COLOR[entry.kind] or "ffffffff", KIND_LABEL[entry.kind] or entry.kind))
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:Show()
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	else
		row.icon:Hide()
		row.label:SetPoint("LEFT", row.kind, "RIGHT", 4, 0)
	end
	row.label:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
	local text = entry.label
	if entry.missing then
		text = ("%s |cff888888(%d item%s)|r"):format(entry.label, entry.count, entry.count == 1 and "" or "s")
	end
	row.label:SetText(text)
	local color = entry.sinks and SINK_COLOR or FLOAT_COLOR
	row.label:SetTextColor(color[1], color[2], color[3])
	row.remove:SetShown(entry.kind ~= "default" and not entry.missing)
end
Settings.ShowEntryRow = ShowEntryRow

-- A just-removed rule: greyed, in place, with Undo instead of x. It goes away at the next re-sort.
function Settings.ShowRemoved(row)
	row.removed = true
	row.box:Hide()
	row.remove:Hide()
	row.undo:Show()
	row.label:SetText(row.entry.label .. " |cff888888(removed)|r")
	row.label:SetTextColor(0.5, 0.5, 0.5)
end

local function ShowHeadingRow(row, text, y)
	row.entry, row.removed = nil, nil
	row.undo:Hide()
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, y)
	row:Show()
	row.box:Hide()
	row.icon:Hide()
	row.remove:Hide()
	row.line:Hide()
	row.kind:SetText("")
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", 6, 0)
	row.label:SetPoint("RIGHT", -6, 0)
	row.label:SetText(text)
	row.label:SetTextColor(1, 0.82, 0)
end

function Settings.RefreshLadder()
	if not ladderChild then
		return
	end
	-- Finish any edit in progress first, while each box is still on its own rule.
	rebuilding, committedWhileRebuilding = true, false
	for _, r in ipairs(ladderRows) do
		if r.box:HasFocus() then
			r.box:ClearFocus()
		end
	end
	rebuilding = false
	if committedWhileRebuilding then
		ns.Popup.Refresh()
		ns.AutoSort.Resume()
	end
	lastRebuild = GetTime()
	local sinkLine = ns.Weights.SinkLine()
	local entries = LadderEntries()
	local i, y = 0, 0
	local function Next()
		i = i + 1
		local row = GetRow(i)
		local thisY = y
		y = y - ROW_HEIGHT
		return row, thisY
	end
	local sinkShown = false
	for _, entry in ipairs(entries) do
		if not sinkShown and entry.weight >= sinkLine then
			local row, ry = Next()
			ShowEntryRow(row, { kind = "sinkLine", weight = sinkLine }, ry)
			sinkShown = true
		end
		entry.sinks = entry.weight >= sinkLine
		local row, ry = Next()
		ShowEntryRow(row, entry, ry)
	end
	if not sinkShown then
		local row, ry = Next()
		ShowEntryRow(row, { kind = "sinkLine", weight = sinkLine }, ry)
	end

	local missing = MissingEntries()
	y = y - 8
	local row, ry = Next()
	if #missing == 0 then
		ShowHeadingRow(row, "Not set: nothing. Every item in your bags has a weight of its own.", ry)
	else
		ShowHeadingRow(row, ("Not set: these use the default (%s). Give one a weight:"):format(
			FormatWeight(SedimentDB.weights.default)), ry)
		for _, entry in ipairs(missing) do
			entry.missing = true
			local r, ey = Next()
			ShowEntryRow(r, entry, ey)
		end
	end
	for k = i + 1, #ladderRows do
		ladderRows[k]:Hide()
		ladderRows[k].entry = nil
	end
	ladderChild:SetHeight(-y + 4)
end

-- Pages ---------------------------------------------------------------------------------------

local function BuildLadderPage(page)
	local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", 4, 0)
	hint:SetPoint("RIGHT", -4, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Light at the top, heavy at the bottom. Edit a number and press Enter; x clears a rule. "
		.. "Item weights are added with Alt+right-click on an item.")

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -30)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	ladderChild = CreateFrame("Frame", nil, scroll)
	ladderChild:SetSize(WIDTH - 60, 100)
	scroll:SetScrollChild(ladderChild)
end

local function LabeledBox(page, y, label, help, get, set)
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOPLEFT", 4, y)
	text:SetText(label)
	local box = NewBox(page, 60)
	box:SetPoint("TOPLEFT", 220, y + 3)
	local helpText = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	helpText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
	helpText:SetPoint("RIGHT", page, "RIGHT", -8, 0)
	helpText:SetJustifyH("LEFT")
	helpText:SetText(help)
	local function Commit(self)
		local n = tonumber(self:GetText())
		if n then
			set(n)
			Changed()
		end
		self:SetText(FormatWeight(get()))
	end
	box:SetScript("OnEnterPressed", function(self)
		Commit(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Commit)
	page.refreshers[#page.refreshers + 1] = function()
		if not box:HasFocus() then
			box:SetText(FormatWeight(get()))
		end
	end
end

StaticPopupDialogs["SEDIMENT_RESET_WEIGHTS"] = {
	text = "Reset all Sediment weights to the starter set? Your edits will be lost.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.Weights.ResetToPreset()
		Changed()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function BuildGeneralPage(page)
	page.refreshers = {}
	local auto = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	auto:SetSize(24, 24)
	auto:SetPoint("TOPLEFT", 0, 0)
	auto:SetScript("OnClick", function()
		ns.AutoSort.Toggle()
	end)
	local autoText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	autoText:SetPoint("LEFT", auto, "RIGHT", 4, 0)
	autoText:SetText("Sort automatically while the bags are closed")
	page.refreshers[#page.refreshers + 1] = function()
		auto:SetChecked(ns.AutoSort.IsEnabled())
	end

	LabeledBox(page, -40, "Wait after changes (seconds)",
		"How long the bags must be quiet before auto-sort starts. Longer lets a burst of looting finish "
		.. "and new quest items register.",
		ns.AutoSort.Delay, function(n) SedimentDB.autoSortDelay = math.max(0, math.min(30, n)) end)
	LabeledBox(page, -96, "Speed (lower = smoother)",
		"How much time per frame auto-sort may spend moving items, in milliseconds. Lower spreads a sort "
		.. "over longer and keeps the frame rate steadier. The sort button always goes full speed.",
		ns.Sort.BudgetMs, function(n) SedimentDB.streamBudgetMs = math.max(0.01, math.min(50, n)) end)
	LabeledBox(page, -164, "Sink line",
		"Items lighter than this float to the top of the bags; this heavy or heavier sink to the bottom.",
		ns.Weights.SinkLine, function(n) ns.Weights.SetLevel("sinkLine", nil, n) end)
	LabeledBox(page, -220, "Default weight",
		"The weight of anything with no item, flag, subclass or class weight of its own.",
		function() return SedimentDB.weights.default end, function(n) ns.Weights.SetLevel("default", nil, n) end)

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetSize(170, 24)
	reset:SetPoint("TOPLEFT", 4, -290)
	reset:SetText("Reset to starter weights")
	reset:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_RESET_WEIGHTS")
	end)
end

local function ShowTab(name)
	for key, page in pairs(pages) do
		page:SetShown(key == name)
	end
	for key, tab in pairs(tabs) do
		if key == name then
			tab:LockHighlight()
		else
			tab:UnlockHighlight()
		end
	end
	Settings.Refresh()
end

local function Build()
	frame = CreateFrame("Frame", "SedimentSettings", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
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
	frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
	frame:Hide()
	tinsert(UISpecialFrames, "SedimentSettings")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Sediment")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local x = 110
	for _, name in ipairs({ "Ladder", "General" }) do
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetSize(80, 22)
		tab:SetPoint("TOPLEFT", x, -10)
		tab:SetText(name)
		tab:SetScript("OnClick", function()
			ShowTab(name)
		end)
		tabs[name] = tab
		x = x + 84

		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 14, -42)
		page:SetPoint("BOTTOMRIGHT", -12, 12)
		page:Hide()
		pages[name] = page
	end
	BuildLadderPage(pages.Ladder)
	BuildGeneralPage(pages.General)
	frame:SetScript("OnShow", function()
		Settings.Refresh()
	end)
	ShowTab("Ladder")
end

function Settings.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	if pages.Ladder:IsShown() then
		Settings.RefreshLadder()
	end
	if pages.General:IsShown() then
		for _, f in ipairs(pages.General.refreshers) do
			f()
		end
	end
end

-- Item names that weren't loaded yet: relabel in place.
function Settings.RefreshNames()
	if not frame or not frame:IsShown() then
		return
	end
	for _, row in ipairs(ladderRows) do
		local entry = row.entry
		if row:IsShown() and entry and entry.kind == "item" and not row.removed then
			entry.label = ItemLabel(entry.key)
			row.label:SetText(entry.label)
		end
	end
end

function Settings.Toggle()
	if not frame then
		Build()
	end
	frame:SetShown(not frame:IsShown())
end

function Settings.Open()
	if not frame then
		Build()
	end
	frame:Show()
end
