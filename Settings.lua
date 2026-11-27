-- Settings: the Sediment window. A section list on the left (like WoW's Options window), the selected
-- section on the right. Opened with the gear left of the bag's sort button, /sed, or the Settings button in
-- the weight popup, always at Order unless you pick another section. It closes in combat; where you drag it
-- is remembered (SedimentDB.settingsPos), else on Order it sits beside the bags.
--
-- Order (shown as "Ordering"): the list of rules, the one place to arrange Sediment (Order.lua; it replaced
--   the Weights page and the Setup window, 2026-11-25). Its welcome shows while there are no rules; ? brings
--   it back.
-- Special bags: the special bags you have, the fill switch, and the keep-out rules with x/Undo.
-- Timing: the wait after bag changes and the smoothness (auto-sort is always on, 0.20).
-- Debug group, only with the debug addon (Settings.DebugOn): Testing, Tools (dev buttons) and Files.
-- History: Created and Snapshot entries of the rules, the pinned one first, with Pin / Unpin, Load and x.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Settings.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Settings = {}
ns.Settings = Settings
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)
local Print = function(msg) ns.Print(msg) end

-- Layout like WoW's own Options window: a section list on the left (grouped, with a Debug group that only
-- shows with the debug addon), the selected section's settings on the right under its name. A list scales to any
-- number of sections, where a row of tabs ran out of width at five.
local WIDTH, HEIGHT = 760, 680 -- was 600x520, then 760x600: the Order list barely fit (user, 2026-11-25)
local NAV_W = 140                         -- the section list
local CONTENT_X = NAV_W + 24              -- where the settings pane starts
local CONTENT_W = WIDTH - CONTENT_X - 14  -- the settings pane's width
local NAV_GROUPS = {
	{ header = "Sediment", items = { "Order", "Special bags", "Timing", "History" } }, -- user's order, 2026-11-25
	{ header = "Debug", items = { "Testing", "Tools", "Files" }, debug = true }, -- only with the debug addon
}
-- The section ids above are internal; what the list and the page title show comes from Text.lua for the
-- sections named after one of Sediment's nouns, so renaming the noun renames the section.
local SECTION_TEXT = { Order = "OrderSection", History = "SavedRules" }
local function SectionLabel(id)
	return SECTION_TEXT[id] and L(SECTION_TEXT[id]) or id
end

local ROW_HEIGHT = 22
local frame, tabs, pages = nil, {}, {}

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

local CLICK_GUARD = 0.3 -- clicks right after a list redrew are ignored (rows may have moved)

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
	-- Group/Part, like a folder path (user, 2026-11-25): "Armor/Cloth" and "Trade Goods/Cloth" can't be confused.
	return ("%s/%s"):format(classID and ClassLabel(classID) or "?", sub or key)
end

-- A rule's name (and icon, for items), for the setup questions' review list.
-- A group with a part of the same name ("Quest/Quest"): the part line says nothing the group line doesn't.
function Settings.PartSameAsGroup(subKey)
	local c, sc = tostring(subKey):match("^(%d+):(%d+)$")
	if not c then
		return false
	end
	local group = C_Item.GetItemClassInfo(tonumber(c))
	return group ~= nil and C_Item.GetItemSubClassInfo(tonumber(c), tonumber(sc)) == group
end

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

-- Select mode ---------------------------------------------------------------------------------
-- Order turns it on while its list shows: every bag slot gets a light highlight; clicking an item adds its
-- row (Order's handler), hovering one lights up the row that sorts it. Alt+right-click still opens the weight
-- popup. The clicks land on Sediment's own catcher frames laid over the slots (children of the item buttons,
-- so they move and hide with them); Blizzard's item buttons are never changed, so nothing is tainted. While
-- it's on, a plain click can't use or pick up an item. Turning it on opens the bags; ending it leaves them
-- open. It ends with the settings window, the Order section, or combat.
--
-- Highlights (Order): while on, slots whose item has no rule of its own get an orange outline, and the items
-- of the selected row a gold one. Plain textures on a frame that takes no clicks, so the bag works as usual
-- underneath.

