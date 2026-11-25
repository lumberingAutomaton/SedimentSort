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
function Methods.CreateFontString() return NewObj() end
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
GetTime = os.clock
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
ns.Sort = { Start = function() sorts = sorts + 1 end, IsRunning = function() return false end,
	IsQuiet = function() return false end, BudgetMs = function() return 0.3 end, OpenBagsMode = function() return "pause" end }
ns.Popup = { Refresh = function() end, Open = function() ns.popupOpened = true end, Close = function() end,
	BenchRefresh = function() end, BENCH_MODES = { "Drift" } }
ns.AutoSort = { Resume = function() end, IsEnabled = function() return true end, Delay = function() return 1.1 end }
ns.COMMANDS, ns.SHORTCUTS = {}, {}

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

for _, file in ipairs({ "Weights.lua", "Settings.lua", "Setup.lua" }) do
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

-- A new user opens the settings: the setup's first page comes up over them.
S.Open()
assert(SedimentSettings.shown, "settings didn't open")
setup = SedimentSetup
assert(setup and setup.shown and setup.intro.shown, "the intro didn't come up with the settings")
assert(not setup.intro.startOver.shown, "Start over shown with nothing to start over")
Click(setup.intro.start)
RunTimers()
assert(not SedimentSettings.shown, "settings stayed open")
assert(Title() == "Your empty space", "first question: " .. Title())
assert(Q().choices[1].desc.text:find("now"), "the current layout isn't marked")
assert(setup.progress.text:match("^Question 1 of"), setup.progress.text)

-- Highlights: unruled items outlined; empty slots and (later) ruled items not.
assert(buttons[1].SedimentMark and buttons[1].SedimentMark.shown, "unruled hearthstone not highlighted")
assert(not buttons[#buttons].SedimentMark, "an empty slot got a highlight")

Choice(1) -- middle
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
Choice(1)
assert(Title() == "BoE gear", Title())
Click(Q().skip)
assert(w().flags.unboundGear == nil, "Skip set a rule")
assert(Title() == "Spare bags", Title())
-- Finish later, then carry on from the same place.
setup:Hide()
assert(SedimentDB.setup.steps[SedimentDB.setup.index].key == 1, "place not kept")
S.Open() -- not dismissed: the intro shows, with Continue
assert(setup.shown and setup.intro.shown and setup.intro.start.text:match("^Continue"), "no Continue")
Click(setup.intro.start)
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
		assert(Q().choices[3].shown and Q().choices[3].button.text == "Split this up", "no split offered")
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
assert(SedimentDB.setup == nil and SedimentDB.welcomeHidden, "Done didn't end the run")
assert(not setup.shown, "window still open")
assert(not buttons[2].SedimentMark.shown, "highlights stayed on")
local h = W.History()
assert(h[1] and h[1].reason == "setup questions done" and W.IsCurrent(h[1]), "Done didn't save a version")
assert(#h == 1, "the first run (started with no rules) should leave one version, got " .. #h)

-- A second run: starting saves nothing new (the rules are the version Done saved); Start over saves the
-- run's answers, clears the weights, and asks everything again.
SedimentSettings:Hide()
S.Open()
assert(not setup.shown, "the intro opened although it's done")
ns.Setup.ShowIntro()
Click(setup.intro.start)
RunTimers()
assert(#W.History() == 1, "starting saved the same rules twice")
local doneVersion = W.History()[1]
Choice(3) -- packed toward the bottom
assert(w().sinkLine == 0, "layout top not set")
setup:Hide()
ns.Setup.ShowIntro()
assert(setup.intro.startOver.shown, "no Start over while a run is in progress")
Click(setup.intro.startOver)
RunTimers()
h = W.History()
assert(h[1].reason == "before starting the setup questions over" and h[1].weights.sinkLine == 0,
	"Start over didn't save the run's answers")
assert(h[2] == doneVersion, "Start over lost the earlier version")
assert(not W.HasRules() or next(w().items) == nil, "Start over didn't clear the weights")
assert(w().sinkLine == 50, "Start over didn't clear the layout")
assert(Title() == "Your empty space" and Q().choices[1].desc.text:find("now")
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
Click(setup.intro.start)
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

-- The History section: renders a row per version, Load / Name / x go through their dialogs.
local typed = "my rules"
StaticPopup_Show = function(name, _, _, data)
	local d = StaticPopupDialogs[name]
	local dialog = NewObj()
	local box = NewObj()
	box.text = typed
	dialog.GetEditBox = function() return box end
	if d.OnShow then d.OnShow(dialog, data) end
	box.text = typed
	d.OnAccept(dialog, data)
end
S.Open("History")
local function HistoryRows()
	local list = {}
	for _, f in ipairs(allFrames) do
		if f.rename and f.load and f.shown and f.entry then
			list[#list + 1] = f
		end
	end
	table.sort(list, function(a, b) return a.y < b.y end)
	return list
end
local hrows = HistoryRows()
assert(#hrows == #W.History() and #hrows >= 2, "History rows: " .. #hrows .. " for " .. #W.History() .. " versions")
assert(hrows[1].info.text:find("sink line"), "row summary missing: " .. hrows[1].info.text)
-- Load the "done" version (not in use); the rules in use are saved first.
local target
for _, r in ipairs(hrows) do
	if not W.IsCurrent(r.entry) then target = r break end
end
local n = #W.History()
local wanted = target.entry -- rows re-render after a load, so hold on to the version, not the row
Click(target.load)
assert(W.IsCurrent(wanted), "Load didn't load")
assert(#W.History() == n + 1, "Load didn't save the rules it replaced")
-- Name it, then delete the newest.
hrows = HistoryRows()
Click(hrows[1].rename)
assert(hrows[1].entry.name == "my rules", "Name didn't name it")
assert(hrows[1].title.text:match("^my rules") and hrows[1].title.text:find("kept"), "the row doesn't show the name and kept mark")
local victim = hrows[1].entry
Click(hrows[1].remove)
for _, e in ipairs(W.History()) do assert(e ~= victim, "x didn't delete") end
-- Restore previous rules on the Weights page uses History too.
S.Open("Weights")
StaticPopupDialogs.SEDIMENT_RESTORE_RULES.OnAccept()
print("history section OK")
