-- Clicks through the settings against mocked frames (no game needed): the Order section (the first layout,
-- Start Fresh, rows, outlines, moving rows and the Empty Space, unset items, x with Undo, Select Mode and widen,
-- drag and drop), History, Special bags, Debug > Files and the weight popup.
-- It checks the logic and that nothing errors, not how anything looks.
-- Run: lua dev/setup_check.lua (from the addon folder).

-- Mock frames: every object keeps shown/text/scripts; unknown methods (CamelCase) do nothing and return 0.
local Methods = {}
local function NewObj(name)
	local o = { shown = true, text = "", scripts = {}, enabled = true, checked = false, name = name }
	return setmetatable(o, { __index = function(_, k)
		if Methods[k] then
			return Methods[k]
		end
		if type(k) == "string" and k:match("^%u") and not k:match("^Disorder") then
			return function() return 0 end
		end
	end })
end
function Methods.Show(o)
	local was = o.shown
	o.shown = true
	if not was and o.scripts.OnShow then o.scripts.OnShow(o) end
end
function Methods.Hide(o)
	local was = o.shown
	o.shown = false
	if was and o.scripts.OnHide then o.scripts.OnHide(o) end
end
function Methods.SetShown(o, v) if v then o:Show() else o:Hide() end end
function Methods.IsShown(o) return o.shown end
function Methods.IsVisible(o) return o.shown end
function Methods.SetText(o, t) o.text = t end
function Methods.GetText(o) return o.text end
function Methods.SetScript(o, n, f) o.scripts[n] = f end
function Methods.GetScript(o, n) return o.scripts[n] end
local allTexts = {}
function Methods.CreateFontString() local t = NewObj() allTexts[#allTexts + 1] = t return t end
function Methods.CreateTexture() return NewObj() end
function Methods.GetStringHeight() return 12 end
function Methods.GetStringWidth() return 50 end
function Methods.SetEnabled(o, v) o.enabled = v and true or false end
function Methods.IsEnabled(o) return o.enabled end
function Methods.SetChecked(o, v) o.checked = v and true or false end
function Methods.GetChecked(o) return o.checked end
function Methods.HasFocus() return false end
function Methods.GetLeft() return 900 end
function Methods.GetTop() return 600 end
function Methods.GetEffectiveScale() return 1 end
function Methods.GetFrameLevel() return 1 end
function Methods.GetCenter() return 0, 0 end
function Methods.SetTexture(o, t) o.texture = t end
function Methods.GetHighlightTexture(o) o.glow = o.glow or NewObj() return o.glow end
function Methods.SetAlpha(o, a) o.alpha = a end
function Methods.SetColorTexture(o, r, g, b, a) o.color = { r, g, b, a } end
function Methods.LockHighlight(o) o.locked = true end
function Methods.SetFrameStrata(o, s) o.strata = s end
function Methods.UnlockHighlight(o) o.locked = false end
-- Rows are positioned with SetPoint("TOPLEFT", 0, -(k - 1) * ROW_HEIGHT): record y from it.
function Methods.SetPoint(o, point, a, b, ...)
	o.lastPoint = { point, a, b, ... }
	if point == "TOPLEFT" and type(a) == "number" and type(b) == "number" then
		o.y = -b
	end
end
-- Text without colour codes (Sediment's nouns and button names are coloured).
local function Plain(t) return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Click(o) assert(o.enabled, "clicked a disabled button: " .. tostring(o.text)) o.scripts.OnClick(o, "LeftButton") end

local allFrames = {}
function Methods.GetParent(o) return o.parent end
function CreateFrame(_, name, parent)
	local o = NewObj(name)
	o.parent = parent
	if name then _G[name] = o end
	allFrames[#allFrames + 1] = o
	return o
end
UIParent, GameTooltip = NewObj(), NewObj()
UISpecialFrames, StaticPopupDialogs = {}, {}
for _, f in ipairs({ "GameTooltip_SetTitle", "GameTooltip_AddNormalLine", "GameTooltip_Hide", "StaticPopup_Show",
	"hooksecurefunc", "OpenAllBags", "PlaySound" }) do
	_G[f] = function() end
end
tinsert, date, unpack = table.insert, os.date, table.unpack
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
InCombatLockdown = function() return false end
-- Blizzard's Combined Backpack setting: off at first, so Setup has to turn it on.
local cvars = { combinedBags = "0" }
GetCVar = function(name) return cvars[name] end
GetCVarBool = function(name) return cvars[name] == "1" end
SetCVar = function(name, value) cvars[name] = tostring(value) end
-- A clock the test moves on (Wait), so click guards can be checked.
local clock = 1000
GetTime = function() return clock end
local function Wait(seconds) clock = clock + seconds end
local timers = {}
C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function RunTimers()
	while #timers > 0 do
		table.remove(timers, 1)()
	end
end
Enum = { ItemQuality = { Poor = 0 }, ItemClass = { Tradegoods = 7, Container = 1 } }
local CLASS = { [0] = "Consumable", [1] = "Container", [2] = "Weapon", [4] = "Armor", [7] = "Trade Goods",
	[9] = "Recipe", [12] = "Quest", [15] = "Miscellaneous" }
local SUB = { ["0:1"] = "Potion", ["0:5"] = "Food & Drink", ["0:7"] = "Bandage", ["7:5"] = "Cloth", ["7:7"] = "Metal & Stone",
	["12:0"] = "Quest" }
C_Item = {
	GetItemIconByID = function(id) return "icon" .. id end,
	GetItemNameByID = function(id) return "item" .. id end,
	RequestLoadItemDataByID = function() end,
	GetItemClassInfo = function(c) return CLASS[c] end,
	GetItemSubClassInfo = function(c, s) return SUB[c .. ":" .. s] or ("sub" .. c .. ":" .. s) end,
}

-- The bag: one backpack of items.
local HS = 6948
local function Item(itemID, classID, subclassID, extra)
	local it = { itemID = itemID, classID = classID, subclassID = subclassID, subKey = classID .. ":" .. subclassID,
		quality = 1, isBound = true, equipLoc = "", isQuestItem = false, inEquipmentSet = false, count = 1,
		name = "item" .. itemID, link = "[item" .. itemID .. "]", className = CLASS[classID],
		subclassName = SUB[classID .. ":" .. subclassID] }
	for k, v in pairs(extra or {}) do it[k] = v end
	return it
end
local contents = {
	Item(HS, 15, 0),
	Item(2589, 7, 5), Item(2589, 7, 5), Item(2592, 7, 5), Item(2770, 7, 7),
	Item(118, 0, 1), Item(858, 0, 1), Item(4540, 0, 5), Item(4541, 0, 5), Item(117, 0, 5), Item(1251, 0, 7),
	Item(3300, 15, 0, { quality = 0 }), Item(3301, 4, 1, { quality = 0 }),
	Item(2000, 4, 2, { isBound = false, equipLoc = "INVTYPE_CHEST" }),
	Item(2001, 4, 1, { inEquipmentSet = true, equipLoc = "INVTYPE_HEAD" }),
	Item(2002, 2, 7, { equipLoc = "INVTYPE_WEAPON" }), Item(2003, 2, 7, { equipLoc = "INVTYPE_WEAPON" }),
	Item(2005, 2, 7, { isBound = false, equipLoc = "INVTYPE_WEAPON" }), -- BoE, like the user's skinning knife
	Item(5000, 12, 0, { isQuestItem = true }),
	Item(4496, 1, 0, { isBound = false, equipLoc = "INVTYPE_BAG" }),
	false, false, false,
}
local ns = {}
ns.Print = function(msg) ns.lastPrint = msg end
ns.Bags = {
	Read = function()
		local slots = {}
		for i, it in ipairs(contents) do
			slots[i] = { bag = 0, slot = i, zone = "main", item = it or nil }
			if it then it.bag, it.slot = 0, i end
		end
		return slots
	end,
	ReadSlot = function(_, slot) return contents[slot] or nil end,
	SpecialBags = function() return {} end, KeepOutRules = function() return {} end, FillSpecialBags = function() return true end,
}
local sorts = 0
ns.Sort = { Start = function() sorts = sorts + 1 end, Cancel = function() ns.cancelled = true end,
	StartSoon = function() sorts = sorts + 1 end, IsRunning = function() return false end,
	IsQuiet = function() return false end, BudgetMs = function() return 0.3 end }
ns.Popup = { Refresh = function() end, Open = function() ns.popupOpened = true end, Close = function() end,
	BenchRefresh = function() end, BENCH_MODES = { "Drift" } }
ns.AutoSort = { Resume = function() end, Delay = function() return 1.1 end, Status = function() ns.statusShown = true end }
-- The debug addon (SedimentSort_Debug): absent until the Debug section of this test installs it.
local debugAddon = false
C_AddOns = { IsAddOnLoaded = function(name) return debugAddon and name == "Disorder_ItemManager_Debug" end }
-- (Sediment.lua isn't loaded here: its file list, as it would be with one file missing.)
ns.FILES = { "Text.lua", "Rules.lua", "Settings.lua", "Ordering.lua", "Missing.lua" }
ns.ADDON = "Disorder_ItemManager"
ns.MissingFiles = function()
	local m = {}
	for _, f in ipairs(ns.FILES) do if not ns.loadedFiles[f] then m[#m + 1] = f end end
	return m
end
C_AddOns.GetAddOnMetadata = function() return "0.17.1" end

-- The combined bag window, with one item button per slot.
local buttons = {}
for i = 1, #contents do
	local b = NewObj()
	b.GetBagID = function() return 0 end
	b.GetID = function() return i end
	buttons[i] = b
end
ContainerFrameCombinedBags = NewObj()
ContainerFrameCombinedBags.EnumerateValidItems = function() return ipairs(buttons) end
ContainerFrameCombinedBags.UpdateItems = function() end

for _, file in ipairs({ "Text.lua", "Rules.lua", "Settings.lua", "Overlays.lua", "Ordering.lua", "Options.lua",
	"History.lua", "Debug.lua" }) do
	assert(loadfile(file))("Disorder_ItemManager", ns)
end
DisorderItemManagerDB = {}
ns.Weights.Init()
local W, S = ns.Weights, ns.Settings
local w = function() return DisorderItemManagerDB.weights end
local function Weight(it) return (W.Resolve(it)) end

-- A new user clicks the gear: the settings open at Ordering, and with nothing ordered yet the default order is
-- laid out by itself (no welcome screen): a Created entry, Combined Backpack on, the bags sorted, Select Mode on.
local sortsBefore = sorts
S.OpenDefault()
RunTimers()
local P = ns.Order.pane
assert(DisorderItemManagerSettings.shown and S.currentTab == "Order", "the gear didn't open Ordering")
assert(DisorderItemManagerDB.laidOut, "the first open wasn't remembered")
assert(sorts > sortsBefore, "the first layout didn't sort")
assert(W.History()[1] and W.History()[1].kind == "created", "Start Fresh didn't add a Created entry")
assert(cvars.combinedBags == "1", "Start Fresh didn't turn on Combined Backpack")
assert(Plain(P.widenLabel.text):find("Combined Backpack"), "no notice on the page")
assert(ns.lastPrint and Plain(ns.lastPrint):find("Combined Backpack"), "no notice in chat")
assert(ns.Overlays.IsSelecting() and P.pick.text == "Select Mode: On", "Select Mode isn't on once the list shows")
local function OrderRows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.lines and f.undo and f.shown and (f.id or f.ghost) then list[#list + 1] = f end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	return list
end
local function RowIds()
	local ids = {}
	for _, r in ipairs(OrderRows()) do ids[#ids + 1] = r.id or "ghost" end
	return table.concat(ids, " ")
end
local function RowById(id)
	for _, r in ipairs(OrderRows()) do if r.id == id then return r end end
end
local function Choices()
	local labels = {}
	for _, b in ipairs(P.widen) do if b.shown then labels[#labels + 1] = b.text end end
	return table.concat(labels, "|")
end
-- Start Fresh's order: the Hearthstone, the Empty Space, Gray Quality; everything else isn't ordered yet.
assert(RowIds() == "item:6948 gap flag:gray", "fresh rows: " .. RowIds())
-- A longer order for the rest of the walkthrough (Start Fresh's old ten groups), written directly.
local function Rung(...)
	local rules = {}
	for i = 1, select("#", ...), 2 do rules[#rules + 1] = { kind = select(i, ...), key = select(i + 1, ...) } end
	return { rules = rules }
end
local function LongerOrder()
	W.WriteRankingList({ Rung("item", HS), Rung("subclass", "0:1"), Rung("subclass", "0:7"), Rung("class", 0),
		Rung("flag", "quest", "class", 12), Rung("flag", "unboundGear"), Rung("class", 1), { divider = true },
		Rung("class", 2), Rung("class", 4), Rung("class", 7), Rung("class", 15), Rung("flag", "gray") })
	ns.Order.Refresh()
end
LongerOrder()
local FRESH = "item:6948 subclass:0:1 subclass:0:7 class:0 flag:quest flag:unboundGear class:1 gap class:2 class:4 "
	.. "class:7 class:15 flag:gray"
assert(RowIds() == FRESH, "longer order rows: " .. RowIds())
assert(DisorderItemManagerDB.weights.sinkLine == 50, "sink line isn't 50")
assert(P.unset.text == "" and P.unset.shown, "the not-set line should be empty but kept")

-- Click Trade Goods: its items are outlined gold, nothing else; a group has nothing to widen to.
local function Gold(i)
	local m = buttons[i].DisorderMark
	return m and m.shown and m.tint.color and m.tint.color[2] == 0.85
end
local function Orange(i)
	local m = buttons[i].DisorderMark
	return m and m.shown and m.tint.color and m.tint.color[2] == 0.5
end
Wait(1)
Click(RowById("class:7"))
for i, it in ipairs(contents) do
	if it then
		assert((Gold(i) and true or false) == (it.classID == 7), "item " .. it.itemID .. " gold: " .. tostring(Gold(i)))
	end
end
assert(Choices() == "" and P.widenLabel.text == "", "a group row offered choices, or the notice stayed")

-- Dragging. The list's top is at y = 600 in the mock, rows 20 apart; a drop at y = 600 - 20 * slot lands in
-- that slot (0 = above the first row). A press on a row drags once the mouse moves; the release ends it
-- wherever the mouse is. The dragged row is dimmed and hover glow is off.
local cursorY = 600
GetCursorPosition = function() return 0, cursorY end
local mouseDown = false
IsMouseButtonDown = function() return mouseDown end
local function Drag(id, slot)
	local row = RowById(id)
	cursorY = 600 - row.y - 10 -- on the row
	mouseDown = true
	row.scripts.OnMouseDown(row, "LeftButton")
	P.scripts.OnUpdate(P)
	assert(not P.dropLine.shown, "a drag started before the mouse moved")
	cursorY = 600 - 20 * slot
	P.scripts.OnUpdate(P)
	P.scripts.OnUpdate(P)
	assert(P.dropLine.shown, "no drop line while dragging")
	local dragged = RowById(id)
	assert(dragged.alpha == 0.4 and dragged:GetHighlightTexture().alpha == 0, "the dragged row isn't dimmed, or hover glow is on")
	mouseDown = false
	P.scripts.OnUpdate(P)
	assert(not P.dropLine.shown and not P.scripts.OnUpdate, "drag didn't clean up")
	for _, r in ipairs(OrderRows()) do
		assert((r.alpha or 1) == 1 and (r:GetHighlightTexture().alpha or 1) == 1, "a row stayed dimmed or without glow")
	end
end
-- Trade Goods above Armor (slot 9: between Weapon and Armor), by the row; the bags sort.
Wait(1)
sortsBefore = sorts
Drag("class:7", 9)
assert(RowIds() == "item:6948 subclass:0:1 subclass:0:7 class:0 flag:quest flag:unboundGear class:1 gap class:2 class:7 "
	.. "class:4 class:15 flag:gray", "Trade Goods above Armor: " .. RowIds())
assert(sorts > sortsBefore and RowById("class:7").selected.shown, "a drop didn't sort, or didn't select the row")
assert(Weight(contents[2]) < Weight(contents[15]), "trade goods don't sort before armor")
-- A click right after the drop is the release, not a click.
Click(RowById("class:4"))
assert(RowById("class:7").selected.shown, "the click ending a drag selected another row")

-- The Empty Space drags like any row: below Weapon, weapons float; to the top, everything sinks.
Drag("gap", 9)
assert(Weight(contents[16]) < 50 and Weight(contents[2]) >= 50, "weapons should float, trade goods sink")
Drag("gap", 0)
assert(RowIds():match("^gap "), "Empty Space didn't reach the top: " .. RowIds())
for _, it in ipairs(contents) do
	if it then assert(Weight(it) >= 50, "item " .. it.itemID .. " floats with the Empty Space at the top") end
end
local before = RowIds()
Drag("gap", 1) -- just below itself: no move
assert(RowIds() == before, "a drop next to the row itself moved it")

-- A new kind of item turns up: unset, outlined orange, attached to the Empty Space, counted in the top line;
-- selecting the Empty Space outlines it gold.
contents[#contents] = Item(9000, 9, 0) -- a Recipe in the last (empty) slot
ns.Order.OnBagUpdate()
Wait(1)
Click(RowById("item:6948"))
assert(Orange(#contents), "the unset item isn't outlined orange")
assert(Plain(P.unset.text) == "1 item in your bags isn't ordered yet.", "top line: " .. P.unset.text)
Wait(1)
Click(RowById("gap"))
assert(Gold(#contents), "selecting the Empty Space doesn't outline the unset item")
assert(Weight(contents[#contents]) >= 50 and Weight(contents[#contents]) < Weight(contents[2]),
	"with the Empty Space at the top, unset items should sit just below it")

-- x removes a row: it stays greyed in place with Undo, even when the list changes, until the section closes; the
-- rule is gone and the bags sort. Undo puts it back right below the row that was above it.
local orderBefore = RowIds()
Wait(1)
sortsBefore = sorts
Click(RowById("class:7").remove)
assert(DisorderItemManagerDB.weights.classes[7] == nil and sorts > sortsBefore, "x didn't remove the rule and sort")
local ghostRow
for _, r in ipairs(OrderRows()) do if r.ghost then ghostRow = r end end
assert(ghostRow and ghostRow.undo.shown and not ghostRow.remove.shown, "no greyed row with Undo")
assert(RowIds() == orderBefore:gsub("class:7", "ghost"), "the removed row didn't stay in place: " .. RowIds())
Click(ghostRow.undo)
assert(RowIds() == orderBefore and DisorderItemManagerDB.weights.classes[7], "Undo didn't put it back in place")
-- Removed, then the list changes (the row above it is dragged to the top): the removed row stays, under that
-- row; Undo puts Trade Goods back under it, wherever it is now.
local above
do
	local ids = {}
	for id in RowIds():gmatch("%S+") do ids[#ids + 1] = id end
	for n, id in ipairs(ids) do if id == "class:7" then above = ids[n - 1] end end
end
assert(above, "Trade Goods has no row above it in this test")
Wait(1)
Click(RowById("class:7").remove)
Wait(1)
Drag(above, 0)
for _, r in ipairs(OrderRows()) do if r.ghost then ghostRow = r end end
assert(RowIds():find("^" .. above:gsub("%p", "%%%0") .. " ghost "), "the removed row didn't follow the row above it: " .. RowIds())
Wait(1)
Click(ghostRow.undo)
assert(RowIds():find("^" .. above:gsub("%p", "%%%0") .. " class:7 "), "Undo didn't put it back under " .. above .. ": " .. RowIds())
LongerOrder()
assert(RowIds() == FRESH, "longer order again: " .. RowIds())

-- Select Mode (on since the list showed): hovering a bag item lights up the row that sorts it; a click adds
-- the item's row right above that row, selected, with its widen choices on the right; hovering a choice
-- outlines what it would cover; choosing swaps the row in place.
local function SlotEnter(i) buttons[i].DisorderSelect.scripts.OnEnter(buttons[i].DisorderSelect) end
local function SlotLeave(i) buttons[i].DisorderSelect.scripts.OnLeave(buttons[i].DisorderSelect) end
local function SlotClick(i, button) buttons[i].DisorderSelect.scripts.OnClick(buttons[i].DisorderSelect, button) end
SlotEnter(2) -- 2589, Trade Goods/Cloth: Trade Goods sorts it
assert(RowById("class:7").locked and not RowById("class:4").locked, "hover didn't light up the Trade Goods row")
SlotLeave(2)
assert(not RowById("class:7").locked, "the row stayed lit after the mouse left")
SlotEnter(#contents) -- the unset Recipe: the Empty Space
assert(RowById("gap").locked, "hovering an unset item didn't light up the Empty Space")
SlotLeave(#contents)
sortsBefore = sorts
SlotClick(2)
assert(not ns.popupOpened, "a pick opened the weight popup")
assert(RowIds():find("item:2589 class:7", 1, true), "the pick isn't right above Trade Goods: " .. RowIds())
assert(RowById("item:2589").selected.shown and sorts > sortsBefore, "the new row isn't selected, or no sort")
assert(Choices() == "Trade Goods/Cloth|Trade Goods", "widen choices: " .. Choices())
assert(Plain(P.widenLabel.text) == "Sort item2589 as:", "widen heading: " .. P.widenLabel.text)
P.widen[1].scripts.OnEnter(P.widen[1])
for i, it in ipairs(contents) do
	if it then
		assert((Gold(i) and true or false) == (it.subKey == "7:5"), "hover outline wrong for item " .. it.itemID)
	end
end
P.widen[1].scripts.OnLeave(P.widen[1])
Click(P.widen[1])
assert(DisorderItemManagerDB.weights.items[2589] == nil and DisorderItemManagerDB.weights.subclasses["7:5"], "widening didn't swap the rule")
assert(RowIds():find("subclass:7:5 class:7", 1, true), "the Cloth row didn't take the item's place: " .. RowIds())
assert(Choices() == "Trade Goods", "a group/part row should offer its group: " .. Choices())
SlotClick(14) -- 2000, BoE chest: a flag choice too
assert(Choices():find("BoE Gear", 1, true), "flag choice missing: " .. Choices())
-- Any item row can widen, not just the last pick: the Hearthstone's row.
Wait(1)
Click(RowById("item:6948"))
assert(Choices() == "Miscellaneous/sub15:0|Miscellaneous", "Hearthstone row choices: " .. Choices())
-- Alt+right-click still opens the weight popup.
IsAltKeyDown = function() return true end
before = RowIds()
SlotClick(3, "RightButton")
assert(ns.popupOpened and RowIds() == before, "Alt+right-click picked instead of opening the popup")
IsAltKeyDown, ns.popupOpened = function() return false end, nil
-- The button turns picking off and on.
Click(P.pick)
assert(not ns.Overlays.IsSelecting() and P.pick.text == "Select Mode: Off", "the button didn't turn Select Mode off")
Click(P.pick)
assert(ns.Overlays.IsSelecting() and P.pick.text == "Select Mode: On", "the button didn't turn Select Mode back on")

-- Start Fresh with rules (the bottom button asks first): saves them, keep-out included, clears, lays out again.
DisorderItemManagerDB.weights.items[2002] = 5
DisorderItemManagerDB.keepOut = { items = {}, subclasses = { ["7:5"] = true } }
local nBefore = #W.History()
ns.lastPrint = nil
StaticPopupDialogs.DISORDER_ITEMMANAGER_START_FRESH.OnAccept()
RunTimers()
assert(DisorderItemManagerDB.weights.items[2002] == nil and DisorderItemManagerDB.keepOut == nil, "Start Fresh didn't clear")
local h = W.History()
assert(#h == nBefore + 2 and h[1].kind == "created" and h[2].kind == "snapshot" and h[2].keepOut.subclasses["7:5"],
	"Start Fresh didn't save the rules first and add a Created entry")
assert(RowIds() == "item:6948 gap flag:gray", "fresh again: " .. RowIds())
assert(not (ns.lastPrint and Plain(ns.lastPrint):find("Combined")), "a notice although Combined Backpack was already on")
LongerOrder()

-- Leaving the section: no outlines, picking ends; coming back turns it on again, even if it was turned off.
Click(P.pick)
S.Open("Options")
assert(not buttons[2].DisorderMark.shown and not ns.Overlays.IsSelecting(), "outlines or picking stayed after leaving Order")
S.Open("Order")
assert(ns.Overlays.IsSelecting(), "Select Mode isn't on again on returning to Order")
Wait(1)
Click(RowById("class:7"))
assert(Gold(2), "outlines didn't come back on returning to Order")
-- A list emptied on purpose stays empty: the automatic layout happens only on the very first open.
local kept = W.CopyWeights()
W.SetWeights({ sinkLine = 50, default = 50, items = {}, flags = {}, subclasses = {}, classes = {} })
S.Open("Options")
S.Open("Order")
assert(next(DisorderItemManagerDB.weights.classes) == nil, "the default order came back on an emptied list")
W.SetWeights(kept)
S.Open("Options")
S.Open("Order")
S.OnCombat()
assert(not DisorderItemManagerSettings.shown and not ns.Overlays.IsSelecting(), "combat didn't close the settings and end picking")
contents[#contents] = false
print(("order section OK (%d sorts)"):format(sorts))

-- The History section: a row per entry, the pinned one first; Pin / Unpin, Load, x with Undo.
DisorderItemManagerDB.setup = nil
DisorderItemManagerDB.weights.classes[4] = 31
W.Snapshot()
S.Open("History")
local function HistoryRows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.pin and f.load and f.shown and f.entry then
			list[#list + 1] = f
		end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	return list
end
local hrows = HistoryRows()
assert(#hrows == #W.History() and #hrows >= 2, "History rows: " .. #hrows .. " for " .. #W.History() .. " saves")
assert(Plain(hrows[1].info.text):find("%d+ ordered"), "row summary missing: " .. hrows[1].info.text)
-- Load a save that isn't in use; the rules in use (changed since the last save) are saved first.
DisorderItemManagerDB.weights.classes[4] = 32
S.Refresh()
hrows = HistoryRows()
local target
for _, r in ipairs(hrows) do
	if not W.IsCurrent(r.entry) then target = r break end
end
local n = #W.History()
local wanted = target.entry -- rows re-render after a load, so hold on to the save, not the row
Click(target.load)
assert(not W.IsCurrent(wanted), "a Load click right after the list redrew wasn't ignored")
Wait(1)
Click(target.load) -- no "are you sure?": it loads at once
assert(W.IsCurrent(wanted), "Load didn't load")
assert(#W.History() == n + 1, "Load didn't save the rules it replaced")
-- A second click straight after (a double-click) hits a shifted row and must be ignored.
Click(target.load)
assert(W.IsCurrent(wanted) and #W.History() == n + 1, "a double-click loaded a second save")
Wait(1)
-- Tags: the loaded save is Active; the save Load just made (the rules before) is Previous.
local activeRows, previousRows = 0, 0
for _, r in ipairs(HistoryRows()) do
	local info = Plain(r.info.text)
	if info:match("^Active") then activeRows = activeRows + 1; assert(W.IsCurrent(r.entry), "Active on the wrong save") end
	if info:match("^Previous") then previousRows = previousRows + 1; assert(r.entry == W.History()[1], "Previous on the wrong save") end
end
assert(activeRows == 1 and previousRows == 1, ("tags: %d Active, %d Previous"):format(activeRows, previousRows))
-- Pin the last row: it moves to the top (one pin: any other is unpinned); titles are "kind — time".
hrows = HistoryRows()
local toPin = hrows[#hrows].entry
assert(hrows[#hrows].pin.text == "Pin", "unpinned row's button: " .. hrows[#hrows].pin.text)
Click(hrows[#hrows].pin)
hrows = HistoryRows()
assert(hrows[1].entry == toPin and toPin.pinned and hrows[1].pin.text == "Unpin", "pinning didn't move it to the top")
local pinCount = 0
for _, e in ipairs(W.History()) do if e.pinned then pinCount = pinCount + 1 end end
assert(pinCount == 1, "more than one pinned entry")
assert(Plain(hrows[1].title.text):match(" — %a%a%a %d+, %d+:%d+$"), "title: " .. hrows[1].title.text)
assert(not Plain(hrows[1].info.text):find("%d%d%d%d%-"), "the date is still in the summary line")
Click(hrows[1].pin) -- Unpin
assert(not toPin.pinned, "Unpin didn't")
-- x greys the row with Undo; Undo restores; closing the window makes it final.
hrows = HistoryRows()
local victim = hrows[1].entry
Click(hrows[1].remove)
hrows = HistoryRows()
assert(victim.deleted and hrows[1].entry == victim and hrows[1].undo.shown and not hrows[1].remove.shown
	and not hrows[1].load.enabled, "x didn't grey the row with Undo")
Click(hrows[1].undo)
assert(not victim.deleted, "Undo didn't undo")
Click(HistoryRows()[1].remove)
DisorderItemManagerSettings:Hide()
for _, e in ipairs(W.History()) do assert(e ~= victim, "closing the window didn't delete") end
assert(StaticPopupDialogs.SEDIMENT_RESTORE_RULES == nil, "Restore previous rules is still there")
print("history section OK")

-- Options > Special bags: the fill switch turns off and back on (it used to save "off" either way).
S.Open("Options")
local fill
for _, f in ipairs(allFrames) do
	if f.label and f.label.text == "Fill reagent and profession bags automatically" then fill = f end
end
assert(fill, "fill checkbox not found")
local function Tick(on) fill.checked = on fill.scripts.OnClick(fill) end
Tick(false)
assert(DisorderItemManagerDB.fillSpecialBags == false, "unticking didn't turn filling off")
Tick(true)
assert(DisorderItemManagerDB.fillSpecialBags == nil, "ticking didn't turn filling back on")
S.Refresh()
assert(fill.checked, "the box shows unticked after turning filling on")
print("special bags switch OK")

-- The Debug group exists only with the debug addon: without it, its sections fall back to Ordering.
S.Open("Files")
assert(S.currentTab == "Order", "a Debug section opened without the debug addon")
debugAddon = true

-- Debug > Tools: the old /sed commands as buttons.
S.Open("Tools")
assert(S.currentTab == "Tools", "Tools didn't open with the debug addon")
for _, f in ipairs(allFrames) do
	if f.text == "Auto-sort status" then Click(f) end
	if f.text == "Cancel sort" then Click(f) end
end
assert(ns.statusShown and ns.cancelled, "the Tools buttons didn't run status and cancel")
print("tools section OK")

-- Debug > Files: the version, a summary, and each expected file loaded or missing (Missing.lua here).
S.Open("Files")
assert(S.currentTab == "Files", "Files section didn't open with the debug addon")
local seen = {}
for _, t in ipairs(allTexts) do
	if type(t.text) == "string" then seen[#seen + 1] = Plain(t.text) end
end
local function Has(pattern)
	for _, line in ipairs(seen) do if line:find(pattern) then return true end end
end
assert(Has("^Disorder 0%.17%.1 %(the version in the %.toc%)$"), "no version line")
assert(Has("^1 of 5 files missing%.$"), "no missing summary")
assert(Has("^Missing%.lua   missing %(restart the game%)$") and Has("^Ordering%.lua   loaded$"), "file lines wrong")
-- Debug: an item the game has locked shows red at once, and the red goes when it unlocks.
contents[2].isLocked = true
ns.Debug.lockWatch.scripts.OnEvent(ns.Debug.lockWatch, "ITEM_LOCK_CHANGED", 0, 2)
RunTimers()
assert(buttons[2].DisorderLockMark and buttons[2].DisorderLockMark.shown, "a locked item isn't red")
assert(not (buttons[3].DisorderLockMark and buttons[3].DisorderLockMark.shown), "an unlocked item is red")
contents[2].isLocked = nil
ns.Debug.lockWatch.scripts.OnEvent(ns.Debug.lockWatch, "ITEM_LOCK_CHANGED", 0, 2)
RunTimers()
assert(not buttons[2].DisorderLockMark.shown, "the red stayed after the item unlocked")
debugAddon = false
-- Without the debug addon: no red at all.
contents[2].isLocked = true
ns.Debug.RefreshLockMarks()
assert(not buttons[2].DisorderLockMark.shown, "a red overlay without the debug addon")
contents[2].isLocked = nil
print("files section OK")
print("red overlay on locked items OK")

-- The weight popup: the levels that apply, most specific first; the winner marked; Add only above it.
ns.Bags.SpecialBagItem = function() return false end
ns.Bags.KeepOutRule = function() return false end
C_Container = { GetContainerItemInfo = function(_, slot) return contents[slot] and { itemID = contents[slot].itemID } end }
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, "icon" .. id end
assert(loadfile("Popup.lua"))("Disorder_ItemManager", ns)
local Popup = ns.Popup
StaticPopupDialogs.DISORDER_ITEMMANAGER_START_FRESH.OnAccept() -- clean rules again
RunTimers()
LongerOrder()
local function PopupRows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.parent == DisorderItemManagerPopup and f.add and f.shown then list[#list + 1] = f end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = Plain(r.label.text) .. (r.add.shown and " [Add]" or "") .. (r.mark.text ~= "" and " <wins" or "")
	end
	return table.concat(out, " | "), list
end
-- A gray cloth armor piece, like the Calico Bracers: Gray Quality wins; the item above it can be added;
-- its group/part and group (Armor has a row) are below it, with nothing to add.
Popup.Open(0, 13)
local at = DisorderItemManagerPopup.lastPoint
assert(at[1] == "BOTTOMLEFT" and at[2] == ContainerFrameCombinedBags and at[3] == "TOPLEFT", "the popup isn't above the bag")
assert(DisorderItemManagerPopup.strata == "DIALOG" and DisorderItemManagerSettings.strata == "HIGH", "the popup isn't a layer above the settings")
assert(Plain(DisorderItemManagerPopup.summary.text) == "Sorted as Gray Quality.",
	"summary: " .. DisorderItemManagerPopup.summary.text)
local got, list = PopupRows()
assert(got == "item3301 [Add] | Gray Quality <wins | Armor/sub4:1 | Armor", "gray armor rows: " .. got)
sortsBefore = sorts
Click(list[1].add)
assert(DisorderItemManagerDB.weights.items[3301] and sorts > sortsBefore, "Add didn't give the item a row and sort")
assert(Plain(DisorderItemManagerPopup.summary.text) == "Sorted as item3301.",
	"summary after Add: " .. DisorderItemManagerPopup.summary.text)
got = PopupRows()
assert(got == "item3301 <wins | Gray Quality | Armor/sub4:1 | Armor", "after Add: " .. got)
-- Nothing set: every level can be added, "Not set" wins; adding the group puts its row by the Empty Space.
contents[#contents] = Item(9100, 9, 3)
Popup.Open(0, #contents)
assert(Plain(DisorderItemManagerPopup.summary.text) == "Nothing set: it stays next to the Empty Space.",
	"unset summary: " .. DisorderItemManagerPopup.summary.text)
got, list = PopupRows()
assert(got == "item9100 [Add] | Recipe/sub9:3 [Add] | Recipe [Add] | Not set <wins", "unset rows: " .. got)
Click(list[3].add)
S.Open("Order")
assert(RowIds():find("class:1 class:9 gap", 1, true), "the new group row isn't just above the Empty Space: " .. RowIds())
got = PopupRows()
assert(got == "item9100 [Add] | Recipe/sub9:3 [Add] | Recipe <wins", "after adding the group: " .. got)
-- Settings: Order, with the deciding row selected.
Click(DisorderItemManagerPopup.settingsButton)
assert(S.currentTab == "Order" and RowById("class:9").selected.shown, "Settings didn't select the deciding row")
-- Quest items (user's screenshots): named as the Order row they sort with ("Quest Items" holds the quest flag
-- and the Quest group), and no "Quest/Quest" line.
local questSlot
for i, it in ipairs(contents) do if it and it.itemID == 5000 then questSlot = i end end
Popup.Open(0, questSlot) -- 5000, a quest item
assert(Plain(DisorderItemManagerPopup.summary.text) == "Sorted as Quest Items.", "quest summary: " .. DisorderItemManagerPopup.summary.text)
got = PopupRows()
assert(got == "item5000 [Add] | Quest Items <wins | Quest", "quest item rows: " .. got)
contents[#contents] = Item(5001, 12, 0) -- like the Okra: the Quest group, no quest flag
Popup.Open(0, #contents)
assert(Plain(DisorderItemManagerPopup.summary.text) == "Sorted as Quest Items.", "okra summary: " .. DisorderItemManagerPopup.summary.text)
got = PopupRows()
assert(got == "item5001 [Add] | Quest <wins", "okra rows: " .. got)
Click(DisorderItemManagerPopup.settingsButton)
assert(RowById("flag:quest").selected.shown, "Settings didn't select the Quest Items row for the Quest group")
contents[#contents] = false
print("weight popup OK")
