-- Settings: the Sediment window. A section list on the left (like WoW's Options window), the selected
-- section on the right. Opened with the gear left of the bag's sort button (Sorting), /sed, or the
-- Settings button in the weight popup (Weights). It closes in combat.
--
-- Weights: Select mode (click bag items to set their weights) and the ladder: every weight you've set
--   (items, flags, subclasses, classes, the default), light to heavy, with the sink line drawn across.
--   Edit in place; x removes a rule (with Undo). "Not set": categories in the bags still on the default.
-- Sorting: auto-sort on/off, its order, wait, smoothness, what happens if the bags open mid-sort, and
--   "Debug mode", which adds a Debug group: Testing (seeded scrambles, status text, recent sorts) and
--   Commands (every /sed command).
-- Special bags: the special bags you have, the fill switch, and the keep-out rules with x/Undo.
-- History: saved versions of the rules (Weights.Snapshot and friends), newest first, with Load, Name and x;
--   "Save a copy" (optionally named) at the top.
-- The setup questions (Setup.lua) open with the window, until "Don't show this again" or they're done;
-- the ? next to the title brings their first page back. (It replaced the old welcome screen.)
--
-- Numbers are still what's stored and edited. The ladder is laid out so it could become a ranking
-- (move rules between rungs instead of typing numbers) without changing anything underneath.

local _, ns = ...
local Settings = {}
ns.Settings = Settings
local Print = function(msg) ns.Print(msg) end

-- Layout like WoW's own Options window: a section list on the left (grouped, with a Debug group that only
-- shows in debug mode), the selected section's settings on the right under its name. A list scales to any
-- number of sections, where a row of tabs ran out of width at five.
local WIDTH, HEIGHT = 600, 520
local NAV_W = 140                         -- the section list
local CONTENT_X = NAV_W + 24              -- where the settings pane starts
local CONTENT_W = WIDTH - CONTENT_X - 14  -- the settings pane's width
local NAV_GROUPS = {
	{ header = "Sediment", items = { "Weights", "Sorting", "Special bags", "History" } },
	{ header = "Debug", items = { "Testing", "Commands" }, debug = true },
}
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

-- A rule's name (and icon, for items), for the setup questions' review list.
function Settings.RuleLabel(kind, key)
	if kind == "item" then
		return ItemLabel(key), C_Item.GetItemIconByID(key)
	elseif kind == "flag" then
		return ns.Weights.FlagLabel(key)
	elseif kind == "subclass" then
		return SubclassLabel(key)
	elseif kind == "class" then
		return ClassLabel(key)
	end
	return "Everything else"
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
	row:SetSize(CONTENT_W - 30, ROW_HEIGHT)

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
--
-- The setup questions borrow it ("anything next to your hearthstone?"): they pass their own click handler
-- and slot labels, so a click picks the item instead of opening the popup.
--
-- Highlights (the setup questions): while on, slots whose item has no rule of its own get an orange
-- outline, and the items the current question is about a gold one. Plain textures on a frame that takes
-- no clicks, so the bag works as usual underneath.

local selecting = false
local selectHandler, selectLabel = nil, nil -- set by the setup questions; nil = open the weight popup
local highlighting, highlightFocus = false, nil
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
		if selectHandler then
			selectHandler(b:GetBagID(), b:GetID())
		else
			ns.Popup.Open(b:GetBagID(), b:GetID())
		end
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

local UNRULED_EDGE, UNRULED_TINT = { 1, 0.5, 0.1, 0.95 }, { 1, 0.5, 0.1, 0.12 }
local FOCUS_EDGE, FOCUS_TINT = { 1, 0.85, 0.15, 1 }, { 1, 0.85, 0.15, 0.3 }

