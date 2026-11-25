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
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Settings.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Settings = {}
ns.Settings = Settings
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)
local Print = function(msg) ns.Print(msg) end

-- Layout like WoW's own Options window: a section list on the left (grouped, with a Debug group that only
-- shows in debug mode), the selected section's settings on the right under its name. A list scales to any
-- number of sections, where a row of tabs ran out of width at five.
local WIDTH, HEIGHT = 760, 600 -- was 600x520: cramped (user, 2026-11-25)
local NAV_W = 140                         -- the section list
local CONTENT_X = NAV_W + 24              -- where the settings pane starts
local CONTENT_W = WIDTH - CONTENT_X - 14  -- the settings pane's width
local NAV_GROUPS = {
	{ header = "Sediment", items = { "Weights", "Special bags", "Sorting", "History" } }, -- user's order, 2026-11-25
	{ header = "Debug", items = { "Testing", "Commands", "Files" }, debug = true },
}
-- The section ids above are internal; what the list and the page title show comes from Text.lua for the
-- sections named after one of Sediment's nouns, so renaming the noun renames the section.
local SECTION_TEXT = { Weights = "SortValues", History = "SavedRules" }
local function SectionLabel(id)
	return SECTION_TEXT[id] and L(SECTION_TEXT[id]) or id
end

local ROW_HEIGHT = 22
-- The Weights list's rows stop here, so each x sits just past the longest name rather than across the
-- window (user, 2026-11-25: after the window grew, it was hard to tell which item an x belonged to).
local LADDER_W = 430

local KIND_ORDER = { item = 1, flag = 2, subclass = 3, class = 4, default = 5 }
local KIND_LABEL = { item = "Item", flag = "Flag", subclass = "Subclass", class = "Class", default = "Default" }
local KIND_COLOR = {
	item = "ffd9b46a", flag = "ff9ad1ff", subclass = "ffb4e0a0", class = "ff8fd18f", default = "ffaaaaaa",
}
local FLOAT_COLOR = { 0.85, 0.85, 0.85 }
local SINK_COLOR = { 0.7, 0.6, 0.5 }
local UNSET_COLOR = { 1, 0.5, 0.1 } -- orange, like the not-set numbers in Select Mode

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

