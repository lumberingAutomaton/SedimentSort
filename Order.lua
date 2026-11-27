-- Order: the settings window's Order section, the one place to arrange Sediment (user, 2026-11-25: it replaced
-- both the Weights page, where rules were numbers, and the separate Setup window).
--
-- The list shows every rule as a row, top to bottom the way the bags sort, with the Empty Space among them.
-- Drag a row to move it: press anywhere on it and move the mouse a little; Sediment watches the press itself
-- rather than WoW's drag start, which was hard to trigger (user, 2026-11-25; a grip at each row's left went
-- too, unneeded once this worked). Clicking a row outlines its items in the bags (gold) and lists ways to widen it in the right
-- column ("all Armor/Cloth", "all Armor", "all BoE Gear"; hovering a choice outlines what it would cover).
-- Items with nothing set are outlined orange and stay attached to the Empty Space (Weights.PinDefault);
-- selecting the Empty Space outlines them. The bags sort on every change. x removes a row: it stays greyed in
-- place with Undo until the list next changes or the section closes.
--
-- Select Mode is on whenever the list shows, until its button ("Select Mode: On") turns it off: hovering a bag
-- item lights up the row that sorts it; clicking one adds a row for it right above that row, selected.
--
-- With no rules, or after ?, a welcome panel covers the list (it sits over it, so nothing shifts) with Start
-- Fresh: save the rules to History, lay out the default order (Weights.DefaultOrder), add a Created entry, and
-- turn on Blizzard's Combined Backpack if it's off (Sediment sorts in its order). The numbers behind the rows
-- are still stored; the page never shows them.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Order.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Order = {}
ns.Order = Order
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)

local ROW_HEIGHT = 20
local SIDE_W = 206 -- the column right of the list: the Select Mode button and the selected row's widen choices
local DRAG_START = 5 -- pixels the mouse moves, pressed on a row, before it drags
local GAP_ID = "gap" -- the Empty Space row's id
local UNSET_COLOR = { 1, 0.5, 0.1 } -- orange, like the outlines in the bags
local CLICK_GUARD = 0.3

local pane            -- the Settings page this was built into
local listW           -- the list's width
local selected        -- the selected row: a rule id, or GAP_ID
local orderList       -- the ranking list as last drawn
local rows, child = {}, nil
local ghosts = {}     -- rows removed with x, shown greyed with Undo: { position, label, icon, rules = { { kind, key, weight } } }
local picking = false -- Select Mode, with our click and hover handlers
local pickWanted = true -- on whenever the list shows, unless its button turned it off (until the section reopens)
local hoverRule       -- a widen choice under the mouse: outline what it would cover
local bagHover        -- the row lit up for the bag item under the mouse
local scrollToSelected = false -- after a pick or a move: bring the selected row into view
local press           -- a press on a row that may become a drag: { row, x, y }
local dragging        -- the row being dragged: its position among the shown rows
local dropTime = 0    -- the click that ends a drag isn't a click on the row
local welcomeForced = false -- ? shows the welcome even with rules
local notice          -- a one-off line under the list ("turned on Combined Backpack")
local lastDraw = 0    -- clicks on rows right after the rows changed are ignored (they may have moved)

local function RuleId(kind, key)
	return kind == "default" and "default" or (kind .. ":" .. tostring(key))
end

-- Any weight rules (items, flags, subclasses, classes)? Keep-out rules don't count.
local function HasWeightRules()
	local w = SedimentDB.weights
	return next(w.items) ~= nil or next(w.flags) ~= nil or next(w.subclasses) ~= nil or next(w.classes) ~= nil
end

local function Shown()
	return pane ~= nil and pane:IsVisible()
end

-- A change to the rules: refresh what shows them, and sort now so the bags show the outcome.
local function AfterChange()
	lastDraw = GetTime() -- the rows are about to change under the mouse
	ns.Popup.Refresh()
	ns.Settings.RefreshOverlays()
	ns.Sort.StartSoon()
end

