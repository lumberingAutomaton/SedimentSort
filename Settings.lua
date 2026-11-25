-- Settings: the Sediment window. Opened with the button left of the bag's sort button (Sorting tab),
-- /sed, or the Settings button in the weight popup (Weights tab). It closes in combat.
--
-- Weights tab: select mode (click bag items to set their weights), and the ladder: every weight you've set (items, flags, subclasses, classes, the default), sorted light to
-- heavy, with the sink line drawn across at its value. Edit any number in place, or clear a rule with
-- the x. Under it, "Not set": the categories among your current bag items that fall through to the
-- default weight, with a box to give each one a weight. So you see what's set and what's missing.
-- Sorting tab: auto-sort on/off, its order, wait, smoothness, what happens if the bags open mid-sort, and
-- "Debug mode", which reveals the Testing tab (seeded scrambles, status text, recent sorts) and the
-- Commands tab (every /sed command). A welcome screen explains the idea when the window opens, until
-- "Don't show this again"; the ? next to the title brings it back.
--
-- Numbers are still what's stored and edited. The ladder is laid out so it could become a ranking
-- (move rules between rungs instead of typing numbers) without changing anything underneath.

local _, ns = ...
local Settings = {}
ns.Settings = Settings
local Print = function(msg) ns.Print(msg) end

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

-- Select mode ---------------------------------------------------------------------------------
-- On the Weights tab: while it's on, every bag slot gets a light highlight and its current weight, and
-- clicking an item opens its weight popup (clicking the next item switches to it). The clicks land on
-- Sediment's own catcher frames laid over the slots (children of the item buttons, so they move and
-- hide with them); Blizzard's item buttons are never changed, so nothing is tainted. While it's on, a
-- plain click can't use or pick up an item. Turning it on opens the bags; ending it leaves them open. It
-- ends when toggled off, when the window closes, and when combat starts (all
-- Sediment windows close then, so a potion always works when it matters).

local selecting = false
local hookedFrames = {}
local DEFAULT_COLOR = { 1, 0.55, 0.1 } -- weight number for items using the default (nothing set)
local SET_COLOR = { 1, 1, 1 }

