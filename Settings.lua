-- Settings: the window. A section list on the left (like WoW's Options window), the selected section on the
-- right. Opened with the gear left of the bag's sort button, /dim, or the Settings button in the ordering
-- popup, always at Ordering unless you pick another section. It closes in combat; where you drag it is
-- remembered (DisorderItemManagerDB.settingsPos), else on Ordering it sits beside the bags.
--
-- The sections live in their own files and register here (Settings.AddPage): Ordering.lua, Options.lua
-- (Special bags, Timing), History.lua, and Debug.lua (Testing, Tools, Files; only with the debug addon).
-- Shared layout helpers and labels are in Settings.UI.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Settings.lua"] = true -- see ns.FILES (Core.lua) and the Files section
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
	{ header = "Disorder", items = { "Order", "Special bags", "Timing", "History" } }, -- user's order, 2026-11-25
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

-- Labels and boxes ----------------------------------------------------------------------------

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

-- Combat: close every window of ours and end select mode, so nothing of ours can catch a click.
function Settings.OnCombat()
	ns.Overlays.SetSelectMode(false)
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

-- A keep-out rule's name, and whether it covers a whole group ("all Cloth") rather than one item.
local function KeepOutLabel(rule)
	if rule.kind == "subclass" then
		local classID, subclassID = rule.key:match("^(%-?%d+):(%-?%d+)$")
		local name = C_Item.GetItemSubClassInfo(tonumber(classID), tonumber(subclassID))
		return "all " .. (name or rule.key), true
	end
	return ItemLabel(rule.key), false
end


-- Shared by the section files: layout helpers and labels.
Settings.UI = {
	CONTENT_W = CONTENT_W, GAP_HELP = GAP_HELP, GAP_GROUP = GAP_GROUP, CONTROL_X = CONTROL_X,
	ROW_HEIGHT = ROW_HEIGHT, CLICK_GUARD = CLICK_GUARD,
	Flow = Flow, Text = Text, HelpText = HelpText, NewBox = NewBox, LabeledBox = LabeledBox, CheckRow = CheckRow,
	Changed = Changed, WeightChanged = WeightChanged, FormatWeight = FormatWeight,
	ItemLabel = ItemLabel, ClassLabel = ClassLabel, SubclassLabel = SubclassLabel, KeepOutLabel = KeepOutLabel,
}

-- The sections, registered by their files: name -> { build(page), onShow(), onHide() (leaving the section),
-- onWindowHide() (the window closing), refresh(page) (instead of the page's refreshers) }.
local pageDefs = {}
function Settings.AddPage(name, def)
	pageDefs[name] = def
end

local ShowTab -- defined below

-- The Debug group (Testing, Tools, Files) exists only when the debug addon (<folder>_Debug, a separate
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


-- The Debug group's sections: they fall back to Ordering when the debug addon isn't loaded.
local debugPages = {}
for _, group in ipairs(NAV_GROUPS) do
	if group.debug then
		for _, name in ipairs(group.items) do
			debugPages[name] = true
		end
	end
end
-- ? : the Order section's welcome.
function Settings.ShowWelcome()
	Settings.Open("Order")
	ns.Order.ShowWelcome()
end

function ShowTab(name)
	if debugPages[name] and not Settings.DebugOn() then
		name = "Order"
	end
	local prev = Settings.currentTab
	local prevShown = prev and pages[prev] and pages[prev]:IsShown()
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
	if prevShown and prev ~= name and pageDefs[prev] and pageDefs[prev].onHide then
		pageDefs[prev].onHide()
	end
	if pageDefs[name] and pageDefs[name].onShow then
		pageDefs[name].onShow()
	end
	Settings.Refresh()
end

local function Build()
	frame = CreateFrame("Frame", "DisorderItemManagerSettings", UIParent, "BackdropTemplate")
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
		DisorderItemManagerDB.settingsPos = { x = self:GetLeft(), y = self:GetTop() } -- kept across sessions
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
	tinsert(UISpecialFrames, "DisorderItemManagerSettings")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText(L("AddonName"))
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
		GameTooltip_SetTitle(GameTooltip, "How " .. L("AddonName") .. " works")
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
	for _, group in ipairs(NAV_GROUPS) do
		for _, name in ipairs(group.items) do
			pages[name].refreshers = {}
			if pageDefs[name] then
				pageDefs[name].build(pages[name])
			end
		end
	end
	frame:SetScript("OnShow", function()
		Settings.Refresh()
	end)
	frame:SetScript("OnHide", function()
		ns.Overlays.SetSelectMode(false) -- select mode never outlives the window
		for _, group in ipairs(NAV_GROUPS) do
			for _, name in ipairs(group.items) do
				local def = pageDefs[name]
				if def and def.onWindowHide then
					def.onWindowHide()
				end
			end
		end
	end)
	ShowTab("Order")
end

local function RunRefreshers(page)
	for _, f in ipairs(page.refreshers or {}) do
		f()
	end
end

function Settings.Refresh()
	if ns.Overlays.Active() then
		ns.Overlays.Refresh()
	end
	if not frame or not frame:IsShown() then
		return
	end
	for name, page in pairs(pages) do
		if page:IsShown() then
			local def = pageDefs[name]
			if def and def.refresh then
				def.refresh(page)
			else
				RunRefreshers(page)
			end
		end
	end
end

-- One section, if it's the one showing (the test bench after a sort).
function Settings.RefreshPage(name)
	if frame and frame:IsShown() and pages[name] and pages[name]:IsShown() then
		RunRefreshers(pages[name])
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

-- Where the window goes: where it was dragged (DisorderItemManagerDB.settingsPos), else on the Order section beside the
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
	local pos = DisorderItemManagerDB.settingsPos
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
			if frame:IsShown() and not DisorderItemManagerDB.settingsPos then
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
