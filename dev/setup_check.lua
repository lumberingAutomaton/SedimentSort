-- Clicks through the setup questions against mocked frames (no game needed): every question type, Back,
-- Skip, Split this up, Finish later and resume, the review's moves, Done; and the bag-slot highlights.
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
		if type(k) == "string" and k:match("^%u") and not k:match("^Sediment") then
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
function Methods.SetColorTexture(o, r, g, b, a) o.color = { r, g, b, a } end
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
tinsert, date = table.insert, os.date
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
	[12] = "Quest", [15] = "Miscellaneous" }
local SUB = { ["0:1"] = "Potion", ["0:5"] = "Food & Drink", ["0:7"] = "Bandage", ["7:5"] = "Cloth", ["7:7"] = "Metal & Stone" }
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
ns.Sort = { AutoOrder = function() return "full" end, Start = function() sorts = sorts + 1 end,
	StartSoon = function() sorts = sorts + 1 end, IsRunning = function() return false end,
	IsQuiet = function() return false end, BudgetMs = function() return 0.3 end, OpenBagsMode = function() return "pause" end }
ns.Popup = { Refresh = function() end, Open = function() ns.popupOpened = true end, Close = function() end,
	BenchRefresh = function() end, BENCH_MODES = { "Drift" } }
ns.AutoSort = { Resume = function() end, IsEnabled = function() return true end, Delay = function() return 1.1 end }
ns.COMMANDS, ns.SHORTCUTS = {}, {}
-- (Sediment.lua isn't loaded here: its file list, as it would be with one file missing.)
ns.FILES = { "Text.lua", "Weights.lua", "Settings.lua", "Setup.lua", "Missing.lua" }
ns.ADDON = "SedimentSort"
ns.MissingFiles = function()
	local m = {}
	for _, f in ipairs(ns.FILES) do if not ns.loadedFiles[f] then m[#m + 1] = f end end
	return m
end
C_AddOns = { GetAddOnMetadata = function() return "0.17.1" end }

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

for _, file in ipairs({ "Text.lua", "Weights.lua", "Settings.lua", "Setup.lua" }) do
	assert(loadfile(file))("Sediment", ns)
end
SedimentDB = {}
ns.Weights.Init()
local W, S = ns.Weights, ns.Settings
local w = function() return SedimentDB.weights end
local function Weight(it) return (W.Resolve(it)) end
local setup = SedimentSetup -- built on first use
local function Q() return SedimentSetup.question end
local function Title() return SedimentSetup.title.text end
local function Choice(i) Click(Q().choices[i].button) RunTimers() end

-- A new user clicks the gear: with no rules, the setup's first page opens instead of the settings.
S.OpenDefault()
setup = SedimentSetup
assert(setup and setup.shown and setup.intro.shown, "the gear didn't open the setup with no rules")
assert(not (SedimentSettings and SedimentSettings.shown), "the settings opened too")
-- Its Settings button goes on to the Weights section; the gear again brings the setup back.
Click(setup.intro.settings)
assert(not setup.shown and SedimentSettings.shown and S.currentTab == "Weights", "Settings button didn't open Weights")
SedimentSettings:Hide()
S.OpenDefault()
assert(setup.shown and setup.intro.shown, "the gear didn't bring the setup back")
assert(setup.intro.fresh.shown and setup.intro.continue.shown, "the two buttons aren't both there")
assert(not setup.intro.continue.enabled, "Continue enabled with nothing to continue")
assert(Plain(setup.intro.status.text) == "Start Fresh to begin.", Plain(setup.intro.status.text))
Click(setup.intro.fresh)
RunTimers()
assert(not SedimentSettings.shown, "settings stayed open")
assert(Title() == "Your Empty Space", "first question: " .. Title())
assert(Q().choices[1].desc.text:find("now"), "the current layout isn't marked")
assert(setup.progress.text:match("^Question 1 of"), setup.progress.text)
-- Combined Backpack was off: Start Fresh turned it on and says so on the page and in chat.
assert(cvars.combinedBags == "1", "Start Fresh didn't turn on Combined Backpack")
assert(Q().notice.shown and Plain(Q().notice.text):find("Combined Backpack"), "no notice on the page")
assert(ns.lastPrint and Plain(ns.lastPrint):find("Combined Backpack"), "no notice in chat")

-- Highlights: unruled items outlined; empty slots and (later) ruled items not.
assert(buttons[1].SedimentMark and buttons[1].SedimentMark.shown, "unruled hearthstone not highlighted")
assert(not buttons[#buttons].SedimentMark, "an empty slot got a highlight")

Choice(1) -- middle
assert(not Q().notice.shown, "the notice stayed past its question")
assert(w().sinkLine == 50)
assert(Title() == "Your hearthstone", Title())
Choice(1) -- first
assert(w().items[HS], "no hearthstone rule")
assert(not buttons[1].SedimentMark.shown or buttons[1].SedimentMark.color, "hearthstone mark state")

-- Neighbours: select mode with our handler; picks in click order; clicking the hearthstone does nothing.
assert(Title() == "Next to your hearthstone", Title())
assert(S.IsSelecting(), "select mode isn't on for the neighbours question")
local function SlotClick(i) buttons[i].SedimentSelect.scripts.OnClick(buttons[i].SedimentSelect) end
SlotClick(1)
SlotClick(8)  -- 4540
SlotClick(6)  -- 118
SlotClick(10) -- 117
SlotClick(10) -- off again
assert(not ns.popupOpened, "a pick opened the weight popup")
assert(buttons[8].SedimentSelect.weight.text == "1" and buttons[6].SedimentSelect.weight.text == "2", "pick numbers")
Choice(1) -- OK
assert(not S.IsSelecting(), "select mode stayed on after the neighbours question")
assert(Weight(contents[1]) < Weight(contents[8]) and Weight(contents[8]) < Weight(contents[6]), "neighbour order")
assert(Weight(contents[6]) < w().default, "neighbours not before the rest")
assert(w().items[117] == nil, "an unpicked item got a rule")

assert(Title() == "Gray junk", Title())
Choice(2) -- sink: very bottom
assert(Title() == "Trade goods", Title())
-- Back: returns to gray and undoes it.
Click(Q().back)
assert(Title() == "Gray junk" and w().flags.gray == nil, "Back didn't undo gray")
Choice(2)
Choice(2) -- trade goods sink
assert(Weight(contents[2]) >= 50 and Weight(contents[12]) > Weight(contents[2]), "gray not below trade goods")

assert(Title() == "Equipment sets", Title())
-- The "skinning knife" case: a BoE item that already has its own Weight isn't part of the BoE question.
SedimentDB.weights.items[2005] = 95 -- heavy, so it doesn't sit above the hearthstone in later checks
Choice(1)
assert(Title() == "BoE gear", Title())
local boeIcons = {}
for _, b in ipairs(Q().icons) do
	if b.shown and b.itemID then boeIcons[#boeIcons + 1] = b.itemID end
end
assert(#boeIcons == 1 and boeIcons[1] == 2000, "BoE question lists items it can't move: " .. table.concat(boeIcons, ","))
assert(Plain(Q().help.text):find("^In your bags: 1 item"), "BoE count includes the placed item: " .. Q().help.text)
local knifeSlot
for i, it in ipairs(contents) do if it and it.itemID == 2005 then knifeSlot = i end end
assert(not (buttons[knifeSlot].SedimentMark and buttons[knifeSlot].SedimentMark.shown
	and buttons[knifeSlot].SedimentMark.tint.color[2] == 0.85), "the placed BoE item is outlined gold")
Click(Q().skip)
assert(w().flags.unboundGear == nil, "Skip set a rule")
assert(Title() == "Spare bags", Title())
-- Finish later, then carry on from the same place.
setup:Hide()
assert(SedimentDB.setup.steps[SedimentDB.setup.index].key == 1, "place not kept")
S.OpenDefault() -- a run isn't finished: the intro shows, with Continue
assert(setup.shown and setup.intro.shown and setup.intro.continue.enabled, "Continue not offered mid-run")
assert(Plain(setup.intro.status.text):match("^Continue to finish Setup %(question %d+ of %d+%)"), Plain(setup.intro.status.text))
Click(setup.intro.continue)
RunTimers()
assert(Title() == "Spare bags", "resumed at " .. Title())
Choice(1)
assert(Title() == "Quest items", Title())
Choice(2)

-- Generated questions: the class with the most items without a rule first.
local first = Title()
assert(first == "Consumable" or first == "Weapon" or first == "Armor", "first generated question: " .. first)
-- Walk the generated questions, splitting Consumable if it comes with more than one subclass.
local guard, splitDone = 0, false
while Title() ~= "Your order" do
	guard = guard + 1
	assert(guard < 20, "too many questions")
	if Title() == "Consumable" then
		assert(Q().choices[3].shown and Q().choices[3].button.text == "Split This Up", "no split offered")
		Choice(3)
		splitDone = true
		assert(Title():match("^Food") or Title():match("^Bandage") or Title():match("^Potion"),
			"split didn't ask a subclass: " .. Title())
		-- Back returns to Consumable, un-split; splitting again asks the same subclasses.
		local firstSub = Title()
		Click(Q().back)
		assert(Title() == "Consumable" and Q().choices[3].shown, "Back from a split didn't return to the class")
		Choice(3)
		assert(Title() == firstSub, "splitting again asked something else: " .. Title())
	end
	Choice(guard % 2 == 0 and 1 or 2)
end
assert(splitDone, "Consumable never came up to split")
for _, it in ipairs(contents) do
	if it then
		assert(W.HasOwnRule(it), "after the questions, item " .. it.itemID .. " still has no rule")
	end
end
assert(SedimentSetup.progress.text == "Last step", SedimentSetup.progress.text)

-- Review: rows top to bottom with the empty space between; select the hearthstone, move it down.
local review = setup.review
assert(review.shown and not setup.question.shown, "review pane not shown")
assert(not review.up.enabled and not review.down.enabled, "moves enabled with nothing selected")
local function Rows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.lines and f.shown then
			list[#list + 1] = f
		end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	return list
end
-- Rows are positioned with SetPoint("TOPLEFT", 0, -(k - 1) * ROW_HEIGHT): record y from it.
function Methods.SetPoint(o, point, a, b, c, d)
	if point == "TOPLEFT" and type(a) == "number" and type(b) == "number" then
		o.y = -b
	end
end
local function RowById(id)
	for _, r in ipairs(Rows()) do
		if r.id == id then
			return r
		end
	end
end
local function Order()
	local ids = {}
	for _, e in ipairs(W.RankingList()) do
		if e.divider then
			ids[#ids + 1] = "|"
		else
			local r = e.rules[1]
			ids[#ids + 1] = r.kind == "default" and "default" or (r.kind .. ":" .. tostring(r.key))
		end
	end
	return table.concat(ids, " ")
end
-- Re-render so the rows pick up their positions under the new SetPoint.
ns.Setup.OnBagUpdate()
local gaps = 0
for _, r in ipairs(Rows()) do
	if not r.id then gaps = gaps + 1 end
end
assert(gaps == 1, "middle layout should show one empty-space row, got " .. gaps)
assert(not RowById("default"), "the default has a row of its own in the review")
local hsRow = RowById("item:" .. HS)
assert(hsRow, "no hearthstone row")
Click(hsRow)
-- The selected row's items are outlined gold in the bag: the hearthstone, and nothing it doesn't cover.
local function Gold(i)
	local m = buttons[i].SedimentMark
	return m and m.shown and m.tint.color and m.tint.color[2] == 0.85
end
assert(Gold(1), "selecting the hearthstone row didn't outline the hearthstone")
for i = 2, #contents do
	if contents[i] and contents[i].itemID ~= HS then
		assert(not Gold(i), "item " .. contents[i].itemID .. " outlined although the row doesn't cover it")
	end
end
assert(not review.up.enabled and review.down.enabled, "first row: up should be off, down on")
local sortsBefore, orderBefore = sorts, Order()
Click(review.down)
RunTimers()
local orderAfter = Order()
assert(orderAfter:match("^item:4540 item:6948 "), "hearthstone didn't move down one: " .. orderAfter)
assert(sorts > sortsBefore, "a move didn't sort")
assert(Weight(contents[8]) < Weight(contents[1]), "weights don't follow the move")
assert(review.up.enabled, "after moving down, up should be on")
Click(review.up)
assert(Order() == orderBefore, "moving back up didn't restore the order")

-- Move the last float rung (just above the empty space and the default) down: it crosses to the sink side.
local list = W.RankingList()
local d
for k, e in ipairs(list) do if e.divider then d = k end end
assert(list[d - 1].rules[1].kind == "default", "the default isn't next to the empty space")
local lastFloat = list[d - 2].rules[1]
local id = lastFloat.kind == "default" and "default" or (lastFloat.kind .. ":" .. tostring(lastFloat.key))
Click(RowById(id))
Click(review.down)
assert(W.RuleSide(lastFloat.kind, lastFloat.key) == "sink", "crossing the empty space didn't make it sink")
Click(review.up)
assert(W.RuleSide(lastFloat.kind, lastFloat.key) == "float", "crossing back didn't make it float")

-- Packed layout: no empty-space row in the middle, it's at the end; moves skip the hidden divider.
SedimentDB.weights.sinkLine = 100
ns.Setup.OnBagUpdate()
local rows = Rows()
assert(not rows[#rows].id, "packed-from-top layout: the empty space row isn't last")
assert(not RowById("default"), "the default has a row in the packed review")
Click(RowById(id))
Click(review.down)
local afterPacked = Order()
assert(W.RuleSide(lastFloat.kind, lastFloat.key) == "sink", "packed move didn't cross the hidden divider")
-- And it really moved past one visible row (not just across the divider).
local seq = afterPacked:gsub(" |", "")
local before = orderBefore:gsub(" |", "")
assert(seq ~= before, "packed move changed nothing visible")
SedimentDB.weights.sinkLine = 50
ns.Setup.OnBagUpdate()

-- Back from the review returns to the last question.
Click(review.back)
assert(setup.question.shown, "Back from the review didn't return to a question")
Choice(1)
assert(review.shown, "answering the last question again didn't come back to the review")

-- Done: the run ends, the intro stops opening by itself, the window and highlights go.
Click(review.done)
assert(SedimentDB.setup == nil, "Done didn't end the run")
assert(not setup.shown, "window still open")
assert(not buttons[2].SedimentMark.shown, "highlights stayed on")
local h = W.History()
assert(h[1] and h[1].kind == "created" and W.IsCurrent(h[1]), "Done didn't add a Created entry")
assert(#h == 1, "the first run (started with no rules) should leave one entry, got " .. #h)

-- A second run: starting saves nothing new (the rules are the version Done saved); Start over saves the
-- run's answers, clears the weights, and asks everything again.
SedimentSettings:Hide()
S.OpenDefault()
assert(not setup.shown and SedimentSettings.shown and S.currentTab == "Weights", "with rules set, the gear didn't open Weights")
-- "Don't show this" sends the gear to the settings even with no rules.
SedimentDB.setupHidden = true
assert(not ns.Setup.Wanted(), "setupHidden ignored")
SedimentDB.setupHidden = nil
ns.Setup.ShowIntro()
assert(setup.intro.continue.enabled and Plain(setup.intro.status.text):match("^Continue to use your existing rules"),
	"rules exist: " .. Plain(setup.intro.status.text))
Click(setup.intro.continue) -- keep the rules
RunTimers()
assert(W.HasRules(), "Keep my rules cleared the rules")
assert(#W.History() == 1, "starting saved the same rules twice")
local doneVersion = W.History()[1]
Choice(3) -- packed toward the bottom
assert(w().sinkLine == 0, "layout top not set")
setup:Hide()
ns.Setup.ShowIntro()
assert(setup.intro.fresh.shown, "no Start fresh while a run is in progress")
Click(setup.intro.fresh)
RunTimers()
h = W.History()
assert(h[1].kind == "snapshot" and h[1].weights.sinkLine == 0,
	"Start Fresh mid-run didn't take a Snapshot of the run's answers")
assert(h[2] == doneVersion, "Start over lost the earlier version")
assert(not W.HasRules() or next(w().items) == nil, "Start over didn't clear the weights")
assert(w().sinkLine == 50, "Start over didn't clear the layout")
assert(Title() == "Your Empty Space" and Q().choices[1].desc.text:find("now")
	and not Q().choices[3].desc.text:find("now"), "Start over didn't restart with the run's answers undone")
-- The generated questions are asked again too: walk to the end and count them.
local again = 0
while Title() ~= "Your order" do
	again = again + 1
	assert(again < 30, "too many questions after Start over")
	Click(Q().skip)
	RunTimers()
end
assert(again >= 9, "Start over skipped questions: " .. again)
Click(setup.review.back)
while Q().back.enabled and SedimentDB.setup.index > 1 do
	Click(Q().back)
end

-- Combat closes it and keeps the place.
Choice(1)
S.OnCombat()
assert(not setup.shown and SedimentDB.setup.index > 1, "combat didn't close it with the place kept")

-- Hearthstone last: the first pick still ends up right beside it (order: second pick, first pick, hearthstone).
ns.Setup.ShowIntro()
Click(setup.intro.continue)
RunTimers()
assert(Title() == "Your hearthstone", "resumed at " .. Title())
Choice(2) -- last
SlotClick(8)  -- 4540: first pick, nearest
SlotClick(6)  -- 118
Choice(1)
assert(Weight(contents[6]) < Weight(contents[8]) and Weight(contents[8]) < Weight(contents[1]),
	"with the hearthstone last, the first pick isn't nearest to it")
local list, n = W.RankingList(), 0
for _, e in ipairs(list) do n = n + 1 end
assert(list[n].rules[1].key == HS and list[n - 1].rules[1].key == 4540, "first pick not right before the hearthstone")
print(("setup flow OK (%d generated questions, %d sorts)"):format(guard, sorts))

-- Start Fresh (rules set, no run in progress): saves them, then clears everything, keep-out rules too.
setup:Hide()
SedimentDB.setup = nil
SedimentDB.keepOut = { items = {}, subclasses = { ["7:5"] = true } }
assert(next(w().items), "test needs item rules here")
ns.Setup.ShowIntro()
assert(setup.intro.continue.enabled, "rules set but Continue greyed")
local nBefore = #W.History()
ns.lastPrint = nil
Click(setup.intro.fresh)
RunTimers()
assert(next(w().items) == nil and next(w().classes) == nil and next(w().flags) == nil, "Start Fresh didn't clear")
assert(SedimentDB.keepOut == nil, "Start Fresh kept keep-out rules")
assert(#W.History() == nBefore + 1 and W.History()[1].kind == "snapshot"
	and W.History()[1].keepOut.subclasses["7:5"], "Start Fresh didn't save the rules (with keep-out) first")
assert(Title() == "Your Empty Space", "Start Fresh didn't start at the first question")
assert(not Q().notice.shown and not (ns.lastPrint and Plain(ns.lastPrint):find("Combined")),
	"a notice although Combined Backpack was already on")
-- With no rules, Continue is greyed.
setup:Hide()
SedimentDB.setup = nil
ns.Setup.ShowIntro()
assert(not setup.intro.continue.enabled and Plain(setup.intro.status.text) == "Start Fresh to begin.",
	"no-rules first page wrong")
-- Start Fresh on the Weights page: asks, then opens Setup (after saving and clearing).
SedimentDB.weights.classes[4] = 30
StaticPopupDialogs.SEDIMENT_START_FRESH.OnAccept()
RunTimers()
assert(setup.shown and Title() == "Your Empty Space" and next(w().classes) == nil, "Weights' Start Fresh didn't open Setup fresh")
setup:Hide()

-- The History section: a row per entry, the pinned one first; Pin / Unpin, Load, x with Undo.
SedimentDB.setup = nil
SedimentDB.weights.classes[4] = 31
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
assert(Plain(hrows[1].info.text):find("Empty Space at"), "row summary missing: " .. hrows[1].info.text)
-- Load a save that isn't in use; the rules in use (changed since the last save) are saved first.
SedimentDB.weights.classes[4] = 32
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
SedimentSettings:Hide()
for _, e in ipairs(W.History()) do assert(e ~= victim, "closing the window didn't delete") end
assert(StaticPopupDialogs.SEDIMENT_RESTORE_RULES == nil, "Restore previous rules is still there")
print("history section OK")

-- Special bags: the fill switch turns off and back on (it used to save "off" either way).
S.Open("Special bags")
local fill
for _, f in ipairs(allFrames) do
	if f.label and f.label.text == "Fill reagent and profession bags automatically" then fill = f end
end
assert(fill, "fill checkbox not found")
local function Tick(on) fill.checked = on fill.scripts.OnClick(fill) end
Tick(false)
assert(SedimentDB.fillSpecialBags == false, "unticking didn't turn filling off")
Tick(true)
assert(SedimentDB.fillSpecialBags == nil, "ticking didn't turn filling back on")
S.Refresh()
assert(fill.checked, "the box shows unticked after turning filling on")
print("special bags switch OK")

-- Weights: one list; unset groups are orange rows right after the default's row; the top line counts them,
-- and goes empty (not away) when nothing is unset.
SedimentDB.weights.classes = {}
SedimentDB.weights.subclasses = {}
SedimentDB.weights.items = {}
SedimentDB.weights.flags = {}
S.Open("Weights")
local function LadderRows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.stripe and f.box and f.shown and f.entry then list[#list + 1] = f end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	return list
end
local rows = LadderRows()
local defaultAt
for k, r in ipairs(rows) do
	if r.entry.kind == "default" then defaultAt = k end
end
assert(defaultAt and rows[defaultAt + 1] and rows[defaultAt + 1].entry.missing, "no orange rows after the default's row")
local sawClass, sawSub = false, false
for k = defaultAt + 1, #rows do
	if rows[k].entry.missing then
		sawClass = sawClass or rows[k].entry.kind == "class"
		sawSub = sawSub or rows[k].entry.kind == "subclass"
	end
end
assert(sawClass and sawSub, "both the broad and the narrow groups should be listed")
assert(Plain(S.unsetLine.text):match("^%d+ items in your bags have no Weight yet%.$"), "top line: " .. S.unsetLine.text)
-- Everything set: no orange rows, and the line is empty but still there.
for _, it in ipairs(contents) do
	if it then SedimentDB.weights.items[it.itemID] = 10 end
end
S.Refresh()
for _, r in ipairs(LadderRows()) do assert(not r.entry.missing, "an orange row with everything set") end
assert(S.unsetLine.text == "" and S.unsetLine.shown, "the top line should be empty but kept")
print("weights list OK")

-- Debug > Files: the version, a summary, and each expected file loaded or missing (Missing.lua here).
SedimentDB.testingTools = true
S.Open("Files")
assert(S.currentTab == "Files", "Files section didn't open in debug mode")
local seen = {}
for _, t in ipairs(allTexts) do
	if type(t.text) == "string" then seen[#seen + 1] = Plain(t.text) end
end
local function Has(pattern)
	for _, line in ipairs(seen) do if line:find(pattern) then return true end end
end
assert(Has("^Sediment 0%.17%.1 %(the version in the %.toc%)$"), "no version line")
assert(Has("^1 of 5 files missing%.$"), "no missing summary")
assert(Has("^Missing%.lua   missing %(restart the game%)$") and Has("^Setup%.lua   loaded$"), "file lines wrong")
SedimentDB.testingTools = nil
print("files section OK")