-- A Weight changed: also sort now, so the player sees the outcome (Sort.StartSoon).
local function WeightChanged()
	Changed()
	ns.Sort.StartSoon()
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
	list[#list + 1] = { kind = "default", label = "Not set (default)", weight = w.default }
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
	local items = 0
	for _, s in ipairs(ns.Bags.Read()) do
		local item = s.item
		if item then
			local levels, winner = ns.Weights.Explain(item)
			if levels[winner].kind == "default" then
				items = items + 1
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
	return list, items
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
	row:SetSize(LADDER_W, ROW_HEIGHT)
	-- Every other row striped, so the eye can follow a line from the number to its x.
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.05)

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
			WeightChanged()
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
			ns.Sort.StartSoon() -- the bags do re-sort, to show the outcome
		end
	end)

	-- Shown in place of x on a removed row; puts the rule back.
	row.undo = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.undo:SetSize(52, 18)
	row.undo:SetPoint("RIGHT", -2, 0)
	row.undo:SetText(L("UndoButton"))
	row.undo:Hide()
	row.undo:SetScript("OnClick", function()
		local entry = row.entry
		if entry and row.removed then
			ns.Weights.SetLevel(entry.kind, entry.key, entry.weight)
			row.removed = nil
			Settings.ShowEntryRow(row, entry, row.y)
			ns.Popup.Refresh()
			ns.AutoSort.Resume()
			ns.Sort.StartSoon()
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
	row:SetWidth(LADDER_W) -- rows share frames with headings, which are wider
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
		-- The Empty Space row (stored as the sink line): its name, then a line across to the row's end.
		row.kind:SetText("")
		row.icon:Hide()
		row.label:SetPoint("LEFT", row.kind, "LEFT", 0, 0)
		row.label:SetText(L("LootGap"))
		row.label:SetTextColor(1, 0.69, 0.25)
		row.line:ClearAllPoints()
		row.line:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
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
	local color = entry.missing and UNSET_COLOR or (entry.sinks and SINK_COLOR or FLOAT_COLOR)
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
	row:SetWidth(CONTENT_W - 30) -- headings get the full width (rows stop at LADDER_W), and no stripe
	row.stripe:Hide()
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
		ns.Sort.StartSoon()
	end
	lastRebuild = GetTime()
	local sinkLine = ns.Weights.SinkLine()
	local entries = LadderEntries()
	local i, y = 0, 0
	local function Next()
		i = i + 1
		local row = GetRow(i)
		row.stripe:SetShown(i % 2 == 0)
		local thisY = y
		y = y - ROW_HEIGHT
		return row, thisY
	end
	-- One list (user, 2026-11-25). What has no Weight of its own sorts at the default's place, so that's where
	-- its groups are listed: orange rows right after the default's row, both the broad group and the narrower
	-- one for now (which to keep is undecided). Give one a Weight and it sorts to its place like any other.
	local missing, unsetItems = MissingEntries()
	if Settings.unsetLine then
		Settings.unsetLine:SetText(unsetItems > 0 and ("%d item%s in your bags %s no %s yet."):format(unsetItems,
			unsetItems == 1 and "" or "s", unsetItems == 1 and "has" or "have", L("SortValue")) or "")
	end
	local sinkShown = false
	local function SinkLineRow()
		local r, ey = Next()
		ShowEntryRow(r, { kind = "sinkLine", weight = sinkLine }, ey)
		sinkShown = true
	end
	for _, entry in ipairs(entries) do
		if not sinkShown and entry.weight >= sinkLine then
			SinkLineRow()
		end
		entry.sinks = entry.weight >= sinkLine
		local r, ey = Next()
		ShowEntryRow(r, entry, ey)
		if entry.kind == "default" then
			for _, m in ipairs(missing) do
				m.missing, m.sinks = true, entry.sinks
				local mr, my = Next()
				ShowEntryRow(mr, m, my)
			end
		end
	end
	if not sinkShown then
		SinkLineRow()
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
		Settings.selectButton:SetText(Settings.SelectLabel())
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
-- Spacing, the same on every page (user, 2026-11-25: the window felt cramped, and the Sorting boxes sat on
-- their help text): help text sits GAP_HELP under its label, groups are GAP_GROUP apart, and controls (boxes,
-- choice buttons) start at CONTROL_X, centred on their label's line so they never reach the help below.
local GAP_HELP, GAP_GROUP, CONTROL_X = 6, 18, 300

-- Lays a page out top to bottom: each region goes under the one before (gap), from the page's left edge
-- (x); wrap = text stretches to the page's right edge and wraps there.
local function Flow(page)
	local last, lastX
	return function(region, gap, x, wrap)
		x = x or 4
		region:ClearAllPoints()
		if last then
			region:SetPoint("TOPLEFT", last, "BOTTOMLEFT", x - lastX, -(gap or 0))
		else
			region:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
		end
		if wrap then
			region:SetPoint("RIGHT", page, "RIGHT", -8, 0)
		end
		last, lastX = region, x
		return region
	end
end

local function Text(page, template, text)
	local fs = page:CreateFontString(nil, "OVERLAY", template)
	fs:SetJustifyH("LEFT")
	if text then
		fs:SetText(text)
	end
	return fs
end

local function HelpText(page, text)
	return Text(page, "GameFontDisableSmall", text)
end

local function SelectLabel()
	return L("PickMode") .. (selecting and ": on" or ": off")
end
Settings.SelectLabel = SelectLabel

local function BuildWeightsPage(page)
	page.refreshers = {}
	local place = Flow(page)
	-- How to use it, in plain steps: the step above the button, what happens below it (user, 2026-11-25:
	-- "turn it on" described the feature, not how to start it).
	place(Text(page, "GameFontHighlight", "Click below to enter " .. N("PickMode") .. "."), 0, 4, true)
	local selectButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	selectButton:SetSize(170, 22)
	place(selectButton, GAP_HELP, 2)
	selectButton:SetScript("OnClick", function()
		Settings.SetSelectMode(not selecting)
	end)
	Settings.selectButton = selectButton
	place(Text(page, "GameFontHighlightSmall", "While " .. N("PickMode") .. " is on, click any item in your "
		.. "bags to see or change its " .. N("SortValue") .. ". Orange numbers are not set yet. Click the button "
		.. "again to stop."), GAP_HELP, 4, true)
	page.refreshers[#page.refreshers + 1] = function()
		selectButton:SetText(SelectLabel())
	end
	local ladderHint = place(HelpText(page, "Light at the top, heavy at the bottom. Edit a number and press "
		.. "Enter; x removes a " .. N("SortValue") .. "."), GAP_GROUP, 4, true)

	-- "N items in your bags have no Weight yet", bright orange. Its space is always kept (the text just goes
	-- empty when nothing is unset), so the list below never shifts (user, 2026-11-25: a section that appeared
	-- and vanished made the whole list jump).
	local unsetLine = place(Text(page, "GameFontNormal"), GAP_GROUP, 4, true)
	unsetLine:SetHeight(16)
	unsetLine:SetTextColor(UNSET_COLOR[1], UNSET_COLOR[2], UNSET_COLOR[3])
	Settings.unsetLine = unsetLine

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", unsetLine, "BOTTOMLEFT", -4, -GAP_HELP)
	scroll:SetPoint("BOTTOMRIGHT", -26, 40)
	ladderChild = CreateFrame("Frame", nil, scroll)
	ladderChild:SetSize(LADDER_W, 100)
	scroll:SetScrollChild(ladderChild)

	-- Start Fresh: the one way to clear everything (it replaced Reset to default; History's Load replaced
	-- Restore previous rules). It saves the rules, clears them and opens Setup.
	local fresh = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	fresh:SetSize(130, 24)
	fresh:SetPoint("BOTTOMLEFT", 2, 4)
	fresh:SetText(L("ClearAllButton"))
	fresh:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_START_FRESH")
	end)
end

local function LabeledBox(page, place, gap, label, help, get, set)
	local text = place(Text(page, "GameFontNormal", label), gap, 4)
	local box = NewBox(page, 60)
	box:SetPoint("LEFT", text, "LEFT", CONTROL_X, 0)
	place(HelpText(page, help), GAP_HELP + 4, 4, true) -- a box is taller than its label: clear it
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
local function ChoiceRow(page, place, gap, label, width, get, set, choices)
	local text = place(Text(page, "GameFontNormal", label), gap, 4)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetPoint("LEFT", text, "LEFT", CONTROL_X - 4, 0)
	local help = place(HelpText(page, ""), GAP_HELP + 4, 4, true)
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

-- A checkbox with its label, and help text under it if given.
local function CheckRow(page, place, gap, label, get, set, help)
	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	place(check, gap, 0)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("LEFT", check, "RIGHT", 4, 0)
	text:SetText(label)
	check.label = text
	if help then
		place(HelpText(page, help), 0, 28, true)
	end
	page.refreshers[#page.refreshers + 1] = function()
		check:SetChecked(get())
	end
	return check, text
end

StaticPopupDialogs["SEDIMENT_START_FRESH"] = {
	text = B("ClearAllButton") .. "? Your rules are saved to " .. N("SavedRules") .. ", then cleared (" .. N("SortValues")
		.. " and " .. L("KeepOutRule") .. "), and " .. N("Onboarding") .. " opens.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		Settings.Close()
		ns.Setup.Start(true)
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
			y = y - 24
		end
		for _, name in ipairs(group.items) do
			local entry = tabs[name]
			entry:SetShown(visible)
			if visible then
				entry:ClearAllPoints()
				entry:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 6, y)
				y = y - 21
			end
		end
		y = y - 10
	end
end

local function BuildSortingPage(page)
	page.refreshers = {}
	local place = Flow(page)
	CheckRow(page, place, 0, "Sort automatically while the bags are closed", ns.AutoSort.IsEnabled, function(on)
		if on ~= ns.AutoSort.IsEnabled() then
			ns.AutoSort.Toggle()
		end
	end)
	ChoiceRow(page, place, GAP_GROUP, "Auto-sort order", 100,
		function() return ns.Sort.AutoOrder() end,
		function(v) SedimentDB.autoOrder = v ns.AutoSort.Resume() end, {
			{ value = "partial", label = L("OrderMinimal"), help = "Only what the " .. N("SortValues") .. " require: "
				.. "items of equal " .. N("SortValue") .. " keep their order, identical stacks stay together. Fewest moves." },
			{ value = "full", label = L("OrderExact"), help = "The exact order, the same as the sort button. More "
				.. "moves, but every item always has the same spot." },
		})
	LabeledBox(page, place, GAP_GROUP, "Wait after changes (seconds)",
		"How long the bags must be quiet before auto-sort starts. Long enough for a burst of looting to "
		.. "finish and new quest items to register.",
		ns.AutoSort.Delay, function(n) SedimentDB.autoSortDelay = math.max(0, math.min(30, n)) end)
	LabeledBox(page, place, GAP_GROUP, "Smoothness (ms per frame)",
		"How much time per frame, on average, auto-sort may spend moving items. Lower is smoother but "
		.. "slower. The sort button always goes full speed.",
		ns.Sort.BudgetMs, function(n) SedimentDB.streamBudgetMs = math.max(0.01, math.min(50, n)) end)
	ChoiceRow(page, place, GAP_GROUP, "If the bags open during an auto-sort", 100,
		ns.Sort.OpenBagsMode, function(v) SedimentDB.openBags = v end, {
			{ value = "pause", label = L("OpenBagsPause"), help = "Nothing moves while the bags are open; the sort "
				.. "carries on once they close." },
			{ value = "finish", label = L("OpenBagsFinish"), help = "Everything left goes out at once, so the bag "
				.. "settles within about half a second of opening. Expect a short stutter." },
		})
	CheckRow(page, place, GAP_GROUP * 2, "Debug mode",
		function() return SedimentDB.testingTools and true or false end,
		function(on)
			SedimentDB.testingTools = on
			Settings.LayoutNav()
			ns.Popup.BenchRefresh()
		end,
		"Adds a Debug group to the list on the left: Testing (seeded scrambles, recent sorts, a status line in "
		.. "the bag) and Commands (every /sed command).")
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

	CheckRow(page, place, GAP_GROUP, "Status text in the bag (last sort's cost)",
		function() return SedimentDB.benchStatusText ~= false end,
		function(on) SedimentDB.benchStatusText = on ns.Popup.BenchRefresh() end)

	place(Text(page, "GameFontNormal", "Recent sorts"), GAP_GROUP, 4)
	page.history = {}
	for i = 1, 10 do
		local line = place(Text(page, "GameFontHighlightSmall"), i == 1 and GAP_HELP or 4, 8, true)
		line:SetWordWrap(false)
		page.history[i] = line
	end
	page.refreshers[#page.refreshers + 1] = function()
		local history = SedimentDB.benchHistory or {}
		for i, line in ipairs(page.history) do
			line:SetText(history[i] and ns.Popup.BenchRunText(history[i]) or " ")
		end
	end
end

-- Special bags: which special bags you have, the fill switch, and every keep-out rule (Keep out of special
-- bags: all Cloth, or one item) with x to remove it. Removing doesn't re-sort the list: the row greys out
-- with Undo, so nothing moves under the mouse. Rules are added from the weight popup.
local specialRows = {}

-- A keep-out rule's name, and whether it covers a whole group ("all Cloth") rather than one item.
local function KeepOutLabel(rule)
	if rule.kind == "subclass" then
		local classID, subclassID = rule.key:match("^(%-?%d+):(%-?%d+)$")
		local name = C_Item.GetItemSubClassInfo(tonumber(classID), tonumber(subclassID))
		return "all " .. (name or rule.key), true
	end
	return ItemLabel(rule.key), false
end

local function BuildSpecialPage(page)
	page.refreshers = {}
	local place = Flow(page)
	local bagsText = place(Text(page, "GameFontHighlight"), 0, 4, true)
	page.refreshers[#page.refreshers + 1] = function()
		local names = {}
		for _, b in ipairs(ns.Bags.SpecialBags()) do
			names[#names + 1] = ("%s (%d slots)"):format(b.name, b.slots)
		end
		bagsText:SetText("|cffffd100Your special bags:|r " .. (#names > 0 and table.concat(names, ", ")
			or "none right now (reagent bags and profession bags like herb or mining bags)"))
	end

	CheckRow(page, place, GAP_GROUP, "Fill reagent and profession bags automatically",
		ns.Bags.FillSpecialBags, function(on)
			-- Not "on and nil or false": that's always false, so ticking it never stuck (found 2026-11-25).
			if on then
				SedimentDB.fillSpecialBags = nil -- the default: fill
			else
				SedimentDB.fillSpecialBags = false
			end
			ns.AutoSort.Resume()
		end,
		"Off: " .. N("AddonName") .. " never moves anything into those bags; what's already in them stays and is "
		.. "still sorted there.")

	place(Text(page, "GameFontNormal", L("KeepOutList")), GAP_GROUP, 4)
	local hint = place(HelpText(page, "To add one, Alt+right-click an item (or click it in " .. N("PickMode")
		.. ", in " .. N("SortValues") .. ") and tick a box under " .. L("KeepOutRule") .. "."), GAP_HELP, 4, true)

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -GAP_HELP)
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
		row.undo:SetSize(60, 20)
		row.undo:SetPoint("RIGHT", -2, 0)
		row.undo:SetText(L("UndoButton"))
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

	-- Rebuilt only when the section is shown or the window opens, never while clicking (removal greys a row).
	function Settings.RefreshSpecialList()
		local labelled = {}
		for _, rule in ipairs(ns.Bags.KeepOutRules()) do
			local text, whole = KeepOutLabel(rule)
			labelled[#labelled + 1] = { rule = rule, text = text, whole = whole }
		end
		table.sort(labelled, function(a, b)
			if a.whole ~= b.whole then
				return a.whole -- "all ..." first
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
			row.remove:Hide()
			row.undo:Hide()
			row:Show()
		end
		child:SetHeight(math.max(1, #labelled) * ROW_HEIGHT + 4)
	end
end

-- History: Created and Snapshot entries (Weights.lua), the pinned one first. Each row: Pin / Unpin on the left
-- (far from x), Load and x on the right. x greys the row with Undo; the entry goes for good when the window
-- closes. Hover a row for its rules.
local historyRows = {}

-- A save's rules, light to heavy with the sink line, for its tooltip.
local function VersionTooltip(entry)
	local w, list = entry.weights, {}
	for id, v in pairs(w.items) do list[#list + 1] = { v, ItemLabel(id) } end
	for k, v in pairs(w.flags) do list[#list + 1] = { v, ns.Weights.FlagLabel(k) } end
	for k, v in pairs(w.subclasses) do list[#list + 1] = { v, SubclassLabel(k) } end
	for k, v in pairs(w.classes) do list[#list + 1] = { v, ClassLabel(k) } end
	list[#list + 1] = { w.default, "Not set (default)" }
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local lines, sinkShown = {}, false
	for _, e in ipairs(list) do
		if not sinkShown and e[1] >= w.sinkLine then
			lines[#lines + 1] = "|cffffb040---- " .. L("LootGap") .. " (" .. tostring(w.sinkLine) .. ") ----|r"
			sinkShown = true
		end
		lines[#lines + 1] = ("%s  |cff888888%s|r"):format(e[2], tostring(e[1]))
	end
	if not sinkShown then
		lines[#lines + 1] = "|cffffb040---- " .. L("LootGap") .. " (" .. tostring(w.sinkLine) .. ") ----|r"
	end
	local ko = entry.keepOut or {}
	for k in pairs(ko.subclasses or {}) do
		lines[#lines + 1] = "|cff9ad1ff" .. L("KeepOutList") .. ":|r " .. KeepOutLabel({ kind = "subclass", key = k })
	end
	for k in pairs(ko.items or {}) do
		lines[#lines + 1] = "|cff9ad1ff" .. L("KeepOutList") .. ":|r " .. ItemLabel(k)
	end
	return lines
end

local function HistoryChanged()
	WeightChanged()
	if Settings.RefreshSpecialList then
		Settings.RefreshSpecialList() -- keep-out rules may have come back
	end
end

-- Load: no "are you sure?" (user, 2026-11-25): it saves the rules in use first, and Previous marks the way back.
local historyRedrawn = 0 -- rows shift after a load; ignore Load clicks right after a redraw (a double-click
                         -- would otherwise load the save just made, undoing the first)

local function LoadSave(entry)
	if not entry or entry.deleted or GetTime() - historyRedrawn < CLICK_GUARD then
		return
	end
	ns.Weights.LoadVersion(entry)
	HistoryChanged()
end

local HISTORY_ROW = 36

local function BuildHistoryPage(page)
	page.refreshers = {}
	local place = Flow(page)
	local help = place(HelpText(page, N("AddonName") .. " takes a " .. L("EntrySnapshot") .. " of your rules "
		.. "when you log out and before " .. B("LoadSaveButton") .. " or " .. B("ClearAllButton") .. ", if they've "
		.. "changed; finishing " .. N("Onboarding") .. " adds a " .. L("EntryCreated") .. " entry. "
		.. B("KeepSaveButton") .. " one to keep it at the top; of the rest, the newest 20 are kept. Hover an entry "
		.. "to see its rules."), 0, 4, true)

	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -GAP_HELP - 4)
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
		-- Pin / Unpin on the left, far from x (user, 2026-11-25).
		row.pin = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.pin:SetSize(60, 20)
		row.pin:SetPoint("LEFT", 4, 0)
		row.pin:SetScript("OnClick", function()
			local entry = row.entry
			if not entry or entry.deleted then
				return
			end
			if entry.pinned then
				ns.Weights.Unpin(entry)
			else
				ns.Weights.Pin(entry) -- one pin: this replaces any other
			end
			Settings.Refresh()
		end)
		row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.title:SetPoint("TOPLEFT", row.pin, "TOPRIGHT", 10, 5)
		row.title:SetJustifyH("LEFT")
		row.title:SetWordWrap(false)
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.info:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
		row.info:SetJustifyH("LEFT")
		row.info:SetWordWrap(false)
		-- x marks the save; Undo takes it back (until the window closes).
		row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
		row.remove:SetSize(20, 20)
		row.remove:SetPoint("RIGHT", -2, 0)
		row.remove:SetScript("OnClick", function()
			if row.entry and not row.entry.deleted then
				ns.Weights.DeleteVersion(row.entry)
				Settings.Refresh()
			end
		end)
		row.undo = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.undo:SetSize(60, 20)
		row.undo:SetPoint("RIGHT", -2, 0)
		row.undo:SetText(L("UndoButton"))
		row.undo:SetScript("OnClick", function()
			if row.entry and row.entry.deleted then
				ns.Weights.UndeleteVersion(row.entry)
				Settings.Refresh()
			end
		end)
		row.load = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.load:SetSize(60, 20)
		row.load:SetPoint("RIGHT", -66, 0)
		row.load:SetText(L("LoadSaveButton"))
		row.load:SetScript("OnClick", function()
			LoadSave(row.entry)
		end)
		row.title:SetPoint("RIGHT", row.load, "LEFT", -8, 0)
		row.info:SetPoint("RIGHT", row.load, "LEFT", -8, 0)
		row:SetScript("OnEnter", function(self)
			if not self.entry then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, ns.Weights.EntryTitle(self.entry))
			if self.entry.pinned then
				GameTooltip_AddNormalLine(GameTooltip, N("KeptSave") .. ": stays at the top and is never dropped. "
					.. B("UnkeepSaveButton") .. " to let it go.")
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
		historyRedrawn = GetTime()
		local h = ns.Weights.HistoryForDisplay()
		local previous = ns.Weights.PreviousSave()
		for i, entry in ipairs(h) do
			local row = Row(i)
			row.entry = entry
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 0, -(i - 1) * (HISTORY_ROW + 3))
			local current = ns.Weights.IsCurrent(entry)
			local title = ns.Weights.EntryTitle(entry)
			if entry.deleted then
				row.title:SetText(title .. "  |cff888888(deleted)|r")
				row.title:SetTextColor(0.5, 0.5, 0.5)
			elseif entry.pinned then
				row.title:SetText(title) -- the Unpin button already says it's pinned (user, 2026-11-25)
				row.title:SetTextColor(1, 1, 1)
			else
				row.title:SetText(title)
				row.title:SetTextColor(0.8, 0.8, 0.8)
			end
			-- Tags first (at the end, a long summary cut them off): Active = the rules in use, Previous = the
			-- newest save that isn't, i.e. what to roll back to (user, 2026-11-25).
			local tag = ""
			if current then
				tag = "|cff66ff66" .. L("SaveInUse") .. "|r  ·  "
			elseif entry == previous then
				tag = "|cff9ad1ff" .. L("SaveBefore") .. "|r  ·  "
			end
			row.info:SetText(tag .. ns.Weights.VersionSummary(entry)) -- the time is in the title
			row.pin:SetText(entry.pinned and L("UnkeepSaveButton") or L("KeepSaveButton"))
			row.pin:SetEnabled(not entry.deleted)
			row.pin:Show()
			row.load:SetEnabled(not current and not entry.deleted)
			row.load:Show()
			row.remove:SetShown(not entry.deleted)
			row.undo:SetShown(entry.deleted and true or false)
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
			row.pin:Hide()
			row.load:Hide()
			row.remove:Hide()
			row.undo:Hide()
			row:Show()
		end
		child:SetHeight(math.max(1, #h) * (HISTORY_ROW + 3) + 4)
	end
end

-- Files (debug mode): the version the game read from the .toc, and every file Sediment expects with whether
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
	if (name == "Testing" or name == "Commands" or name == "Files") and not SedimentDB.testingTools then
		name = "Weights"
	end
	for key, page in pairs(pages) do
		page:SetShown(key == name)
	end
	for key, entry in pairs(tabs) do
		entry.selected:SetShown(key == name)
		entry.text:SetTextColor(key == name and 1 or 0.9, key == name and 0.82 or 0.9, key == name and 0 or 0.9)
	end
	if frame.pageTitle then
		frame.pageTitle:SetText(SectionLabel(name))
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
		-- A solid texture: the tooltip background art is translucent itself, so the world showed through.
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 1) -- opaque: at 0.96 nameplates showed through the text
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
		GameTooltip_AddNormalLine(GameTooltip, "What it does, and " .. N("Onboarding") .. ".")
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
			entry.text:SetText(SectionLabel(name))
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
	rule:SetPoint("TOPLEFT", CONTENT_X, -66)
	rule:SetPoint("RIGHT", -14, 0)
	for _, group in ipairs(NAV_GROUPS) do
		for _, name in ipairs(group.items) do
			local page = CreateFrame("Frame", nil, frame)
			page:SetPoint("TOPLEFT", CONTENT_X, -80)
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
	BuildFilesPage(pages.Files)
	frame:SetScript("OnShow", function()
		Settings.Refresh()
	end)
	frame:SetScript("OnHide", function()
		Settings.SetSelectMode(false) -- select mode never outlives the window
		ns.Weights.PurgeDeleted() -- History saves marked with x go for good now
	end)
	ShowTab("Weights")
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
	if pages.Files:IsShown() then
		RunRefreshers(pages.Files)
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

-- tab: a section name; nil keeps the last one (Weights the first time).
function Settings.Open(tab)
	if InCombatLockdown() then
		Print("settings are closed during combat.")
		return
	end
	if not frame then
		Build()
	end
	frame:Show()
	ShowTab(tab or Settings.currentTab or "Weights")
end

-- The gear on the bag and /sed: the setup questions' first page while there are no rules or a run isn't
-- finished (unless "Don't show" is ticked), else the Weights section. (User, 2026-11-25: ideally nobody
-- needs the Sorting section; its defaults should just be right.)
function Settings.OpenDefault()
	if InCombatLockdown() then
		Print("settings are closed during combat.")
		return
	end
	if ns.Setup.IsShown() then
		ns.Setup.Raise()
	elseif ns.Setup.Wanted() then
		ns.Setup.ShowIntro()
	else
		Settings.Open("Weights")
	end
end

-- /sed: close whichever is open, else open the default.
function Settings.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	elseif ns.Setup.IsShown() then
		ns.Setup.Close()
	else
		Settings.OpenDefault()
	end
end