-- The item classes that have items in the bags with nothing set, in class order.
local function UnsetClasses()
	local seen, list = {}, {}
	for _, s in ipairs(ns.Bags.Read()) do
		local item = s.item
		if item and not seen[item.classID] and not ns.Weights.HasOwnRule(item) then
			seen[item.classID] = true
			list[#list + 1] = item.classID
		end
	end
	table.sort(list)
	return list
end

local function UnsetCount()
	local n = 0
	for _, s in ipairs(ns.Bags.Read()) do
		if s.item and not ns.Weights.HasOwnRule(s.item) then
			n = n + 1
		end
	end
	return n
end

-- Rows ------------------------------------------------------------------------------------------------

local function RungLabel(e)
	for _, r in ipairs(e.rules) do
		if r.kind == "flag" and r.key == "quest" then
			return ns.Weights.FlagLabel("quest") -- the Quest Items row holds the quest flag and the Quest category
		end
	end
	local names, icon = {}, nil
	for _, r in ipairs(e.rules) do
		local label, ic = ns.Settings.RuleLabel(r.kind, r.key)
		names[#names + 1] = label
		icon = icon or ic
	end
	return table.concat(names, ", "), icon
end

local function IsUnsetRung(e)
	return e.rules and #e.rules == 1 and e.rules[1].kind == "default"
end

local function RowId(e)
	if e.divider then
		return GAP_ID
	end
	return RuleId(e.rules[1].kind, e.rules[1].key)
end

local function IndexOf(id)
	for i, e in ipairs(orderList or {}) do
		if not IsUnsetRung(e) and RowId(e) == id then
			return i
		end
	end
end

-- The row holding a rule (a row can hold two: Quest Items holds the quest flag and the Quest group); "not
-- set" is the Empty Space's, where those items are attached.
local function RowIdOfRule(kind, key)
	if kind == "default" then
		return GAP_ID
	end
	for _, e in ipairs(orderList or ns.Weights.PinDefault(ns.Weights.RankingList())) do
		if e.rules and not IsUnsetRung(e) then
			for _, r in ipairs(e.rules) do
				if r.kind == kind and r.key == key then
					return RowId(e)
				end
			end
		end
	end
end

-- The selected row's rule, when it holds just one (the Empty Space and two-rule rows: none).
local function SelectedRule()
	local i = selected and selected ~= GAP_ID and IndexOf(selected)
	local e = i and orderList[i]
	if e and e.rules and #e.rules == 1 then
		return e.rules[1]
	end
end

-- Would this rule decide the item? Only if nothing more specific does (ignoring the selected rule, which a
-- widen choice replaces).
local function WouldCover(rule, item)
	local sel = SelectedRule()
	for _, level in ipairs(ns.Weights.Explain(item)) do
		if level.kind == rule.kind and level.key == rule.key then
			return level.applies
		end
		local replaced = sel and level.kind == sel.kind and level.key == sel.key
		if level.applies and level.weight ~= nil and not replaced then
			return false
		end
	end
	return false
end

-- Gold outlines: a hovered widen choice's items; else the selected row's items (for the Empty Space, the
-- items with nothing set, which are attached to it).
local function Focus(item)
	if hoverRule then
		return WouldCover(hoverRule, item)
	end
	if selected == GAP_ID then
		return not ns.Weights.HasOwnRule(item)
	end
	local i = selected and IndexOf(selected)
	local rung = i and orderList[i]
	if not rung or not rung.rules then
		return false
	end
	local levels, winner = ns.Weights.Explain(item)
	local won = RuleId(levels[winner].kind, levels[winner].key)
	for _, r in ipairs(rung.rules) do
		if RuleId(r.kind, r.key) == won then
			return true
		end
	end
	return false
end

-- Drag and drop -----------------------------------------------------------------------------------------
-- Drag any row, the Empty Space included; a gold line shows where it will land; the list scrolls near its
-- edges. While dragging, only the line marks the spot: the rows' hover glow is off and the dragged row is
-- dimmed (user, 2026-11-25: the glow made the line hard to see). (Move Up / Move Down went: drag does it.)

-- Where a drop at the cursor would go: 0 = above the first row ... n = below the last.
local function DropSlot()
	local _, y = GetCursorPosition()
	y = y / child:GetEffectiveScale()
	local top = child:GetTop()
	if not top then
		return nil
	end
	local slot = math.floor((top - y) / ROW_HEIGHT + 0.5)
	return math.max(0, math.min(pane.rowCount or 0, slot))
end

local function DragUpdate()
	local slot = DropSlot()
	if slot then
		pane.dropLine:ClearAllPoints()
		pane.dropLine:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -slot * ROW_HEIGHT + 2)
		pane.dropLine:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		pane.dropLine:Show()
	end
	local _, y = GetCursorPosition()
	y = y / pane.scroll:GetEffectiveScale()
	local top, bottom = pane.scroll:GetTop(), pane.scroll:GetBottom()
	if top and bottom then
		local cur, range = pane.scroll:GetVerticalScroll(), pane.scroll:GetVerticalScrollRange()
		if y > top - ROW_HEIGHT and cur > 0 then
			pane.scroll:SetVerticalScroll(math.max(0, cur - 4))
		elseif y < bottom + ROW_HEIGHT and cur < range then
			pane.scroll:SetVerticalScroll(math.min(range, cur + 4))
		end
	end
end

local function DragLook(on)
	for _, row in ipairs(rows) do
		local glow = row:GetHighlightTexture()
		if glow then
			glow:SetAlpha(on and 0 or 1)
		end
		row:SetAlpha(on and row.position == dragging and 0.4 or 1)
	end
end

local function DragStop()
	press = nil
	pane:SetScript("OnUpdate", nil)
	if not dragging then
		return
	end
	DragLook(false)
	local from, slot = dragging, DropSlot()
	dragging, dropTime = nil, GetTime()
	pane.dropLine:Hide()
	if slot then
		-- A slot just above or just below the row itself leaves it where it is.
		local to = slot < from - 1 and slot + 1 or slot > from and slot or nil
		if to and ns.Weights.MoveRow(from, to) then
			ghosts, scrollToSelected = {}, true
			AfterChange()
		end
	end
	Order.Refresh()
end

local function StartDrag(row)
	press = nil
	if dragging or not row.id then
		return
	end
	selected, dragging, hoverRule = row.id, row.position, nil
	Order.Refresh() -- dims the row (Refresh keeps the drag look)
end

-- Every frame while a row is pressed: drag once the mouse has moved a little, follow it, and drop when the
-- button comes up wherever the mouse is (the row may not get the release).
local function PressUpdate()
	if not IsMouseButtonDown("LeftButton") then
		DragStop()
		return
	end
	if press and not dragging then
		local x, y = GetCursorPosition()
		if math.abs(x - press.x) + math.abs(y - press.y) >= DRAG_START then
			StartDrag(press.row)
		end
	end
	if dragging then
		DragUpdate()
	end
end

local function Press(row)
	if not row.id or dragging then
		return
	end
	local x, y = GetCursorPosition()
	press = { row = row, x = x, y = y }
	pane:SetScript("OnUpdate", PressUpdate)
end

-- Removing (x) and Undo --------------------------------------------------------------------------------

local function Remove(row)
	local i = row.id and IndexOf(row.id)
	local e = i and orderList[i]
	if not e or not e.rules or GetTime() - lastDraw < CLICK_GUARD then
		return
	end
	local w = SedimentDB.weights
	local ghost = { position = row.position, rules = {} }
	ghost.label, ghost.icon = RungLabel(e)
	for _, r in ipairs(e.rules) do
		local tbl = r.kind == "item" and w.items or r.kind == "flag" and w.flags or r.kind == "subclass" and w.subclasses
			or w.classes
		ghost.rules[#ghost.rules + 1] = { kind = r.kind, key = r.key, weight = tbl[r.key] }
		ns.Weights.SetLevel(r.kind, r.key, nil)
	end
	ghosts[#ghosts + 1] = ghost
	if selected == row.id then
		selected = nil
	end
	AfterChange()
	Order.Refresh()
end

local function Undo(ghost)
	for _, r in ipairs(ghost.rules) do
		ns.Weights.SetLevel(r.kind, r.key, r.weight)
	end
	for n, g in ipairs(ghosts) do
		if g == ghost then
			table.remove(ghosts, n)
			break
		end
	end
	AfterChange()
	Order.Refresh()
end

-- Select Mode ------------------------------------------------------------------------------------------

local function OnPick(bag, slot)
	local item = ns.Bags.ReadSlot(bag, slot)
	if not item then
		return
	end
	if ns.Weights.AddRuleAbove("item", item.itemID, item) then
		ghosts = {}
		AfterChange()
	end
	-- (If it already had a row, that row is just selected.)
	selected, scrollToSelected, notice, hoverRule = RuleId("item", item.itemID), true, nil, nil
	Order.Refresh()
end

-- Bring a row into view, if it isn't.
local function ScrollTo(id)
	for r, row in ipairs(rows) do
		if row:IsShown() and row.id == id then
			local rowTop, view = (r - 1) * ROW_HEIGHT, pane.scroll:GetHeight()
			local cur = pane.scroll:GetVerticalScroll()
			if rowTop < cur then
				pane.scroll:SetVerticalScroll(rowTop)
			elseif view and view > 0 and rowTop + ROW_HEIGHT > cur + view then
				pane.scroll:SetVerticalScroll(rowTop + ROW_HEIGHT - view)
			end
			return
		end
	end
end

-- The bag item under the mouse: light up the row that sorts it (the Empty Space for items not set yet).
local function ShowBagHover()
	for _, row in ipairs(rows) do
		if row:IsShown() and row.id and row.id == bagHover then
			row:LockHighlight()
		else
			row:UnlockHighlight()
		end
	end
end

local function OnHover(bag, slot)
	local item = bag and ns.Bags.ReadSlot(bag, slot)
	bagHover = nil
	if item then
		local levels, winner = ns.Weights.Explain(item)
		bagHover = RowIdOfRule(levels[winner].kind, levels[winner].key)
	end
	ShowBagHover()
	if bagHover and not dragging then
		ScrollTo(bagHover)
	end
end

local function StopPicking()
	if picking then
		picking = false
		if ns.Settings.IsSelecting() then
			ns.Settings.SetSelectMode(false)
		end
	end
	bagHover = nil
end

-- Select Mode is on while the list shows (not under the welcome), unless its button turned it off.
local function SyncPicking(showWelcome)
	local want = pickWanted and not showWelcome and Shown() and not InCombatLockdown()
	if want and not picking then
		picking = true
		ns.Settings.SetSelectMode(true, OnPick, OnHover)
	elseif not want and picking then
		StopPicking()
	end
end

local function TogglePicking()
	pickWanted = not picking
	Order.Refresh()
end

-- Ways to widen the selected row: an item to "all Armor/Cloth", "all Armor", or a flag it has ("all BoE Gear");
-- a group/part to its group. Groups and flags are as wide as it gets. A part named like its group
-- ("Quest/Quest") isn't offered: it's the group.
local function WidenChoices(rule)
	local list = {}
	local function Add(kind, key)
		-- Named exactly like the row it makes or joins (user, 2026-11-25: no "all"; hovering a choice outlines
		-- everything it would cover).
		list[#list + 1] = { kind = kind, key = key, label = (ns.Settings.RuleLabel(kind, key)) }
	end
	if rule.kind == "item" then
		local item
		for _, s in ipairs(ns.Bags.Read()) do
			if s.item and s.item.itemID == rule.key then
				item = s.item
				break
			end
		end
		local classID, subclassID
		if item then
			classID, subclassID = item.classID, item.subclassID
		else
			local _, _, _, _, _, c, sc = C_Item.GetItemInfoInstant(rule.key) -- not in the bags: no flags
			classID, subclassID = c, sc
		end
		if classID and subclassID then
			local subKey = classID .. ":" .. subclassID
			if not ns.Settings.PartSameAsGroup(subKey) then
				Add("subclass", subKey)
			end
			Add("class", classID)
		end
		if item then
			local flags = ns.Weights.ItemFlags(item)
			for _, f in ipairs(ns.Weights.FLAG_ORDER) do
				if flags[f] then
					Add("flag", f)
				end
			end
		end
	elseif rule.kind == "subclass" then
		local c = tonumber(tostring(rule.key):match("^(%d+):"))
		if c then
			Add("class", c)
		end
	end
	return list
end

local function Widen(choice)
	local rule = SelectedRule()
	if not rule or not choice then
		return
	end
	ns.Weights.ReplaceRule(rule.kind, rule.key, choice.kind, choice.key)
	hoverRule, ghosts, notice = nil, {}, nil
	orderList = ns.Weights.PinDefault(ns.Weights.RankingList())
	selected, scrollToSelected = RowIdOfRule(choice.kind, choice.key), true
	AfterChange()
	Order.Refresh()
end

-- Start Fresh ------------------------------------------------------------------------------------------

-- Sediment's top-to-bottom order is the Combined Backpack's, so Start Fresh turns Blizzard's Combined Backpack
-- on if it's off (user, 2026-11-25: when they start, never at login): the call Blizzard's own bag menu makes.
local function EnsureCombinedBackpack()
	if GetCVar("combinedBags") ~= nil and not GetCVarBool("combinedBags") then
		SetCVar("combinedBags", 1)
		return true
	end
	return false
end

-- Save the rules to History (if not saved), clear them (Weights and keep-out rules), lay out the default order
-- with the bags' other kinds of items above the Empty Space, and add a Created entry to History.
function Order.StartFresh()
	if InCombatLockdown() then
		return
	end
	ns.Weights.ClearAll()
	ns.Weights.DefaultOrder(UnsetClasses())
	ns.Weights.Created()
	selected, ghosts, welcomeForced = nil, {}, false
	if EnsureCombinedBackpack() then
		notice = N("AddonName") .. " turned on Blizzard's Combined Backpack: it sorts in that window's order."
		ns.Print(notice)
	end
	if ns.Settings.RefreshSpecialList then
		ns.Settings.RefreshSpecialList() -- keep-out rules were cleared
	end
	AfterChange()
	Order.Refresh()
end

-- Building -----------------------------------------------------------------------------------------------

local function Button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, 22)
	b:SetText(text)
	return b
end

local function Row(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, child)
	row:SetSize(listW, ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 0.82, 0, 0.25)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 4, 0)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	-- The Empty Space row: a line either side of its label.
	row.lines = {}
	for k = 1, 2 do
		local t = row:CreateTexture(nil, "ARTWORK")
		t:SetHeight(2)
		t:SetColorTexture(0.9, 0.6, 0.2, 0.9)
		row.lines[k] = t
	end
	row.lines[1]:SetPoint("LEFT", 4, 0)
	row.lines[1]:SetPoint("RIGHT", row.label, "LEFT", -6, 0)
	row.lines[2]:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
	row.lines[2]:SetPoint("RIGHT", -26, 0)
	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(20, 20)
	row.remove:SetPoint("RIGHT", -2, 0)
	row.remove:SetScript("OnClick", function()
		Remove(row)
	end)
	row.undo = Button(row, L("UndoButton"), 60)
	row.undo:SetHeight(18)
	row.undo:SetPoint("RIGHT", -2, 0)
	row.undo:SetScript("OnClick", function()
		if row.ghost then
			Undo(row.ghost)
		end
	end)
	row:SetScript("OnClick", function(self)
		local now = GetTime()
		if self.id and not dragging and now - lastDraw >= CLICK_GUARD and now - dropTime >= CLICK_GUARD then
			selected, hoverRule, notice = self.id, nil, nil
			Order.Refresh()
		end
	end)
	-- Anywhere on the row: a press drags once the mouse moves a little (PressUpdate); a press and release in
	-- place is a click.
	row:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			Press(self)
		end
	end)
	row:SetScript("OnMouseUp", function()
		if dragging then
			DragStop()
		end
	end)
	rows[i] = row
	return row
end

function Order.Build(page, width)
	pane = page
	Order.pane = page -- for dev/setup_check.lua
	pane.refreshers = pane.refreshers or {}
	local columnX = width - SIDE_W
	listW = columnX - 34

	pane.help = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.help:SetPoint("TOPLEFT", 4, 0)
	pane.help:SetPoint("RIGHT", -8, 0)
	pane.help:SetJustifyH("LEFT")
	pane.help:SetText("Top to bottom, the way your bags sort. Drag a row to move it; click one to outline its items "
		.. "in your bags. Put the " .. N("LootGap") .. " where new loot should land; whatever isn't set yet stays next "
		.. "to it, outlined orange. While " .. N("SelectMode") .. " is on, hover an item in your bags to find its "
		.. "row, or click it to give it a row of its own.")

	-- "N items in your bags aren't ordered yet", orange; its space is always kept, so nothing below shifts.
	pane.unset = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pane.unset:SetPoint("TOPLEFT", pane.help, "BOTTOMLEFT", 0, -10)
	pane.unset:SetPoint("RIGHT", -8, 0)
	pane.unset:SetHeight(16)
	pane.unset:SetJustifyH("LEFT")
	pane.unset:SetTextColor(UNSET_COLOR[1], UNSET_COLOR[2], UNSET_COLOR[3])

	local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", pane.unset, "BOTTOMLEFT", 0, -6)
	scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", columnX - 26, 34) -- down to Start Fresh
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(listW, 100)
	scroll:SetScrollChild(child)
	pane.scroll = scroll
	pane.dropLine = child:CreateTexture(nil, "OVERLAY", nil, 7)
	pane.dropLine:SetHeight(3)
	pane.dropLine:SetColorTexture(1, 0.9, 0.3, 1)
	pane.dropLine:Hide()

	-- Right of the list: the Select Mode button, then the selected row's widen choices ("Sort Mageweave Cloth as:"
	-- and a button for each), or a one-off notice.
	local colW = SIDE_W - 16
	pane.pick = Button(pane, "", colW)
	pane.pick:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 30, 0)
	pane.pick:SetScript("OnClick", TogglePicking)
	pane.widenLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pane.widenLabel:SetPoint("TOPLEFT", pane.pick, "BOTTOMLEFT", 0, -18)
	pane.widenLabel:SetWidth(colW)
	pane.widenLabel:SetJustifyH("LEFT")
	pane.widen = {}
	for k = 1, 6 do
		local b = Button(pane, "", colW)
		b:SetPoint("TOPLEFT", pane.widenLabel, "BOTTOMLEFT", 0, -6 - (k - 1) * 26)
		b:SetScript("OnClick", function(self) Widen(self.choice) end)
		b:SetScript("OnEnter", function(self)
			hoverRule = self.choice
			ns.Settings.RefreshOverlays()
		end)
		b:SetScript("OnLeave", function()
			hoverRule = nil
			ns.Settings.RefreshOverlays()
		end)
		pane.widen[k] = b
	end

	-- Start Fresh, bottom left (asks first: it replaces your rules).
	pane.fresh = Button(pane, L("ClearAllButton"), 130)
	pane.fresh:SetHeight(24)
	pane.fresh:SetPoint("BOTTOMLEFT", 2, 4)
	pane.fresh:SetScript("OnClick", function()
		StaticPopup_Show("SEDIMENT_START_FRESH")
	end)

	-- The welcome: over the list while there are no rules, or after ?. It covers the list rather than pushing
	-- it down, so nothing shifts when it goes.
	local welcome = CreateFrame("Frame", nil, pane, "BackdropTemplate")
	welcome:SetPoint("TOPLEFT", pane.help, "TOPLEFT", -4, 4)
	welcome:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 34)
	welcome:SetFrameLevel(pane:GetFrameLevel() + 20)
	welcome:EnableMouse(true)
	welcome:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
	welcome:SetBackdropColor(0.05, 0.05, 0.05, 1)
	local wtitle = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	wtitle:SetPoint("TOPLEFT", 8, -8)
	wtitle:SetText("Your bags, always in your order")
	local wbody = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	wbody:SetPoint("TOPLEFT", wtitle, "BOTTOMLEFT", 0, -12)
	wbody:SetPoint("RIGHT", -12, 0)
	wbody:SetJustifyH("LEFT")
	wbody:SetSpacing(3)
	wbody:SetText(N("AddonName") .. " keeps your bags sorted all the time, quietly, while they're closed. You "
		.. "decide the order, and where the " .. N("LootGap") .. " goes: new loot lands there, so you always see "
		.. "what's new.\n\n"
		.. "Nothing ever moves in combat.\n\n"
		.. B("ClearAllButton") .. " lays out a common order to start from. Then drag the rows until your bags look "
		.. "right; they sort as you go. Alt+right-click any bag item to see what decides where it goes.")
	welcome.fresh = Button(welcome, L("ClearAllButton"), 140)
	welcome.fresh:SetHeight(26)
	welcome.fresh:SetPoint("TOPLEFT", wbody, "BOTTOMLEFT", 0, -16)
	welcome.fresh:SetScript("OnClick", function()
		if HasWeightRules() then
			StaticPopup_Show("SEDIMENT_START_FRESH")
		else
			Order.StartFresh()
		end
	end)
	welcome.close = Button(welcome, L("CloseButton"), 90)
	welcome.close:SetPoint("LEFT", welcome.fresh, "RIGHT", 10, 0)
	welcome.close:SetScript("OnClick", function()
		welcomeForced = false
		Order.Refresh()
	end)
	welcome:Hide()
	pane.welcome = welcome