-- The highlight on one slot: a tint and a 2px outline, under the select catcher, taking no clicks.
local function Marker(button)
	local m = button.SedimentMark
	if m then
		return m
	end
	m = CreateFrame("Frame", nil, button)
	m:SetAllPoints(button)
	m:SetFrameLevel(button:GetFrameLevel() + 5)
	m.tint = m:CreateTexture(nil, "OVERLAY")
	m.tint:SetAllPoints()
	m.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = m:CreateTexture(nil, "OVERLAY", nil, 1)
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT")
			t:SetPoint(side .. "RIGHT")
			t:SetHeight(2)
		else
			t:SetPoint("TOP" .. side)
			t:SetPoint("BOTTOM" .. side)
			t:SetWidth(2)
		end
		m.edges[#m.edges + 1] = t
	end
	function m.Style(edge, tint)
		m.tint:SetColorTexture(tint[1], tint[2], tint[3], tint[4])
		for _, t in ipairs(m.edges) do
			t:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
		end
	end
	button.SedimentMark = m
	return m
end

function Settings.RefreshOverlays()
	for _, f in ipairs(ContainerFrames()) do
		if f.EnumerateValidItems then
			if (selecting or highlighting) and not hookedFrames[f] and f.UpdateItems then
				-- Bag windows rebuild their buttons as they open and change; follow along.
				hooksecurefunc(f, "UpdateItems", Settings.RefreshOverlays)
				hookedFrames[f] = true
			end
			-- Every bag window, the reagent bag's included. A window's slot list can run past the buttons
			-- it has (a closed window keeps its old size), so skip empty entries rather than stop: an
			-- error here used to end the loop before it reached the reagent bag.
			for _, b in f:EnumerateValidItems() do
				local c = b and b.SedimentSelect
				local m = b and b.SedimentMark
				local item = b and (selecting or highlighting) and f:IsShown() and b.GetBagID
					and ns.Bags.ReadSlot(b:GetBagID(), b:GetID())
				if item and selecting then
					c = Catcher(b)
					local text, color
					if selectLabel then
						text, color = selectLabel(item)
					end
					if not text then
						local levels, winner = ns.Weights.Explain(item)
						text = FormatWeight(levels[winner].weight)
						color = levels[winner].kind == "default" and DEFAULT_COLOR or SET_COLOR
					end
					c.weight:SetText(text)
					c.weight:SetTextColor(color[1], color[2], color[3])
					c:Show()
				elseif c then
					c:Hide()
				end
				local focus = item and highlighting and highlightFocus and highlightFocus(item)
				local unruled = item and highlighting and not ns.Weights.HasOwnRule(item)
				if focus or unruled then
					m = Marker(b)
					if focus then
						m.Style(FOCUS_EDGE, FOCUS_TINT)
					else
						m.Style(UNRULED_EDGE, UNRULED_TINT)
					end
					m:Show()
				elseif m then
					m:Hide()
				end
			end
		end
	end
end

function Settings.IsSelecting()
	return selecting
end

-- Are any overlays on the bag slots (select mode or highlights)? They follow bag changes.
function Settings.OverlaysActive()
	return selecting or highlighting
end

-- Highlights for the setup questions. focus(item) -> true for the items the current question is about.
function Settings.SetHighlight(on, focus)
	highlighting = on and true or false
	highlightFocus = highlighting and focus or nil
	Settings.RefreshOverlays()
end

-- handler(bag, slot) and label(item) -> text, {r, g, b} (or nil for the weight) are for the setup
-- questions; without them a click opens the weight popup.
function Settings.SetSelectMode(on, handler, label)
	if on and InCombatLockdown() then
		Print("not in combat.")
		on = false
	end
	local was = selecting
	selecting = on and true or false
	selectHandler = selecting and handler or nil
	selectLabel = selecting and label or nil
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
	ns.Setup.Close() -- keeps its place, like "Finish later"
end

function Settings.Close()
	if frame then
		frame:Hide()
	end
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
	ladderChild:SetSize(CONTENT_W - 30, 100)
	scroll:SetScrollChild(ladderChild)

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetSize(140, 24)
	reset:SetPoint("BOTTOMLEFT", 2, 2)
	reset:SetText("Reset to default")
	reset:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_RESET_WEIGHTS")
	end)

	-- Shown while History has a version that differs from the rules in use: loads the newest such.
	local restore = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	restore:SetSize(170, 24)
	restore:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	restore:SetText("Restore previous rules")
	restore:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_RESTORE_RULES")
	end)
	restore:SetScript("OnEnter", function(self)
		local b = ns.Weights.PreviousVersion()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, "Restore previous rules")
		if b then
			GameTooltip_AddNormalLine(GameTooltip, ("Loads the version saved %s (%s): %s. Your current rules are "
				.. "saved to History first, so this can be undone. Older versions are in the History section.")
				:format(b.time or "?", b.name or b.reason or "", ns.Weights.VersionSummary(b)))
		end
		GameTooltip:Show()
	end)
	restore:SetScript("OnLeave", GameTooltip_Hide)
	page.refreshers[#page.refreshers + 1] = function()
		restore:SetShown(ns.Weights.PreviousVersion() ~= nil)
	end
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
	text = "Reset to default? This removes all your rules (weights and \"keep in my normal bags\"); your bags "
		.. "then sort by item type. They're saved to History first, so you can load them again.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.Weights.ResetToDefault()
		Changed()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SEDIMENT_RESTORE_RULES"] = {
	text = "Restore your previous rules? Your current rules are saved to History first, so you can switch back.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		local b = ns.Weights.PreviousVersion()
		if b then
			ns.Weights.LoadVersion(b)
		end
		Changed()
		if Settings.RefreshSpecialList then
			Settings.RefreshSpecialList() -- keep-out rules came back too
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local ShowTab -- defined below

-- Lay out the section list: group headers and their entries, the Debug group only in debug mode.
function Settings.LayoutNav()
	if not frame or not frame.nav then
		return
	end
	local y = -8
	for _, group in ipairs(NAV_GROUPS) do
		local visible = not group.debug or SedimentDB.testingTools
		local header = frame.navHeaders[group.header]
		header:SetShown(visible)
		header.bar:SetShown(visible)
		if visible then
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 10, y - 3)
			header.bar:ClearAllPoints()
			header.bar:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 4, y)
			header.bar:SetPoint("RIGHT", frame.nav, "RIGHT", -4, 0)
			header.bar:SetHeight(18)
			y = y - 22
		end
		for _, name in ipairs(group.items) do
			local entry = tabs[name]
			entry:SetShown(visible)
			if visible then
				entry:ClearAllPoints()
				entry:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 6, y)
				y = y - 19
			end
		end
		y = y - 8
	end