local selecting = false
local selectHandler, selectHover = nil, nil -- set by Order; no handler = open the weight popup
local highlighting, highlightFocus = false, nil
local hookedFrames = {}

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
	c:SetScript("OnClick", function(self, button)
		local b = self:GetParent()
		-- Alt+right-click still opens the weight popup, as it does outside Select Mode.
		if selectHandler and not (button == "RightButton" and IsAltKeyDown()) then
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
		if selectHover then
			selectHover(b:GetBagID(), b:GetID()) -- Order: light up the row that sorts it
		end
	end)
	c:SetScript("OnLeave", function()
		GameTooltip_Hide()
		if selectHover then
			selectHover(nil)
		end
	end)
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
					c = Catcher(b) -- no numbers on the slots (user, 2026-11-25: Order replaced them)
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

-- handler(bag, slot): a click on a bag item (Order adds its row); without one a click opens the weight
-- popup. hover(bag, slot) as the mouse enters an item, hover(nil) as it leaves.
function Settings.SetSelectMode(on, handler, hover)
	if on and InCombatLockdown() then
		Print("not in combat.")
		on = false
	end
	local was = selecting
	selecting = on and true or false
	selectHandler = selecting and handler or nil
	selectHover = selecting and hover or nil
	Settings.RefreshOverlays() -- hooks the bag windows first, so opening them below refreshes the overlays
	-- Starting select mode opens the bags (no change if they're open). Ending it leaves them as they are
	-- (user: turning select mode off shouldn't close the bags).
	if selecting and not was then
		OpenAllBags()
		C_Timer.After(0, Settings.RefreshOverlays)
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

-- Order: the list (Order.lua), built into this page.
local function BuildOrderPage(page)
	page.refreshers = {}
	ns.Order.Build(page, CONTENT_W)
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
	text = B("ClearAllButton") .. "? Your rules are saved to " .. N("SavedRules") .. ", then cleared, "
		.. L("KeepOutRule") .. " rules too, and replaced by a common order to start from.",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.Order.StartFresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local ShowTab -- defined below

-- The Debug group (Testing, Tools, Files) exists only when the debug addon (SedimentSort_Debug, a separate
-- folder players don't get) is installed and loaded (user, 2026-11-26: no switch; the right files or nothing).
function Settings.DebugOn()
	return C_AddOns ~= nil and C_AddOns.IsAddOnLoaded(ns.ADDON .. "_Debug") and true or false
end

-- Lay out the section list: group headers and their entries, the Debug group only with the debug addon.
function Settings.LayoutNav()
	if not frame or not frame.nav then
		return
	end
	local y = -8
	for _, group in ipairs(NAV_GROUPS) do
		local visible = not group.debug or Settings.DebugOn()
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

-- Timing: the two numbers worth tuning. Auto-sort itself is always on, sorts in the full order, and an
-- auto-sort running when the bags open finishes at full speed (user, 2026-11-26: those aren't choices).
local function BuildTimingPage(page)
	page.refreshers = {}
	local place = Flow(page)
	LabeledBox(page, place, 0, "Wait after changes (seconds)",
		"How long the bags must be quiet before they sort. Long enough for a burst of looting to finish and "
		.. "new quest items to register.",
		ns.AutoSort.Delay, function(n) SedimentDB.autoSortDelay = math.max(0, math.min(30, n)) end)
	LabeledBox(page, place, GAP_GROUP, "Smoothness (ms per frame)",
		"How much time per frame, on average, sorting may spend moving items while the bags are closed. "
		.. "Lower is smoother but slower. The sort button always goes full speed.",
		ns.Sort.BudgetMs, function(n) SedimentDB.streamBudgetMs = math.max(0.01, math.min(50, n)) end)
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
	local hint = place(HelpText(page, "To add one, Alt+right-click an item and tick a box under " .. L("KeepOutRule")
		.. "."), GAP_HELP, 4, true)

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

-- A save's rules for its tooltip: its order top to bottom with the Empty Space among them, no numbers (user,
-- 2026-11-26: no Weights shown anywhere), then what it keeps out of special bags.
local function VersionTooltip(entry)
	local w, list = entry.weights, {}
	for id, v in pairs(w.items) do list[#list + 1] = { v, ItemLabel(id) } end
	for k, v in pairs(w.flags) do list[#list + 1] = { v, ns.Weights.FlagLabel(k) } end
	for k, v in pairs(w.subclasses) do list[#list + 1] = { v, SubclassLabel(k) } end
	for k, v in pairs(w.classes) do list[#list + 1] = { v, ClassLabel(k) } end
	list[#list + 1] = { w.default, "Not ordered yet" }
	table.sort(list, function(a, b)
		if a[1] ~= b[1] then
			return a[1] < b[1]
		end
		return a[2] < b[2]
	end)
	local gapLine = "|cffffb040---- " .. L("LootGap") .. " ----|r"
	local lines, sinkShown = {}, false
	for _, e in ipairs(list) do
		if not sinkShown and e[1] >= w.sinkLine then
			lines[#lines + 1] = gapLine
			sinkShown = true
		end
		lines[#lines + 1] = e[2]
	end
	if not sinkShown then
		lines[#lines + 1] = gapLine
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
		.. "changed; " .. B("ClearAllButton") .. " also adds a " .. L("EntryCreated") .. " entry for the order it lays out. "
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
end

-- ? : the Order section's welcome.
function Settings.ShowWelcome()
	Settings.Open("Order")
	ns.Order.ShowWelcome()
end

function ShowTab(name)
	if (name == "Testing" or name == "Tools" or name == "Files") and not Settings.DebugOn() then
		name = "Order"
	end
	local wasOrder = Settings.currentTab == "Order" and pages.Order:IsShown()
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
	if name == "Order" then
		ns.Order.OnShow() -- opens the bags: the outlines are the point
	elseif wasOrder then
		ns.Order.OnHide()
	end
	Settings.Refresh()
end

local function Build()
	frame = CreateFrame("Frame", "SedimentSettings", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	-- HIGH, one layer under the weight popup (DIALOG): with both on DIALOG their parts interleaved, the
	-- window's buttons drawing through the popup's text (user, 2026-11-25). Start Fresh's confirmation is
	-- DIALOG too, so it stays above.
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SedimentDB.settingsPos = { x = self:GetLeft(), y = self:GetTop() } -- kept across sessions
	end)
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

	-- ? brings back the Order section's welcome.
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
		GameTooltip_AddNormalLine(GameTooltip, "What it does, and how to start.")
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
	BuildOrderPage(pages.Order)
	BuildTimingPage(pages.Timing)
	BuildTestingPage(pages.Testing)
	BuildSpecialPage(pages["Special bags"])
	BuildHistoryPage(pages.History)
	BuildToolsPage(pages.Tools)
	BuildFilesPage(pages.Files)
	frame:SetScript("OnShow", function()
		Settings.Refresh()
	end)
	frame:SetScript("OnHide", function()
		Settings.SetSelectMode(false) -- select mode never outlives the window
		ns.Weights.PurgeDeleted() -- History saves marked with x go for good now
		ns.Order.OnHide() -- removed rows are final, no outlines
	end)
	ShowTab("Order")
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
	if pages.Order:IsShown() then
		ns.Order.Refresh()
	end
	if pages.Timing:IsShown() then
		RunRefreshers(pages.Timing)
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
	if pages.Order:IsShown() then
		ns.Order.Refresh()
	end
end

-- Where the window goes: where it was dragged (SedimentDB.settingsPos), else on the Order section beside the
-- bags (the outlines in them are the point), else the middle of the screen.
-- The bag window: the Combined Backpack, else the leftmost open bag window (the weight popup sits above it).
local function BagWindow()
	local bag = ContainerFrameCombinedBags
	if bag and bag:IsShown() then
		return bag
	end
	local best
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local f = _G["ContainerFrame" .. i]
		if f and f:IsShown() and f:GetLeft() and (not best or f:GetLeft() < best:GetLeft()) then
			best = f
		end
	end
	return best
end
Settings.BagWindow = BagWindow

local function Place()
	frame:ClearAllPoints()
	local pos = SedimentDB.settingsPos
	if pos then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
		return
	end
	local bag = Settings.currentTab == "Order" and BagWindow()
	if bag and bag:GetLeft() and bag:GetTop() then
		local scale = bag:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local x = bag:GetLeft() * scale - 12 - WIDTH
		local top = math.max(bag:GetTop() * scale, HEIGHT + 20)
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(0, x), top)
	else
		frame:SetPoint("CENTER")
	end
end

-- tab: a section name; nil keeps the last one (Order the first time).
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
	ShowTab(tab or Settings.currentTab or "Order")
	if not wasShown then
		Place()
		C_Timer.After(0, function()
			if frame:IsShown() and not SedimentDB.settingsPos then
				Place() -- again, once the bags have laid themselves out
			end
		end)
	end
end

-- The gear on the bag and /sed: the settings at Order (user, 2026-11-25: one place to arrange; its welcome
-- shows while there are no rules).
function Settings.OpenDefault()
	Settings.Open("Order")
end

-- /sed: close it if open, else open it.
function Settings.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Settings.OpenDefault()
	end
end