end

-- Drawing ------------------------------------------------------------------------------------------------

function Order.Refresh()
	if not pane then
		return
	end
	local n = UnsetCount()
	pane.unset:SetText(n > 0 and ("%d item%s in your bags %s ordered yet."):format(n, n == 1 and "" or "s",
		n == 1 and "isn't" or "aren't") or "")

	local showWelcome = welcomeForced or not HasWeightRules()
	pane.welcome:SetShown(showWelcome)
	pane.welcome.close:SetShown(HasWeightRules())

	orderList = ns.Weights.PinDefault(ns.Weights.RankingList())
	if selected and not IndexOf(selected) then
		selected = nil
	end
	-- The shown rows: every rung but the unset items', plus ghosts (removed rows with Undo) at their places.
	local shown = {}
	for _, e in ipairs(orderList) do
		if not IsUnsetRung(e) then
			shown[#shown + 1] = { entry = e }
		end
	end
	table.sort(ghosts, function(a, b) return a.position < b.position end)
	for _, g in ipairs(ghosts) do
		table.insert(shown, math.min(g.position, #shown + 1), { ghost = g })
	end
	local k, past, position = 0, false, 0
	for _, s in ipairs(shown) do
		k = k + 1
		local row = Row(k)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(k - 1) * ROW_HEIGHT)
		row:Show()
		row:SetAlpha(1)
		row.label:ClearAllPoints()
		row.ghost = s.ghost
		if s.ghost then
			row.id, row.position = nil, nil
			row.selected:Hide()
			row.lines[1]:Hide()
			row.lines[2]:Hide()
			row.icon:SetShown(s.ghost.icon ~= nil)
			if s.ghost.icon then
				row.icon:SetTexture(s.ghost.icon)
			end
			row.label:SetPoint("LEFT", 24, 0)
			row.label:SetPoint("RIGHT", -66, 0)
			row.label:SetText(s.ghost.label)
			row.label:SetTextColor(0.45, 0.45, 0.45)
			row.remove:Hide()
			row.undo:Show()
		else
			local e = s.entry
			position = position + 1
			row.id, row.position = RowId(e), position
			row.selected:SetShown(row.id == selected)
			row.undo:Hide()
			if e.divider then
				past = true
				row.icon:Hide()
				row.lines[1]:Show()
				row.lines[2]:Show()
				row.label:SetPoint("CENTER", -10, 0)
				row.label:SetText(L("LootGap"))
				row.label:SetTextColor(1, 0.7, 0.3)
				row.remove:Hide()
			else
				local label, icon = RungLabel(e)
				row.lines[1]:Hide()
				row.lines[2]:Hide()
				row.icon:SetShown(icon ~= nil)
				if icon then
					row.icon:SetTexture(icon)
				end
				row.label:SetPoint("LEFT", 24, 0)
				row.label:SetPoint("RIGHT", -26, 0)
				row.label:SetText(label)
				if past then
					row.label:SetTextColor(0.8, 0.7, 0.55)
				else
					row.label:SetTextColor(0.9, 0.9, 0.9)
				end
				row.remove:Show()
			end
		end
	end
	for r = k + 1, #rows do
		rows[r]:Hide()
		rows[r].id, rows[r].ghost = nil, nil
	end
	child:SetHeight(k * ROW_HEIGHT + 4)
	pane.rowCount = position
	-- Bring the selected row into view after a pick or a move.
	if scrollToSelected and selected then
		scrollToSelected = false
		ScrollTo(selected)
	end
	DragLook(dragging ~= nil) -- a redraw mid-drag keeps the dragged row dimmed
	ShowBagHover()
	SyncPicking(showWelcome)
	-- The state, not the action (user, 2026-11-25: "Pick from Bags" / "Stop Picking" read badly once it was
	-- on by default).
	pane.pick:SetText(L("SelectMode") .. (picking and ": On" or ": Off"))

	local rule = SelectedRule()
	local choices = rule and WidenChoices(rule) or {}
	if #choices > 0 then
		pane.widenLabel:SetText("Sort " .. RungLabel(orderList[IndexOf(selected)]) .. " as:")
		pane.widenLabel:SetTextColor(1, 0.82, 0)
	else
		pane.widenLabel:SetText(notice or "")
		pane.widenLabel:SetTextColor(0.4, 1, 0.4)
	end
	for m, b in ipairs(pane.widen) do
		b.choice = choices[m]
		b:SetShown(choices[m] ~= nil)
		if choices[m] then
			b:SetText(choices[m].label)
		end
	end
	if Shown() then
		ns.Settings.SetHighlight(true, Focus) -- orange: not set yet; gold: the selected row's items
	end
end

-- The settings window shows the section: open the bags (the outlines are the point) and draw.
function Order.OnShow()
	if not InCombatLockdown() then
		OpenAllBags()
	end
	pickWanted = true -- Select Mode is on each time the section opens
	Order.Refresh()
	ns.Settings.SetHighlight(true, Focus)
end

-- The section or the window closes: stop picking, no outlines, removed rows are final.
function Order.OnHide()
	StopPicking()
	ghosts, notice, dragging, press, hoverRule = {}, nil, nil, nil, nil
	pane:SetScript("OnUpdate", nil)
	pane.dropLine:Hide()
	ns.Settings.SetHighlight(false)
end

-- Select a rule's row and bring it into view (the weight popup's Settings button: the row deciding that item).
function Order.Select(kind, key)
	orderList = ns.Weights.PinDefault(ns.Weights.RankingList())
	selected = RowIdOfRule(kind, key)
	scrollToSelected, hoverRule = true, nil
	Order.Refresh()
end

-- The name of the row holding a rule, as the list shows it (the weight popup: "Sorted as Quest Items").
function Order.RowLabel(kind, key)
	for _, e in ipairs(ns.Weights.RankingList()) do
		for _, r in ipairs(e.rules or {}) do
			if r.kind == kind and r.key == key then
				return (RungLabel(e))
			end
		end
	end
	return (ns.Settings.RuleLabel(kind, key))
end

-- ? on the settings window: the welcome, even with rules.
function Order.ShowWelcome()
	welcomeForced = true
	Order.Refresh()
end

-- Bag changes (our own sorts among them): the not-set count and the outlines.
function Order.OnBagUpdate()
	if Shown() then
		Order.Refresh()
	end
end