end

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
	ChoiceRow(page, -212, "If the bags open during an auto-sort", 100,
		ns.Sort.OpenBagsMode, function(v) SedimentDB.openBags = v end, {
			{ value = "pause", label = "Pause", help = "Nothing moves while the bags are open; the sort "
				.. "carries on once they close." },
			{ value = "finish", label = "Finish now", help = "Everything left goes out at once, so the bag "
				.. "settles within about half a second of opening. Expect a short stutter." },
		})
	local _, debugText = CheckRow(page, -280, "Debug mode",
		function() return SedimentDB.testingTools and true or false end,
		function(on)
			SedimentDB.testingTools = on
			Settings.LayoutNav()
			ns.Popup.BenchRefresh()
		end)
	HelpText(page, debugText, "Adds a Debug group to the list on the left: Testing (seeded scrambles, recent sorts, "
		.. "a status line in the bag) and Commands (every /sed command).")
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

-- Special bags tab: which special bags you have, the fill switch, and every keep-out rule ("Keep in my
-- normal bags": all Cloth, or one item) with x to remove it. Removing doesn't re-sort the list: the row
-- greys out with Undo, so nothing moves under the mouse. Rules are added from the weight popup.
local specialRows = {}

local function KeepOutLabel(rule)
	if rule.kind == "subclass" then
		local classID, subclassID = rule.key:match("^(%-?%d+):(%-?%d+)$")
		local name = C_Item.GetItemSubClassInfo(tonumber(classID), tonumber(subclassID))
		return "all " .. (name or rule.key), "category"
	end
	return ItemLabel(rule.key), "item"
end

local function BuildSpecialPage(page)
	page.refreshers = {}
	local bagsText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bagsText:SetPoint("TOPLEFT", 4, 0)
	bagsText:SetPoint("RIGHT", -8, 0)
	bagsText:SetJustifyH("LEFT")
	page.refreshers[#page.refreshers + 1] = function()
		local names = {}
		for _, b in ipairs(ns.Bags.SpecialBags()) do
			names[#names + 1] = ("%s (%d slots)"):format(b.name, b.slots)
		end
		bagsText:SetText("|cffffd100Your special bags:|r " .. (#names > 0 and table.concat(names, ", ")
			or "none right now (reagent bags and profession bags like herb or mining bags)"))
	end

	local _, fillText = CheckRow(page, -24, "Fill reagent and profession bags automatically",
		ns.Bags.FillSpecialBags, function(on)
			SedimentDB.fillSpecialBags = on and nil or false
			ns.AutoSort.Resume()
		end)
	HelpText(page, fillText, "Off: Sediment never moves anything into those bags; what's already in them stays "
		.. "and is still sorted there.")

	local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 4, -78)
	heading:SetText("Kept in your normal bags")
	local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
	hint:SetPoint("RIGHT", -8, 0)
	hint:SetJustifyH("LEFT")
	hint:SetText("To add one, Alt+right-click an item (or use Select mode in the Weights section) and tick a box under "
		.. "\"Keep in my normal bags\".")

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -112)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT_W - 30, 100)
	scroll:SetScrollChild(child)

	local function Row(i)
		local row = specialRows[i]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, child)
		row:SetSize(CONTENT_W - 30, ROW_HEIGHT)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", 8, 0)
		row.label:SetJustifyH("LEFT")
		row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.kind:SetPoint("LEFT", 260, 0)
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.remove:SetSize(20, 20)
		row.remove:SetPoint("RIGHT", -2, 0)
		row.remove:SetScript("OnClick", function()
			if row.rule and not row.removed then
				ns.Bags.SetKeepOut(row.rule.kind, row.rule.key, false)
				row.removed = true
				row.label:SetText(row.text .. " |cff888888(removed)|r")
				row.label:SetTextColor(0.5, 0.5, 0.5)
				row.remove:Hide()
				row.undo:Show()
				ns.AutoSort.Resume()
				ns.Popup.Refresh()
			end
		end)
		row.undo = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.undo:SetSize(52, 18)
		row.undo:SetPoint("RIGHT", -2, 0)
		row.undo:SetText("Undo")
		row.undo:SetScript("OnClick", function()
			if row.rule and row.removed then
				ns.Bags.SetKeepOut(row.rule.kind, row.rule.key, true)
				row.removed = nil
				row.label:SetText(row.text)
				row.label:SetTextColor(1, 1, 1)
				row.undo:Hide()
				row.remove:Show()
				ns.AutoSort.Resume()
				ns.Popup.Refresh()
			end
		end)
		specialRows[i] = row
		return row
	end

	-- Rebuilt only when the tab is shown or the window opens, never while clicking (removal greys a row).
	function Settings.RefreshSpecialList()
		local rules = ns.Bags.KeepOutRules()
		local labelled = {}
		for _, rule in ipairs(rules) do
			local text, kind = KeepOutLabel(rule)
			labelled[#labelled + 1] = { rule = rule, text = text, kind = kind }
		end
		table.sort(labelled, function(a, b)
			if a.kind ~= b.kind then
				return a.kind < b.kind -- categories first
			end
			return a.text < b.text
		end)
		for i, e in ipairs(labelled) do
			local row = Row(i)
			row.rule, row.text, row.removed = e.rule, e.text, nil
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row.label:SetText(e.text)
			row.label:SetTextColor(1, 1, 1)
			row.kind:SetText(e.kind)
			row.remove:Show()
			row.undo:Hide()
			row:Show()
		end
		for i = #labelled + 1, #specialRows do
			specialRows[i]:Hide()
			specialRows[i].rule = nil
		end
		if #labelled == 0 then
			local row = Row(1)
			row.rule = nil
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, 0)
			row.label:SetText("|cff888888Nothing yet: everything a special bag takes goes into it.|r")
			row.kind:SetText("")
			row.remove:Hide()
			row.undo:Hide()
			row:Show()
		end
		child:SetHeight(math.max(1, #labelled) * ROW_HEIGHT + 4)
	end
end

-- History: every saved version of the rules, newest first. Load (asks first; the rules in use are saved
-- before it loads), Name, x (asks first). Hover a row for its rules. "Save a copy" at the top, with an
-- optional name.
local historyRows = {}

-- A version's rules, light to heavy with the sink line, for its tooltip.
local function VersionTooltip(entry)
	local w, list = entry.weights, {}
	for id, v in pairs(w.items) do list[#list + 1] = { v, ItemLabel(id) } end
	for k, v in pairs(w.flags) do list[#list + 1] = { v, ns.Weights.FlagLabel(k) } end
	for k, v in pairs(w.subclasses) do list[#list + 1] = { v, SubclassLabel(k) } end
	for k, v in pairs(w.classes) do list[#list + 1] = { v, ClassLabel(k) } end
	list[#list + 1] = { w.default, "Everything else (default)" }
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local lines, sinkShown = {}, false
	for _, e in ipairs(list) do
		if not sinkShown and e[1] >= w.sinkLine then
			lines[#lines + 1] = "|cffffb040---- sink line " .. tostring(w.sinkLine) .. " ----|r"
			sinkShown = true
		end
		lines[#lines + 1] = ("%s  |cff888888%s|r"):format(e[2], tostring(e[1]))
	end
	if not sinkShown then
		lines[#lines + 1] = "|cffffb040---- sink line " .. tostring(w.sinkLine) .. " ----|r"
	end
	local ko = entry.keepOut or {}
	for k in pairs(ko.subclasses or {}) do
		lines[#lines + 1] = "|cff9ad1ffKept in normal bags:|r " .. KeepOutLabel({ kind = "subclass", key = k })
	end
	for k in pairs(ko.items or {}) do
		lines[#lines + 1] = "|cff9ad1ffKept in normal bags:|r " .. ItemLabel(k)
	end
	return lines
end

local function HistoryChanged()
	Changed()
	if Settings.RefreshSpecialList then
		Settings.RefreshSpecialList() -- keep-out rules may have come back
	end
end

StaticPopupDialogs["SEDIMENT_LOAD_VERSION"] = {
	text = "Load the rules saved %s?\n\nYour current rules are saved to History first, so you can switch back.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, entry)
		if entry then
			ns.Weights.LoadVersion(entry)
			HistoryChanged()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SEDIMENT_DELETE_VERSION"] = {
	text = "Delete the version saved %s? This can't be undone.",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, entry)
		if entry then
			ns.Weights.DeleteVersion(entry)
			Settings.Refresh()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- The dialog's edit box: its name changed between client versions.
local function DialogEditBox(dialog)
	return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

StaticPopupDialogs["SEDIMENT_NAME_VERSION"] = {
	text = "Name this version (blank for no name). Named versions are never dropped from History.",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self, entry)
		local box = DialogEditBox(self)
		if box then
			box:SetText(entry and entry.name or "")
			box:HighlightText()
		end
	end,
	OnAccept = function(self, entry)
		local box = DialogEditBox(self)
		if entry and box then
			ns.Weights.RenameVersion(entry, box:GetText())
			Settings.Refresh()
		end
	end,
	EditBoxOnEnterPressed = function(box, entry)
		local dialog = box:GetParent()
		if entry then
			ns.Weights.RenameVersion(entry, box:GetText())
			Settings.Refresh()
		end
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(box)
		box:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local HISTORY_ROW = 34

local function BuildHistoryPage(page)
	page.refreshers = {}
	local nameLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameLabel:SetPoint("TOPLEFT", 4, -4)
	nameLabel:SetText("Name (optional)")
	local nameBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	nameBox:SetSize(170, 20)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	local save = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	save:SetSize(100, 22)
	save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	save:SetText("Save a copy")
	local function Save()
		local name = nameBox:GetText()
		nameBox:SetText("")
		nameBox:ClearFocus()
		local _, new = ns.Weights.SaveCopy(name)
		if not new then
			Print(name ~= "" and "these rules were already saved; that version is named now."
				or "these rules are already saved (the newest version).")
		end
		Settings.Refresh()
	end
	save:SetScript("OnClick", Save)
	nameBox:SetScript("OnEnterPressed", Save)
	nameBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)

	local help = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 4, -30)
	help:SetPoint("RIGHT", -8, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Sediment saves your rules before anything replaces them, when you finish the setup questions, and "
		.. "when you log in if they've changed. Hover a version to see its rules. The newest 20 are kept, and "
		.. "named ones until you delete them.")

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -64)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT_W - 30, 100)
	scroll:SetScrollChild(child)

	local function Row(i)
		local row = historyRows[i]
		if row then
			return row
		end
		row = CreateFrame("Frame", nil, child)
		row:SetSize(CONTENT_W - 30, HISTORY_ROW)
		row:EnableMouse(true)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(1, 1, 1, 0.04)
		row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.title:SetPoint("TOPLEFT", 6, -3)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.info:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
		row.info:SetJustifyH("LEFT")
		row.info:SetWordWrap(false)
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.remove:SetSize(20, 20)
		row.remove:SetPoint("RIGHT", -2, 0)
		row.remove:SetScript("OnClick", function()
			if row.entry then
				StaticPopup_Show("SEDIMENT_DELETE_VERSION", row.entry.time, nil, row.entry)
			end
		end)
		row.rename = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.rename:SetSize(52, 20)
		row.rename:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
		row.rename:SetText("Name")
		row.rename:SetScript("OnClick", function()
			if row.entry then
				StaticPopup_Show("SEDIMENT_NAME_VERSION", nil, nil, row.entry)
			end
		end)
		row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.load:SetSize(52, 20)
		row.load:SetPoint("RIGHT", row.rename, "LEFT", -4, 0)
		row.load:SetText("Load")
		row.load:SetScript("OnClick", function()
			if row.entry then
				StaticPopup_Show("SEDIMENT_LOAD_VERSION", row.entry.time, nil, row.entry)
			end
		end)
		row.title:SetPoint("RIGHT", row.load, "LEFT", -6, 0)
		row.info:SetPoint("RIGHT", row.load, "LEFT", -6, 0)
		row:SetScript("OnEnter", function(self)
			if not self.entry then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, self.entry.name or self.entry.time)
			if self.entry.name then
				GameTooltip_AddNormalLine(GameTooltip, "Kept: named versions are never dropped. Clear the name to stop keeping it.")
			end
			for k, line in ipairs(VersionTooltip(self.entry)) do
				if k > 30 then
					GameTooltip_AddNormalLine(GameTooltip, "...")
					break
				end
				GameTooltip:AddLine(line, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		historyRows[i] = row
		return row
	end

	page.refreshers[#page.refreshers + 1] = function()
		local h = ns.Weights.History()
		for i, entry in ipairs(h) do
			local row = Row(i)
			row.entry = entry
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * (HISTORY_ROW + 2))
			local current = ns.Weights.IsCurrent(entry)
			if entry.name then
				-- Named = kept: never dropped by the 20-version limit (user asked for a visible mark).
				row.title:SetText(entry.name .. "  |cffffd100(kept)|r")
				row.title:SetTextColor(1, 1, 1)
			else
				row.title:SetText(entry.reason or "saved")
				row.title:SetTextColor(0.75, 0.75, 0.75)
			end
			row.info:SetText(("%s  ·  %s%s"):format(entry.time or "?", ns.Weights.VersionSummary(entry),
				current and "  ·  |cff66ff66in use|r" or ""))
			row.load:SetEnabled(not current)
			row:Show()
		end
		for i = #h + 1, #historyRows do
			historyRows[i]:Hide()
			historyRows[i].entry = nil
		end
		if #h == 0 then
			local row = Row(1)
			row.entry = nil
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, 0)
			row.title:SetText("|cff888888Nothing saved yet.|r")
			row.info:SetText("")
			row.load:Hide()
			row.rename:Hide()
			row.remove:Hide()
			row:Show()
		else
			for i = 1, #h do
				historyRows[i].load:Show()
				historyRows[i].rename:Show()
				historyRows[i].remove:Show()
			end
		end
		child:SetHeight(math.max(1, #h) * (HISTORY_ROW + 2) + 4)
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

function Settings.ShowWelcome()
	ns.Setup.ShowIntro()
end

function ShowTab(name)
	if (name == "Testing" or name == "Commands") and not SedimentDB.testingTools then
		name = "Sorting"
	end
	for key, page in pairs(pages) do
		page:SetShown(key == name)
	end
	for key, entry in pairs(tabs) do
		entry.selected:SetShown(key == name)
		entry.text:SetTextColor(key == name and 1 or 0.9, key == name and 0.82 or 0.9, key == name and 0 or 0.9)
	end
	if frame.pageTitle then
		frame.pageTitle:SetText(name)
	end
	Settings.currentTab = name
	if name == "Special bags" and Settings.RefreshSpecialList then
		Settings.RefreshSpecialList()
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

	-- ? brings back the setup questions' first page.
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
		GameTooltip_AddNormalLine(GameTooltip, "What it does, and the setup questions.")
		GameTooltip:Show()
	end)
	help:SetScript("OnLeave", GameTooltip_Hide)

	-- The section list.
	local nav = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	nav:SetPoint("TOPLEFT", 10, -40)
	nav:SetPoint("BOTTOMLEFT", 10, 10)
	nav:SetWidth(NAV_W)
	nav:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	nav:SetBackdropColor(0, 0, 0, 0.5)
	frame.nav = nav
	frame.navHeaders = {}
	for _, group in ipairs(NAV_GROUPS) do
		local header = nav:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetText(group.header)
		header.bar = nav:CreateTexture(nil, "BACKGROUND")
		header.bar:SetColorTexture(1, 0.82, 0, 0.12)
		frame.navHeaders[group.header] = header
		for _, name in ipairs(group.items) do
			local entry = CreateFrame("Button", nil, nav)
			entry:SetSize(NAV_W - 12, 18)
			entry.text = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			entry.text:SetPoint("LEFT", 14, 0)
			entry.text:SetText(name)
			entry:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			entry.selected = entry:CreateTexture(nil, "BACKGROUND")
			entry.selected:SetAllPoints()
			entry.selected:SetColorTexture(1, 0.82, 0, 0.25)
			entry.selected:Hide()
			entry:SetScript("OnClick", function()
				ShowTab(name)
			end)
			tabs[name] = entry
		end
	end

	-- The settings pane: the section's name, then its settings.
	frame.pageTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	frame.pageTitle:SetPoint("TOPLEFT", CONTENT_X, -42)
	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(1, 0.82, 0, 0.25)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", CONTENT_X, -64)
	rule:SetPoint("RIGHT", -14, 0)
	for _, group in ipairs(NAV_GROUPS) do
		for _, name in ipairs(group.items) do
			local page = CreateFrame("Frame", nil, frame)
			page:SetPoint("TOPLEFT", CONTENT_X, -72)
			page:SetPoint("BOTTOMRIGHT", -12, 12)
			page:Hide()
			pages[name] = page
		end
	end
	Settings.LayoutNav()
	BuildWeightsPage(pages.Weights)
	BuildSortingPage(pages.Sorting)
	BuildTestingPage(pages.Testing)
	BuildSpecialPage(pages["Special bags"])
	BuildHistoryPage(pages.History)
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
	if selecting or highlighting then
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
	if pages["Special bags"]:IsShown() then
		RunRefreshers(pages["Special bags"])
	end
	if pages.History:IsShown() then
		RunRefreshers(pages.History)
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
		ns.Setup.ShowIntro(true)
	end
end

function Settings.Toggle(tab)
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Settings.Open(tab)
	end
end