-- Every bag window: the combined backpack, the numbered ones, and anything else in Blizzard's own list
-- (the reagent bag's window among them), without duplicates.
local function ContainerFrames()
	local list, seen = {}, {}
	local function Add(f)
		if f and not seen[f] then
			seen[f] = true
			list[#list + 1] = f
		end
	end
	Add(ContainerFrameCombinedBags)
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		Add(_G["ContainerFrame" .. i])
	end
	if ContainerFrameContainer and ContainerFrameContainer.ContainerFrames then
		for _, f in ipairs(ContainerFrameContainer.ContainerFrames) do
			Add(f)
		end
	end
	return list
end

local function Catcher(button)
	local c = button.SedimentSelect
	if c then
		return c
	end
	c = CreateFrame("Button", nil, button)
	c:SetAllPoints(button)
	c:SetFrameLevel(button:GetFrameLevel() + 10)
	c:RegisterForClicks("AnyUp")
	c.glow = c:CreateTexture(nil, "OVERLAY")
	c.glow:SetAllPoints()
	c.glow:SetColorTexture(0.3, 0.7, 1, 0.16)
	c.weight = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	c.weight:SetPoint("TOPLEFT", 2, -2)
	c:SetScript("OnClick", function(self)
		local b = self:GetParent()
		ns.Popup.Open(b:GetBagID(), b:GetID())
	end)
	c:SetScript("OnEnter", function(self)
		local b = self:GetParent()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(b:GetBagID(), b:GetID())
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", GameTooltip_Hide)
	button.SedimentSelect = c
	return c
end

function Settings.RefreshOverlays()
	for _, f in ipairs(ContainerFrames()) do
		if f.EnumerateValidItems then
			if selecting and not hookedFrames[f] and f.UpdateItems then
				-- Bag windows rebuild their buttons as they open and change; follow along.
				hooksecurefunc(f, "UpdateItems", Settings.RefreshOverlays)
				hookedFrames[f] = true
			end
			-- Every bag window, the reagent bag's included. A window's slot list can run past the buttons
			-- it has (a closed window keeps its old size), so skip empty entries rather than stop: an
			-- error here used to end the loop before it reached the reagent bag.
			for _, b in f:EnumerateValidItems() do
				local c = b and b.SedimentSelect
				local item = b and selecting and f:IsShown() and b.GetBagID
					and ns.Bags.ReadSlot(b:GetBagID(), b:GetID())
				if item then
					c = Catcher(b)
					local levels, winner = ns.Weights.Explain(item)
					c.weight:SetText(FormatWeight(levels[winner].weight))
					local color = levels[winner].kind == "default" and DEFAULT_COLOR or SET_COLOR
					c.weight:SetTextColor(color[1], color[2], color[3])
					c:Show()
				elseif c then
					c:Hide()
				end
			end
		end
	end
end

function Settings.IsSelecting()
	return selecting
end

function Settings.SetSelectMode(on)
	if on and InCombatLockdown() then
		Print("not in combat.")
		on = false
	end
	local was = selecting
	selecting = on and true or false
	Settings.RefreshOverlays() -- hooks the bag windows first, so opening them below refreshes the overlays
	-- Starting select mode opens the bags (no change if they're open). Ending it leaves them as they are
	-- (user: turning select mode off shouldn't close the bags).
	if selecting and not was then
		OpenAllBags()
		C_Timer.After(0, Settings.RefreshOverlays)
	end
	if Settings.selectButton then
		Settings.selectButton:SetText(selecting and "Select mode: on" or "Select mode: off")
	end
end

-- Combat: close every Sediment window and end select mode, so nothing of ours can catch a click.
function Settings.OnCombat()
	Settings.SetSelectMode(false)
	if frame then
		frame:Hide()
	end
	ns.Popup.Close()
end

-- Pages ---------------------------------------------------------------------------------------

local function HelpText(page, anchor, text)
	local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
	help:SetPoint("RIGHT", page, "RIGHT", -8, 0)
	help:SetJustifyH("LEFT")
	help:SetText(text)
	return help
end

local function BuildWeightsPage(page)
	page.refreshers = {}
	local selectButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	selectButton:SetSize(170, 22)
	selectButton:SetPoint("TOPLEFT", 2, 0)
	selectButton:SetScript("OnClick", function()
		Settings.SetSelectMode(not selecting)
	end)
	Settings.selectButton = selectButton
	local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", selectButton, "RIGHT", 8, 0)
	hint:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("Turn it on, then click items in your bags to set their weights. Orange numbers use the default.")
	page.refreshers[#page.refreshers + 1] = function()
		selectButton:SetText(selecting and "Select mode: on" or "Select mode: off")
	end

	local ladderHint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	ladderHint:SetPoint("TOPLEFT", selectButton, "BOTTOMLEFT", 2, -6)
	ladderHint:SetPoint("RIGHT", -4, 0)
	ladderHint:SetJustifyH("LEFT")
	ladderHint:SetText("Light at the top, heavy at the bottom. Edit a number and press Enter; x removes a rule.")

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -46)
	scroll:SetPoint("BOTTOMRIGHT", -26, 34)
	ladderChild = CreateFrame("Frame", nil, scroll)
	ladderChild:SetSize(WIDTH - 60, 100)
	scroll:SetScrollChild(ladderChild)

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetSize(170, 24)
	reset:SetPoint("BOTTOMLEFT", 2, 2)
	reset:SetText("Reset to starter weights")
	reset:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_RESET_WEIGHTS")
	end)
end

local function LabeledBox(page, y, label, help, get, set)
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOPLEFT", 4, y)
	text:SetText(label)
	local box = NewBox(page, 60)
	box:SetPoint("TOPLEFT", 240, y + 3)
	HelpText(page, text, help)
	local function Commit(self)
		local n = tonumber(self:GetText())
		if n then
			set(n)
			Changed()
		end
		self:SetText(FormatWeight(get()))
	end
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Commit)
	page.refreshers[#page.refreshers + 1] = function()
		if not box:HasFocus() then
			box:SetText(FormatWeight(get()))
		end
	end
end

-- A label with a button that cycles through choices, and help text that follows the choice.
local function ChoiceRow(page, y, label, width, get, set, choices)
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("TOPLEFT", 4, y)
	text:SetText(label)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetPoint("TOPLEFT", 240, y + 4)
	local help = HelpText(page, text, "")
	local function Show()
		local current = get()
		for _, c in ipairs(choices) do
			if c.value == current then
				button:SetText(c.label)
				help:SetText(c.help)
			end
		end
	end
	button:SetScript("OnClick", function()
		local current = get()
		for i, c in ipairs(choices) do
			if c.value == current then
				set(choices[i % #choices + 1].value)
				break
			end
		end
		Show()
	end)
	page.refreshers[#page.refreshers + 1] = Show
end

local function CheckRow(page, y, label, get, set)
	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", 0, y)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("LEFT", check, "RIGHT", 4, 0)
	text:SetText(label)
	page.refreshers[#page.refreshers + 1] = function()
		check:SetChecked(get())
	end
	return check, text
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

local ShowTab -- defined below

local function BuildSortingPage(page)
	page.refreshers = {}
	CheckRow(page, 0, "Sort automatically while the bags are closed", ns.AutoSort.IsEnabled, function(on)
		if on ~= ns.AutoSort.IsEnabled() then
			ns.AutoSort.Toggle()
		end
	end)
	ChoiceRow(page, -36, "Auto-sort order", 100,
		function() return SedimentDB.autoOrder or "partial" end,
		function(v) SedimentDB.autoOrder = v ns.AutoSort.Resume() end, {
			{ value = "partial", label = "Partial", help = "Only what the weights require: items of equal "
				.. "weight keep their order, identical stacks stay together. Fewest moves." },
			{ value = "full", label = "Full", help = "The exact order, the same as the sort button. More "
				.. "moves, but every item always has the same spot." },
		})
	LabeledBox(page, -96, "Wait after changes (seconds)",
		"How long the bags must be quiet before auto-sort starts. Long enough for a burst of looting to "
		.. "finish and new quest items to register.",
		ns.AutoSort.Delay, function(n) SedimentDB.autoSortDelay = math.max(0, math.min(30, n)) end)
	LabeledBox(page, -152, "Smoothness (ms per frame)",
		"How much time per frame, on average, auto-sort may spend moving items. Lower is smoother but "
		.. "slower. The sort button always goes full speed.",
		ns.Sort.BudgetMs, function(n) SedimentDB.streamBudgetMs = math.max(0.01, math.min(50, n)) end)
	local _, fillText = CheckRow(page, -276, "Fill reagent and profession bags automatically",
		ns.Bags.FillSpecialBags, function(on)
			SedimentDB.fillSpecialBags = on and nil or false
			ns.AutoSort.Resume()
		end)
	HelpText(page, fillText, "Off: Sediment never moves anything into those bags; what's already in them stays "
		.. "and is still sorted there. To keep single items out, Alt+right-click them.")
	ChoiceRow(page, -212, "If the bags open during an auto-sort", 100,
		ns.Sort.OpenBagsMode, function(v) SedimentDB.openBags = v end, {
			{ value = "pause", label = "Pause", help = "Nothing moves while the bags are open; the sort "
				.. "carries on once they close." },
			{ value = "finish", label = "Finish now", help = "Everything left goes out at once, so the bag "
				.. "settles within about half a second of opening. Expect a short stutter." },
		})
	local _, debugText = CheckRow(page, -340, "Debug mode",
		function() return SedimentDB.testingTools and true or false end,
		function(on)
			SedimentDB.testingTools = on
			tabs.Testing:SetShown(on)
			tabs.Commands:SetShown(on)
			ns.Popup.BenchRefresh()
		end)
	HelpText(page, debugText, "Adds the Testing tab (seeded scrambles, recent sorts, a status line in the bag) and "
		.. "the Commands tab (every /sed command).")
end

local function BuildTestingPage(page)
	page.refreshers = {}
	local intro = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", 4, 0)
	intro:SetPoint("RIGHT", -4, 0)
	intro:SetJustifyH("LEFT")
	intro:SetText("Scramble the bags with a seed (the same seed on the same sorted bag makes the same mess), "
		.. "close them, and let auto-sort clean up. Drift is the everyday case.")

	local modeButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	modeButton:SetSize(90, 22)
	modeButton:SetPoint("TOPLEFT", 2, -34)
	local function ShowMode()
		modeButton:SetText(SedimentDB.benchMode or "Drift")
	end
	modeButton:SetScript("OnClick", function()
		local modes, current = ns.Popup.BENCH_MODES, SedimentDB.benchMode or "Drift"
		for i, m in ipairs(modes) do
			if m == current then
				SedimentDB.benchMode = modes[i % #modes + 1]
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
		SedimentDB.benchSeed = tonumber(self:GetText()) or 42
		self:SetText(tostring(SedimentDB.benchSeed))
	end)
	page.refreshers[#page.refreshers + 1] = function()
		if not seedBox:HasFocus() then
			seedBox:SetText(tostring(SedimentDB.benchSeed or 42))
		end
	end

	local scramble = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	scramble:SetSize(90, 22)
	scramble:SetPoint("LEFT", seedBox, "RIGHT", 12, 0)
	scramble:SetText("Scramble")
	scramble:SetScript("OnClick", function()
		seedBox:ClearFocus()
		local seed = tonumber(seedBox:GetText()) or 42
		SedimentDB.benchSeed = seed
		ns.Sort.Scramble(ns.Popup.ScrambleTargets(SedimentDB.benchMode or "Drift", seed))
	end)

	CheckRow(page, -66, "Status text in the bag (last sort's cost)",
		function() return SedimentDB.benchStatusText ~= false end,
		function(on) SedimentDB.benchStatusText = on ns.Popup.BenchRefresh() end)

	local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 4, -100)
	heading:SetText("Recent sorts")
	page.history = {}
	for i = 1, 10 do
		local line = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line:SetPoint("TOPLEFT", 8, -100 - i * 16)
		line:SetPoint("RIGHT", -4, 0)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		page.history[i] = line
	end
	page.refreshers[#page.refreshers + 1] = function()
		local history = SedimentDB.benchHistory or {}
		for i, line in ipairs(page.history) do
			line:SetText(history[i] and ns.Popup.BenchRunText(history[i]) or "")
		end
	end
end

-- Commands tab (debug mode): every /sed command and the mouse shortcuts, from the same lists /sed help
-- uses (ns.COMMANDS, ns.SHORTCUTS in Sediment.lua).
local function BuildCommandsPage(page)
	local last
	local function Line(template, text, gap)
		local fs = page:CreateFontString(nil, "OVERLAY", template)
		if last then
			fs:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(gap or 4))
		else
			fs:SetPoint("TOPLEFT", 4, 0)
		end
		fs:SetPoint("RIGHT", page, "RIGHT", -8, 0)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		last = fs
	end
	Line("GameFontNormal", "Commands")
	for _, c in ipairs(ns.COMMANDS) do
		Line("GameFontHighlightSmall", ("|cffffd100%s|r   %s"):format(c.usage, c.text))
	end
	Line("GameFontNormal", "Mouse", 14)
	for _, c in ipairs(ns.SHORTCUTS) do
		Line("GameFontHighlightSmall", ("|cffffd100%s|r   %s"):format(c.usage, c.text))
	end
end

-- Welcome: shown when the settings window opens, until "Don't show this again" is ticked; the ? button
-- next to the title brings it back. Sits on top of the window's contents.
local welcome

local function BuildWelcome()
	welcome = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	welcome:SetPoint("TOPLEFT", 8, -38)
	welcome:SetPoint("BOTTOMRIGHT", -8, 8)
	welcome:SetFrameLevel(frame:GetFrameLevel() + 50)
	welcome:EnableMouse(true) -- nothing behind it is clickable while it's up
	welcome:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
	welcome:SetBackdropColor(0.04, 0.04, 0.04, 0.98)
	welcome:Hide()

	local title = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Sediment sorts your bags for you")

	local body = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	body:SetPoint("RIGHT", -16, 0)
	body:SetJustifyH("LEFT")
	body:SetSpacing(3)
	body:SetText("Every item has a |cffffd100weight|r. Light items |cffffd100float|r to the top of your bags, "
		.. "heavy ones |cffffd100sink|r to the bottom, and the space in between is where new loot lands.\n\n"
		.. "While your bags are closed, Sediment keeps them in order quietly in the background. "
		.. "Nothing moves while they're open, and nothing ever moves in combat.\n\n"
		.. "|cffffd100Get started:|r give your items weights. Turn on |cffffd100Select mode|r on the Weights tab, "
		.. "then click any item in your bags to set its weight. Lower numbers float, higher numbers sink.\n\n"
		.. "|cffffd100Tips:|r Alt+right-click any bag item to set its weight without opening this window. "
		.. "Right-click the sort button to turn auto-sort on or off. The gear next to it opens this window.")

	local start = CreateFrame("Button", nil, welcome, "UIPanelButtonTemplate")
	start:SetSize(130, 24)
	start:SetPoint("BOTTOMLEFT", 16, 46)
	start:SetText("Set weights")
	start:SetScript("OnClick", function()
		welcome:Hide()
		ShowTab("Weights")
		Settings.SetSelectMode(true)
	end)

	local ok = CreateFrame("Button", nil, welcome, "UIPanelButtonTemplate")
	ok:SetSize(90, 24)
	ok:SetPoint("BOTTOMRIGHT", -16, 14)
	ok:SetText("OK")
	ok:SetScript("OnClick", function()
		welcome:Hide()
	end)

	local dontShow = CreateFrame("CheckButton", nil, welcome, "UICheckButtonTemplate")
	dontShow:SetSize(24, 24)
	dontShow:SetPoint("BOTTOMLEFT", 12, 14)
	dontShow:SetScript("OnClick", function(self)
		SedimentDB.welcomeHidden = self:GetChecked() and true or nil
	end)
	local dontShowText = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dontShowText:SetPoint("LEFT", dontShow, "RIGHT", 4, 0)
	dontShowText:SetText("Don't show this again")
	welcome:SetScript("OnShow", function()
		dontShow:SetChecked(SedimentDB.welcomeHidden and true or false)
	end)
end

function Settings.ShowWelcome()
	if not frame then
		return
	end
	if not welcome then
		BuildWelcome()
	end
	welcome:Show()
end

function ShowTab(name)
	if (name == "Testing" or name == "Commands") and not SedimentDB.testingTools then
		name = "Sorting"
	end
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
	Settings.currentTab = name
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

	-- ? brings the welcome back.
	local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	help:SetSize(22, 22)
	help:SetPoint("LEFT", title, "RIGHT", 8, 0)
	help:SetText("?")
	help:SetScript("OnClick", function()
		Settings.ShowWelcome()
	end)
	help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "How Sediment works")
		GameTooltip:Show()
	end)
	help:SetScript("OnLeave", GameTooltip_Hide)

	local x = 132 -- after the title and ?; four 72px tabs end clear of the close button
	for _, name in ipairs({ "Weights", "Sorting", "Testing", "Commands" }) do
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetSize(72, 22)
		tab:SetPoint("TOPLEFT", x, -10)
		tab:SetText(name)
		tab:SetScript("OnClick", function()
			ShowTab(name)
		end)
		tabs[name] = tab
		x = x + 75

		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", 14, -42)
		page:SetPoint("BOTTOMRIGHT", -12, 12)
		page:Hide()
		pages[name] = page
	end
	tabs.Testing:SetShown(SedimentDB.testingTools and true or false)
	tabs.Commands:SetShown(SedimentDB.testingTools and true or false)
	BuildWeightsPage(pages.Weights)
	BuildSortingPage(pages.Sorting)
	BuildTestingPage(pages.Testing)
	BuildCommandsPage(pages.Commands)
	frame:SetScript("OnShow", function()
		Settings.Refresh()
	end)
	frame:SetScript("OnHide", function()
		Settings.SetSelectMode(false) -- select mode never outlives the window
	end)
	ShowTab("Sorting")
end

local function RunRefreshers(page)
	for _, f in ipairs(page.refreshers or {}) do
		f()
	end
end

function Settings.Refresh()
	if selecting then
		Settings.RefreshOverlays() -- weights may have changed: update the numbers on the slots
	end
	if not frame or not frame:IsShown() then
		return
	end
	if pages.Weights:IsShown() then
		Settings.RefreshLadder()
		RunRefreshers(pages.Weights)
	end
	if pages.Sorting:IsShown() then
		RunRefreshers(pages.Sorting)
	end
	if pages.Testing:IsShown() then
		RunRefreshers(pages.Testing)
	end
end

function Settings.RefreshTesting()
	if frame and frame:IsShown() and pages.Testing:IsShown() then
		RunRefreshers(pages.Testing)
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

-- tab: "Weights", "Sorting" or "Testing"; nil keeps the last one.
function Settings.Open(tab)
	if InCombatLockdown() then
		Print("settings are closed during combat.")
		return
	end
	if not frame then
		Build()
	end
	local wasShown = frame:IsShown()
	frame:Show()
	ShowTab(tab or Settings.currentTab or "Sorting")
	if not wasShown and not SedimentDB.welcomeHidden then
		Settings.ShowWelcome()
	end
end

function Settings.Toggle(tab)
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Settings.Open(tab)
	end
end
