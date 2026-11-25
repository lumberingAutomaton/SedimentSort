-- Setup: the setup questions (NOTES calls them the onboarding questionnaire). The first page is the
-- introduction, which replaced the welcome screen: what Sediment does, and a button to start. Then one
-- question per page. Each answer is applied at once and the bags are sorted (button speed; they're open),
-- so you see it work:
--   1. Where the empty space goes: middle, bottom or top (sink line 50, 100 or 0).
--   2. Hearthstone first or last; then anything to keep next to it (Select mode: click items in order).
--   3. Gray junk, trade goods: float or sink.
--   4. Only if you have such items: equipment sets, BoE gear, spare bags, quest items.
--   5. The item classes in your bags that still have no rule, the one covering the most items first;
--      "Split this up" asks about each of its subclasses instead.
--   6. Review: every rule top to bottom; select a row and move it up or down.
-- Answers are places in an order, not numbers (Weights.PlaceRule): "float" goes at the end of the top part,
-- "sink" at the start of the bottom part, and the order then gets tidy weights. Items without a rule always
-- sit next to the empty space (Weights.PinDefault); the review shows them as part of it. Answers only change
-- the rules they're about. Back undoes the step it returns to (each step keeps a copy of the weights from
-- when it was shown); Skip changes nothing; closing the window ("Finish later") keeps the place, saved in
-- SedimentDB.setup. While it's open, bag slots whose item has no rule of its own are outlined orange and
-- the items the current question is about gold, so you can watch the answers cover the bag. The first page
-- has two fixed buttons: Start Fresh (save the rules to History, clear them all, keep-out rules too, ask
-- everything) and Continue (keep the rules). Starting either way and Done save a version to History.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Setup.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Setup = {}
ns.Setup = Setup
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)

local HEARTHSTONE = 6948
local TRADE_GOODS = Enum.ItemClass and Enum.ItemClass.Tradegoods or 7
local CONTAINER = Enum.ItemClass and Enum.ItemClass.Container or 1
local WIDTH, HEIGHT = 420, 430
local PANE_W = WIDTH - 32
local MAX_ICONS = 12
local ROW_HEIGHT = 20
local CHOICE_W = 130

local frame
local page = "intro"  -- "intro" or "steps"
local picks = {}      -- the hearthstone neighbours clicked so far, in order (item IDs)
local ownSelect = false
local reviewSelected  -- the review's selected rung, by its first rule's id
local Render          -- defined below
local HasWeightRules    -- defined below
local noticeIndex       -- the step showing "Sediment turned on Combined Backpack", if any
local ReviewFocus       -- defined below

local function State()
	return SedimentDB.setup
end

local function RuleId(kind, key)
	return kind == "default" and "default" or (kind .. ":" .. tostring(key))
end

-- The fixed and special questions' wording.
local RULE_TEXT = {
	["flag:gray"] = { title = "Gray junk", text = "Where should gray (poor quality) items go?" },
	["class:" .. TRADE_GOODS] = { title = "Trade goods",
		text = "Where should trade goods go? Cloth, herbs, ore, leather and other crafting materials." },
	["flag:equipmentSet"] = { title = "Equipment sets",
		text = "Items in your equipment sets always stay together. Where should they go?" },
	["flag:unboundGear"] = { title = "BoE gear",
		text = "Gear that isn't soulbound yet (bind on equip). Where should it go?" },
	["class:" .. CONTAINER] = { title = "Spare bags", text = "Bags you're carrying. Where should they go?" },
	["flag:quest"] = { title = "Quest items", text = "Where should quest items go?" },
}

-- The answers' words: float/sink in the middle layout; in the packed ones, the direction you see in the bag
-- (the order runs top to bottom in every layout; only the empty space moves). "Near the start / end" was
-- hard to understand (user, 2026-11-24).
local function Words()
	if ns.Weights.Layout() == "middle" then
		return { float = "Float", sink = "Sink", floats = "floats", sinks = "sinks",
			floatHelp = "To the top part of your bags, above the " .. N("LootGap") .. ".",
			sinkHelp = "To the bottom part of your bags, below the " .. N("LootGap") .. "." }
	end
	-- Plain directions only: "above anything that has no rule yet" (where it really goes) meant nothing to
	-- the user (2026-11-24); the review shows the exact place.
	return { float = "Higher up", sink = "Lower down", floats = "higher up", sinks = "lower down",
		floatHelp = "Toward the top of your bags.",
		sinkHelp = "Toward the bottom of your bags." }
end

-- Bag contents ---------------------------------------------------------------------------------
-- A render asks about the bags many times; it reads them once (slotsCache) and every helper uses that.

local slotsCache

local function Slots()
	return slotsCache or ns.Bags.Read()
end

-- Does this question's rule cover the item at all?
local function Covers(step, item)
	if step.kind == "flag" then
		return ns.Weights.ItemFlags(item)[step.key] == true
	elseif step.kind == "class" then
		return item.classID == step.key
	elseif step.kind == "subclass" then
		return item.subKey == step.key
	end
	return false
end

-- Would answering this question decide where the item goes? Only if no more specific rule already does (its
-- own Weight, or an earlier flag): answering BoE gear can't move a skinning knife you placed yourself, so the
-- question mustn't list, outline or count it (user, 2026-11-25: it looked like being asked twice).
local function Matches(step, item)
	if step.t == "hearth" then
		return item.itemID == HEARTHSTONE
	elseif step.t ~= "rule" or not Covers(step, item) then
		return false
	end
	local levels = ns.Weights.Explain(item)
	for _, level in ipairs(levels) do
		if level.kind == step.kind and level.key == step.key then
			return true
		end
		if level.applies and level.weight ~= nil then
			return false -- a more specific rule decides it
		end
	end
	return false
end

-- The bag items a step is about, and how many of them have no rule of their own.
-- The items this question would decide, how many of those have no Weight yet, and how many it covers in all
-- (covered but not decided = placed by a more specific rule).
local function MatchingItems(step)
	local list, unruled, covered = {}, 0, 0
	for _, s in ipairs(Slots()) do
		if s.item then
			if step.t == "rule" and Covers(step, s.item) then
				covered = covered + 1
			end
			if Matches(step, s.item) then
				list[#list + 1] = s.item
				if not ns.Weights.HasOwnRule(s.item) then
					unruled = unruled + 1
				end
			end
		end
	end
	return list, unruled, covered
end

local function HasItem(itemID)
	for _, s in ipairs(Slots()) do
		if s.item and s.item.itemID == itemID then
			return true
		end
	end
	return false
end

-- Categories already in this run's questions (asked, skipped, or still ahead after a Back).
local function Asked(st)
	local asked = {}
	for _, s in ipairs(st.steps) do
		if s.t == "rule" then
			asked[RuleId(s.kind, s.key)] = true
		end
		if s.fromClass then
			asked[RuleId("class", s.fromClass)] = true -- split up: its subclasses are asked instead
		end
	end
	return asked
end

-- Item classes in the bags with items that have no rule of their own and no question yet, the one
-- covering the most items first. Each: { key = classID, count, subs = { [subKey] = count } }.
local function Categories(st)
	local asked = Asked(st)
	local byClass, list = {}, {}
	for _, s in ipairs(Slots()) do
		local item = s.item
		if item and not asked[RuleId("class", item.classID)] and not ns.Weights.HasOwnRule(item) then
			local c = byClass[item.classID]
			if not c then
				c = { key = item.classID, count = 0, subs = {} }
				byClass[item.classID] = c
				list[#list + 1] = c
			end
			c.count = c.count + 1
			c.subs[item.subKey] = (c.subs[item.subKey] or 0) + 1
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)
	return list
end

local function NextCategory(st)
	local c = Categories(st)[1]
	return c and { t = "rule", kind = "class", key = c.key, dynamic = true } or nil
end

-- The subclasses of a class among its items without a rule, most items first: { subKey, ... }.
local function SubclassesOf(classID)
	local counts, list = {}, {}
	for _, s in ipairs(Slots()) do
		local item = s.item
		if item and item.classID == classID and not ns.Weights.HasOwnRule(item) then
			if not counts[item.subKey] then
				list[#list + 1] = item.subKey
			end
			counts[item.subKey] = (counts[item.subKey] or 0) + 1
		end
	end
	table.sort(list, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	return list
end

-- Steps ------------------------------------------------------------------------------------------

local function StaticSteps()
	return {
		{ t = "layout" },
		{ t = "hearth" },
		{ t = "neighbors" },
		{ t = "rule", kind = "flag", key = "gray" },
		{ t = "rule", kind = "class", key = TRADE_GOODS },
		{ t = "rule", kind = "flag", key = "equipmentSet", special = true },
		{ t = "rule", kind = "flag", key = "unboundGear", special = true },
		{ t = "rule", kind = "class", key = CONTAINER, special = true },
		{ t = "rule", kind = "flag", key = "quest", special = true },
	}
end

-- Is this step asked now? (Steps about items you don't have are passed over.)
local function Applicable(step)
	if step.t == "hearth" then
		return HasItem(HEARTHSTONE)
	elseif step.t == "neighbors" then
		return SedimentDB.weights.items[HEARTHSTONE] ~= nil and HasItem(HEARTHSTONE)
	elseif step.t == "rule" and step.special then
		return #MatchingItems(step) > 0
	end
	return true
end

-- For the "3 of 9" count: like Applicable, but counting the neighbours question before it's known.
local function Countable(step)
	if step.split then
		return false -- its subclass questions are counted instead
	elseif step.t == "neighbors" then
		return HasItem(HEARTHSTONE)
	end
	return Applicable(step)
end

-- Question number and total (nil on the review, which isn't a question).
local function Progress(st)
	local cur = st.steps[st.index]
	if not cur or cur.t == "review" then
		return nil
	end
	local n, at = 0, 0
	for i, step in ipairs(st.steps) do
		if step.t ~= "review" and (i == st.index or Countable(step)) then
			n = n + 1
			if i <= st.index then
				at = at + 1
			end
		end
	end
	return at, n + #Categories(st)
end

local function AfterChange()
	ns.Popup.Refresh()
	ns.Settings.Refresh() -- the ladder, if it's open, and the slot highlights
	ns.Sort.StartSoon()
end

-- Navigation ---------------------------------------------------------------------------------------

-- Show step i, going forward: remember the weights as they are, for Back.
local function Enter(i)
	local st = State()
	st.index = i
	st.steps[i].before = ns.Weights.CopyWeights()
	Render()
end

local function Forward()
	local st = State()
	local i = st.index + 1
	while true do
		if i > #st.steps then
			st.steps[i] = NextCategory(st) or { t = "review" }
		end
		local step = st.steps[i]
		if step.t == "review" then
			-- New categories can appear (after a Back and a different answer): ask them first.
			local c = NextCategory(st)
			if c then
				table.insert(st.steps, i, c)
				step = c
			end
		end
		if Applicable(step) then
			break
		end
		i = i + 1
	end
	Enter(i)
end

-- Back onto a split class question: drop its subclass questions, so it's asked as it was.
local function Unsplit(st, i)
	local step = st.steps[i]
	if not step.split then
		return
	end
	step.split = nil
	while st.steps[i + 1] and st.steps[i + 1].fromClass == step.key do
		table.remove(st.steps, i + 1)
	end
end

-- Back: return to the previous question and undo its answer (and everything after it).
local function Back()
	local st = State()
	local i = st.index - 1
	while i >= 1 and not Applicable(st.steps[i]) do
		i = i - 1
	end
	if i < 1 then
		page = "intro"
		Render()
		return
	end
	if st.steps[i].before then
		ns.Weights.SetWeights(st.steps[i].before)
	end
	Unsplit(st, i)
	st.index = i
	AfterChange()
	Render()
end

local function Answer(apply)
	apply()
	AfterChange()
	Forward()
end

-- Follow this class's question with one per subclass (of its items without a rule). The class question
-- stays in the list, marked split, so Back from its first subclass question returns to it (and un-splits).
local function Split()
	local st = State()
	local step = st.steps[st.index]
	local subs = SubclassesOf(step.key)
	if #subs < 2 then
		return
	end
	step.split = true
	for k, subKey in ipairs(subs) do
		table.insert(st.steps, st.index + k,
			{ t = "rule", kind = "subclass", key = subKey, fromClass = step.key, dynamic = true })
	end
	Enter(st.index + 1)
end


-- Where the window goes: where it was dragged, else beside the bags, else the middle of the screen.
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

local function Place(besideBags)
	frame:ClearAllPoints()
	local pos = SedimentDB.setupPos
	if pos then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
		return
	end
	local bag = besideBags and BagWindow()
	if bag and bag:GetLeft() and bag:GetTop() then
		local scale = bag:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local x = bag:GetLeft() * scale - 12 - WIDTH
		local top = math.max(bag:GetTop() * scale, HEIGHT + 20)
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", math.max(0, x), top)
	else
		frame:SetPoint("CENTER")
	end
end

-- Neighbours: Select mode with our own click handler ----------------------------------------------

local function PickIndex(itemID)
	for i, id in ipairs(picks) do
		if id == itemID then
			return i
		end
	end
end

local PICK_COLOR = { 0.4, 1, 0.4 }
local function PickLabel(item)
	local i = PickIndex(item.itemID)
	if i then
		return tostring(i), PICK_COLOR
	elseif item.itemID == HEARTHSTONE then
		return "H", PICK_COLOR
	end
end

local function OnPick(bag, slot)
	local item = ns.Bags.ReadSlot(bag, slot)
	if not item or item.itemID == HEARTHSTONE then
		return
	end
	local i = PickIndex(item.itemID)
	if i then
		table.remove(picks, i)
	else
		picks[#picks + 1] = item.itemID
	end
	ns.Settings.RefreshOverlays()
	Render()
end

local function ReleaseSelect()
	if ownSelect then
		ownSelect = false
		if ns.Settings.IsSelecting() then
			ns.Settings.SetSelectMode(false)
		end
	end
	picks = {}
end

-- Put the picks next to the hearthstone, the first one clicked nearest to it: after it if the hearthstone
-- is in the start half, before it if it's in the end half. Each pick goes on the far side of the one before,
-- so the order reads outward from the hearthstone either way (user, 2026-11-24: with the hearthstone last,
-- click order top to bottom put the first pick farthest from it).
local function ApplyPicks()
	local where = ns.Weights.RuleSide("item", HEARTHSTONE) == "float" and "after" or "before"
	local anchor = HEARTHSTONE
	for _, id in ipairs(picks) do
		ns.Weights.PlaceRule("item", id, where, "item", anchor)
		anchor = id
	end
end

-- Window ---------------------------------------------------------------------------------------------

local function Text(parent, template, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template)
	fs:SetJustifyH("LEFT")
	fs:SetWidth(width or PANE_W)
	return fs
end

local function Button(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, 22)
	b:SetText(text)
	return b
end

-- Anchor the shown regions one under another.
local function Stack(parent, regions, gap)
	local last
	for _, r in ipairs(regions) do
		if r:IsShown() then
			r:ClearAllPoints()
			if last then
				r:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(r.gapAbove or gap))
			else
				r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
			end
			last = r
		end
	end
end

local function SetShownText(fs, text)
	fs:SetText(text or "")
	fs:SetShown(text ~= nil and text ~= "")
end

local function BuildIntro(pane)
	local body = Text(pane, "GameFontHighlight")
	body:SetPoint("TOPLEFT")
	body:SetSpacing(3)
	body:SetText(N("AddonName") .. " keeps your bags sorted all the time, quietly, while they're closed. You "
		.. "decide the order: what floats to the top, what sinks to the bottom, and what sticks together. New "
		.. "loot lands in the " .. N("LootGap") .. " between, so you always see what's new.\n\n"
		.. "Start broad (\"trade goods sink\") and add exceptions (\"but keep my fishing pole up top\"): the "
		.. "most specific rule wins. Nothing moves while your bags are open unless you ask, and nothing ever "
		.. "moves in combat.\n\n"
		.. N("Onboarding") .. " asks a few questions about what's in your bags now. Each answer sorts them right "
		.. "away, so you see what it does. Anything not set yet is outlined in orange.")
	pane.body = body

	local tips = Text(pane, "GameFontDisableSmall")
	tips:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14)
	tips:SetText("Later: Alt+right-click any bag item to change its " .. N("SortValue") .. ". Right-click the sort "
		.. "button turns auto-sort on or off; the gear next to it opens your " .. N("SortValues") .. ", and ? there "
		.. "brings this back.")

	-- The same two buttons every time (user, 2026-11-25: buttons that change from visit to visit confuse);
	-- the status line above says what Continue would do. Start fresh: save the rules to History, clear the
	-- weights, ask everything. Continue: keep the rules, and carry on a run in progress or start one that
	-- asks only what isn't set; greyed when there's nothing to continue (no rules, no run).
	local function IntroButton(text, width, action, tip)
		local b = Button(pane, text, width)
		b:SetScript("OnClick", action)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip_SetTitle(GameTooltip, text)
			GameTooltip_AddNormalLine(GameTooltip, tip)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetMotionScriptsWhileDisabled(true) -- the tooltip explains a greyed Continue too
		return b
	end
	pane.fresh = IntroButton(L("ClearAllButton"), 120, function() Setup.Start(true) end,
		"Saves your rules to " .. N("SavedRules") .. " (if you have any), clears them (" .. N("SortValues") .. " and "
		.. L("KeepOutRule") .. "), and asks everything from the first question.")
	pane.fresh:SetPoint("BOTTOMLEFT", 0, 34)
	pane.continue = IntroButton(L("ResumeButton"), 110, function() Setup.Start() end,
		"Keeps your rules. Carries on where you left off, or asks only about what isn't set yet. Nothing to "
		.. "continue until you have rules or have started.")
	pane.continue:SetPoint("LEFT", pane.fresh, "RIGHT", 8, 0)
	pane.status = Text(pane, "GameFontHighlight") -- white, so the gold button names show
	pane.status:SetPoint("BOTTOMLEFT", pane.fresh, "TOPLEFT", 0, 10)
	-- The gear opens this page while there are no rules, so it needs a way on to the settings (the X just closes).
	pane.settings = Button(pane, L("OpenSettingsButton"), 90)
	pane.settings:SetPoint("BOTTOMRIGHT", 0, 34)
	pane.settings:SetScript("OnClick", function()
		frame:Hide()
		ns.Settings.Open("Weights")
	end)

	local dontShow = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
	dontShow:SetSize(24, 24)
	dontShow:SetPoint("BOTTOMLEFT", -4, 0)
	dontShow:SetScript("OnClick", function(self)
		SedimentDB.setupHidden = self:GetChecked() and true or nil
	end)
	local dontShowText = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dontShowText:SetPoint("LEFT", dontShow, "RIGHT", 4, 0)
	dontShowText:SetText("Don't show this; open the settings instead")
	pane.dontShow = dontShow
end

local function BuildQuestion(pane)
	pane.notice = Text(pane, "GameFontGreenSmall")
	pane.text = Text(pane, "GameFontHighlight")
	pane.text.gapAbove = 8
	pane.help = Text(pane, "GameFontDisableSmall")
	pane.now = Text(pane, "GameFontNormalSmall")
	pane.now.gapAbove = 6

	pane.iconRow = CreateFrame("Frame", nil, pane)
	pane.iconRow:SetSize(PANE_W, 28)
	pane.iconRow.gapAbove = 8
	pane.icons = {}
	for i = 1, MAX_ICONS do
		local b = CreateFrame("Button", nil, pane.iconRow)
		b:SetSize(26, 26)
		b:SetPoint("LEFT", (i - 1) * 29, 0)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.num = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		b.num:SetPoint("BOTTOMRIGHT", -1, 1)
		b:SetScript("OnEnter", function(self)
			if self.itemID then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetItemByID(self.itemID)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", function(self)
			if self.removable and self.itemID then -- a neighbour pick: click to take it off
				local k = PickIndex(self.itemID)
				if k then
					table.remove(picks, k)
					ns.Settings.RefreshOverlays()
					Render()
				end
			end
		end)
		pane.icons[i] = b
	end

	pane.choices = {}
	for i = 1, 3 do
		local row = CreateFrame("Frame", nil, pane)
		row:SetWidth(PANE_W)
		row.gapAbove = i == 1 and 12 or 6
		row.button = Button(row, "", CHOICE_W)
		row.button:SetHeight(24)
		row.button:SetPoint("TOPLEFT")
		row.desc = Text(row, "GameFontHighlightSmall", PANE_W - CHOICE_W - 10)
		row.desc:SetPoint("TOPLEFT", row.button, "TOPRIGHT", 10, -2)
		row.button:SetScript("OnClick", function()
			if row.onClick then
				row.onClick()
			end
		end)
		pane.choices[i] = row
	end

	pane.legend = Text(pane, "GameFontDisableSmall")
	pane.legend:SetPoint("BOTTOMLEFT", 0, 32)
	pane.legend:SetText("In your bags: |cffff8020orange|r = not set yet, |cffffd926gold|r = what this question is about.")

	pane.back = Button(pane, L("PrevQuestionButton"), 70)
	pane.back:SetPoint("BOTTOMLEFT")
	pane.back:SetScript("OnClick", Back)
	pane.skip = Button(pane, L("SkipQuestionButton"), 70)
	pane.skip:SetPoint("LEFT", pane.back, "RIGHT", 6, 0)
	pane.skip:SetScript("OnClick", Forward)
	pane.later = Button(pane, L("LeaveSetupButton"), 100)
	pane.later:SetPoint("BOTTOMRIGHT")
	pane.later:SetScript("OnClick", function()
		frame:Hide()
	end)
	pane.later:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L("LeaveSetupButton"))
		GameTooltip_AddNormalLine(GameTooltip, "Your answers so far are saved. Click the gear on your bag, then "
			.. B("ResumeButton") .. ", to carry on.")
		GameTooltip:Show()
	end)
	pane.later:SetScript("OnLeave", GameTooltip_Hide)
end

local reviewRows, reviewChild, reviewList = {}, nil, nil

local function RungLabel(e)
	local names, icon = {}, nil
	for _, r in ipairs(e.rules) do
		local label, ic = ns.Settings.RuleLabel(r.kind, r.key)
		names[#names + 1] = label
		icon = icon or ic
	end
	return table.concat(names, ", "), icon
end

local function RungIndex(id)
	for i, e in ipairs(reviewList or {}) do
		if e.rules and RuleId(e.rules[1].kind, e.rules[1].key) == id then
			return i
		end
	end
end

-- Not shown in the review: the default's rung (part of the empty space row) and, in the packed layouts,
-- the divider (it doesn't mark anything you can see there).
local function Hidden(e, packed)
	if e.divider then
		return packed
	end
	return #e.rules == 1 and e.rules[1].kind == "default"
end

-- The shown row a move from i in direction dir goes past (the empty space counts in the middle layout).
local function MoveTarget(i, dir)
	local packed = ns.Weights.Layout() ~= "middle"
	local j = i + dir
	while reviewList[j] and Hidden(reviewList[j], packed) do
		j = j + dir
	end
	return reviewList[j] and j or nil
end

-- In the review, the selected row's items get the gold outline: those whose winning rule is one of that
-- row's rules (user, 2026-11-25: clicking a row should show what it covers in the bag).
function ReviewFocus(item)
	local i = reviewSelected and RungIndex(reviewSelected)
	local rung = i and reviewList[i]
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

local function MoveSelected(dir)
	local i = RungIndex(reviewSelected)
	local j = i and MoveTarget(i, dir)
	if not j then
		return
	end
	-- Going down, removing it shifts the neighbour to j - 1, so j is just past it; going up, j is just before it.
	local e = table.remove(reviewList, i)
	table.insert(reviewList, j, e)
	ns.Weights.WriteRankingList(reviewList)
	AfterChange()
	Render()
end

local function BuildReview(pane)
	pane.help = Text(pane, "GameFontDisableSmall")
	pane.help:SetPoint("TOPLEFT")
	pane.help:SetText("Top to bottom, the way your bags are now. Click a row, then " .. B("RowUpButton") .. " or "
		.. B("RowDownButton") .. "; each move sorts your bags.")

	local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -34)
	scroll:SetPoint("BOTTOMRIGHT", -118, 34)
	reviewChild = CreateFrame("Frame", nil, scroll)
	reviewChild:SetSize(PANE_W - 140, 100)
	scroll:SetScrollChild(reviewChild)

	pane.up = Button(pane, L("RowUpButton"), 90)
	pane.up:SetPoint("TOPRIGHT", 0, -40)
	pane.up:SetScript("OnClick", function()
		MoveSelected(-1)
	end)
	pane.down = Button(pane, L("RowDownButton"), 90)
	pane.down:SetPoint("TOPRIGHT", pane.up, "BOTTOMRIGHT", 0, -6)
	pane.down:SetScript("OnClick", function()
		MoveSelected(1)
	end)

	pane.back = Button(pane, L("PrevQuestionButton"), 70)
	pane.back:SetPoint("BOTTOMLEFT")
	pane.back:SetScript("OnClick", Back)
	pane.done = Button(pane, L("FinishSetupButton"), 90)
	pane.done:SetPoint("BOTTOMRIGHT")
	pane.done:SetScript("OnClick", function()
		Setup.Finish()
	end)
end

local function ReviewRow(i)
	local row = reviewRows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, reviewChild)
	row:SetSize(PANE_W - 140, ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(1, 0.82, 0, 0.25)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 4, 0)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	-- The empty-space row: a line either side of its label.
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
	row.lines[2]:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function(self)
		if self.id then
			reviewSelected = self.id
			Render()
		end
	end)
	reviewRows[i] = row
	return row
end

local function RenderReview(pane)
	reviewList = ns.Weights.PinDefault(ns.Weights.RankingList())
	local layout = ns.Weights.Layout()
	local rows = {}
	if layout == "top" then
		rows[#rows + 1] = { gap = true }
	end
	local past = false
	for i, e in ipairs(reviewList) do
		if e.divider then
			past = true
			if layout == "middle" then
				rows[#rows + 1] = { gap = true }
			end
		elseif not Hidden(e, false) then
			rows[#rows + 1] = { index = i, sinks = past and layout == "middle" }
		end
	end
	if layout == "bottom" then
		rows[#rows + 1] = { gap = true }
	end
	if not RungIndex(reviewSelected) then
		reviewSelected = nil
	end
	for k, r in ipairs(rows) do
		local row = ReviewRow(k)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(k - 1) * ROW_HEIGHT)
		row:Show()
		row.label:ClearAllPoints()
		if r.gap then
			row.id = nil
			row.icon:Hide()
			row.selected:Hide()
			row.lines[1]:Show()
			row.lines[2]:Show()
			row.label:SetPoint("CENTER")
			row.label:SetText(L("LootGap"))
			row.label:SetTextColor(1, 0.7, 0.3)
			row:EnableMouse(false)
		else
			local e = reviewList[r.index]
			local label, icon = RungLabel(e)
			row.id = RuleId(e.rules[1].kind, e.rules[1].key)
			row.lines[1]:Hide()
			row.lines[2]:Hide()
			row:EnableMouse(true)
			if icon then
				row.icon:SetTexture(icon)
				row.icon:Show()
			else
				row.icon:Hide()
			end
			row.label:SetPoint("LEFT", 24, 0)
			row.label:SetPoint("RIGHT", -4, 0)
			row.label:SetText(label)
			if r.sinks then
				row.label:SetTextColor(0.8, 0.7, 0.55)
			else
				row.label:SetTextColor(0.9, 0.9, 0.9)
			end
			row.selected:SetShown(row.id == reviewSelected)
		end
	end
	for k = #rows + 1, #reviewRows do
		reviewRows[k]:Hide()
		reviewRows[k].id = nil
	end
	reviewChild:SetHeight(#rows * ROW_HEIGHT + 4)
	local i = RungIndex(reviewSelected)
	pane.up:SetEnabled(i ~= nil and MoveTarget(i, -1) ~= nil)
	pane.down:SetEnabled(i ~= nil and MoveTarget(i, 1) ~= nil)
end

local function Build()
	frame = CreateFrame("Frame", "SedimentSetup", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SedimentDB.setupPos = { x = self:GetLeft(), y = self:GetTop() } -- kept, like the weight popup
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8", -- solid, like the settings window
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 1) -- opaque, like the settings window
	frame:Hide()
	tinsert(UISpecialFrames, "SedimentSetup") -- Escape closes it (= Finish later)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", 16, -14)
	frame.title:SetPoint("RIGHT", -110, 0)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetWordWrap(false)
	frame.progress = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.progress:SetPoint("TOPRIGHT", -34, -17)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local function Pane()
		local p = CreateFrame("Frame", nil, frame)
		p:SetPoint("TOPLEFT", 16, -44)
		p:SetPoint("BOTTOMRIGHT", -16, 12)
		p:Hide()
		return p
	end
	frame.intro, frame.question, frame.review = Pane(), Pane(), Pane()
	BuildIntro(frame.intro)
	BuildQuestion(frame.question)
	BuildReview(frame.review)

	frame:SetScript("OnHide", function()
		ReleaseSelect()
		ns.Settings.SetHighlight(false)
	end)
end

-- Pages ----------------------------------------------------------------------------------------------

local function SetIcons(pane, items, numbered)
	local seen, k = {}, 0
	for _, item in ipairs(items) do
		local id = type(item) == "table" and item.itemID or item
		if not seen[id] and k < MAX_ICONS then
			seen[id] = true
			k = k + 1
			local b = pane.icons[k]
			b.itemID, b.removable = id, numbered
			b.tex:SetTexture(C_Item.GetItemIconByID(id))
			b.num:SetText(numbered and tostring(k) or "")
			b:Show()
		end
	end
	for i = k + 1, MAX_ICONS do
		pane.icons[i]:Hide()
		pane.icons[i].itemID = nil
	end
	pane.iconRow:SetShown(k > 0)
end

-- Up to three choices: { label, help, onClick, current = bool }.
local function SetChoices(pane, list)
	for i, row in ipairs(pane.choices) do
		local c = list[i]
		if c then
			row.button:SetText(c.label)
			row.desc:SetText(c.help .. (c.current and "  |cff66ff66(now)|r" or ""))
			row.onClick = c.onClick
			row:SetHeight(math.max(24, row.desc:GetStringHeight() + 4))
			row:Show()
		else
			row.onClick = nil
			row:Hide()
		end
	end
end

-- "Now: floats" for a rule that's set, from the order (nil if it has no rule).
local function NowText(kind, key)
	local side = ns.Weights.RuleSide(kind, key)
	if not side then
		return nil
	end
	local words = Words()
	return side == "float" and words.floats or words.sinks
end

local function RenderLayout(pane)
	frame.title:SetText("Your " .. L("LootGap"))
	SetShownText(pane.text, "Where do you want the " .. N("LootGap") .. " in your bags? New loot lands there, so that's "
		.. "where you'll see what's new.")
	SetShownText(pane.help, "Either way, things you put higher up come first. In the middle, the next questions "
		.. "ask float or sink; otherwise, higher up or lower down.")
	SetShownText(pane.now, nil)
	SetIcons(pane, {})
	local layout = ns.Weights.Layout()
	local function Choice(value, label, help)
		return { label = label, help = help, current = layout == value, onClick = function()
			Answer(function() ns.Weights.SetLayout(value) end)
		end }
	end
	SetChoices(pane, {
		Choice("middle", "In the middle", "Some things float to the top, others sink to the bottom; the "
			.. N("LootGap") .. " is between them."),
		Choice("bottom", "At the bottom", "Everything packed from the top, like a normal bag sort."),
		Choice("top", "At the top", "Everything packed toward the bottom of your bags."),
	})
end

local function RenderHearth(pane, step)
	frame.title:SetText("Your hearthstone")
	SetShownText(pane.text, "Where should your Hearthstone go?")
	SetShownText(pane.help, nil)
	local now = SedimentDB.weights.items[HEARTHSTONE] ~= nil
	SetShownText(pane.now, now and ("Now: " .. NowText("item", HEARTHSTONE) .. ".") or "Now: not set.")
	SetIcons(pane, { HEARTHSTONE })
	local layout = ns.Weights.Layout()
	local firstHelp = layout == "top" and "At the top, just below the " .. N("LootGap") .. "."
		or "Top left, before everything else."
	local lastHelp = layout == "bottom" and "After everything else, just before the " .. N("LootGap") .. "."
		or "Bottom right, after everything else."
	SetChoices(pane, {
		{ label = "First", help = firstHelp, onClick = function()
			Answer(function() ns.Weights.PlaceRule("item", HEARTHSTONE, "first") end)
		end },
		{ label = "Last", help = lastHelp, onClick = function()
			Answer(function() ns.Weights.PlaceRule("item", HEARTHSTONE, "last") end)
		end },
	})
end

local function RenderNeighbors(pane)
	frame.title:SetText("Next to your hearthstone")
	SetShownText(pane.text, "Anything you want next to your hearthstone? Click items in your bags, starting with "
		.. "the one you want right beside it; click one again (or its icon here) to take it off.")
	SetShownText(pane.help, "Clicks pick items while this question is up; they don't use them.")
	SetShownText(pane.now, #picks == 0 and "Nothing picked yet." or ("Picked: %d."):format(#picks))
	SetIcons(pane, picks, true)
	SetChoices(pane, {
		{ label = "OK", help = #picks > 0 and "Put them next to your hearthstone, 1 nearest."
			or "Nothing picked: OK goes on without changing anything.", onClick = function()
			Answer(ApplyPicks)
		end },
	})
end

local function RenderRule(pane, step)
	local id = RuleId(step.kind, step.key)
	local fixed = RULE_TEXT[id]
	local items, unruled, covered = MatchingItems(step)
	local name = ns.Settings.RuleLabel(step.kind, step.key)
	frame.title:SetText(fixed and fixed.title or name)
	SetShownText(pane.text, fixed and fixed.text or "Where should these go?")
	local count
	if #items == 0 and covered > 0 then
		count = "Everything in your bags that this covers already has its own " .. N("SortValue") .. "."
	elseif #items == 0 then
		count = "None in your bags right now; this is for when you have some."
	elseif unruled == #items then
		count = ("In your bags: %d item%s, none set yet."):format(#items, #items == 1 and "" or "s")
	else
		count = ("In your bags: %d item%s, %d not set yet."):format(#items, #items == 1 and "" or "s", unruled)
	end
	SetShownText(pane.help, count)
	local now = NowText(step.kind, step.key)
	SetShownText(pane.now, now and ("Now: " .. now .. ".") or nil)
	SetIcons(pane, items)
	local words = Words()
	local sinkHelp = words.sinkHelp
	if id == "flag:gray" then
		sinkHelp = "To the very bottom."
	end
	local choices = {
		{ label = words.float, help = words.floatHelp, current = now == words.floats, onClick = function()
			Answer(function() ns.Weights.PlaceRule(step.kind, step.key, "float") end)
		end },
		{ label = words.sink, help = sinkHelp, current = now == words.sinks, onClick = function()
			Answer(function()
				if id == "flag:gray" then
					ns.Weights.PlaceRule("flag", "gray", "bottom", "item", HEARTHSTONE)
				else
					ns.Weights.PlaceRule(step.kind, step.key, "sink")
				end
			end)
		end },
	}
	if step.dynamic and step.kind == "class" then
		local subs = SubclassesOf(step.key)
		if #subs >= 2 then
			local names = {}
			for k, subKey in ipairs(subs) do
				if k > 3 then
					names[#names] = names[#names] .. ", ..."
					break
				end
				local classID, subclassID = subKey:match("^(%-?%d+):(%-?%d+)$")
				names[#names + 1] = C_Item.GetItemSubClassInfo(tonumber(classID), tonumber(subclassID)) or subKey
			end
			choices[3] = { label = L("SplitGroupButton"), help = ("One question each: %s."):format(table.concat(names, ", ")),
				onClick = Split }
		end
	end
	SetChoices(pane, choices)
end

local function RenderIntro()
	local pane = frame.intro
	frame.title:SetText("Your bags, always in your order")
	frame.progress:SetText("")
	local st = State()
	local at, total
	if st and st.steps[st.index] then
		at, total = Progress(st)
	end
	if st and st.steps[st.index] then
		pane.status:SetText(B("ResumeButton") .. " to finish " .. N("Onboarding")
			.. (at and (" (question %d of %d)."):format(at, total) or "."))
		pane.continue:SetEnabled(true)
	elseif HasWeightRules() then
		pane.status:SetText(B("ResumeButton") .. " to use your existing rules, or " .. B("ClearAllButton")
			.. " to set them up from scratch.")
		pane.continue:SetEnabled(true)
	else
		pane.status:SetText(B("ClearAllButton") .. " to begin.")
		pane.continue:SetEnabled(false)
	end
	pane.dontShow:SetChecked(SedimentDB.setupHidden and true or false)
end

local function RenderNow()
	local st = State()
	local step = st and page == "steps" and st.steps[st.index]
	frame.intro:SetShown(not step)
	frame.question:SetShown(step and step.t ~= "review" or false)
	frame.review:SetShown(step and step.t == "review" or false)
	-- Select mode only on the neighbours question; highlights on every question.
	if step and step.t == "neighbors" then
		if not ownSelect then
			picks = {}
			ownSelect = true
			ns.Settings.SetSelectMode(true, OnPick, PickLabel)
		end
	elseif ownSelect then
		ReleaseSelect()
	end
	if not step then
		ns.Settings.SetHighlight(false)
		RenderIntro()
		return
	end
	ns.Settings.SetHighlight(true, function(item)
		if step.t == "neighbors" then
			return PickIndex(item.itemID) ~= nil
		elseif step.t == "review" then
			return ReviewFocus(item)
		end
		return Matches(step, item)
	end)
	local at, total = Progress(st)
	frame.progress:SetText(at and ("Question %d of %d"):format(at, total) or "Last step")
	if step.t == "review" then
		frame.title:SetText("Your order")
		RenderReview(frame.review)
		return
	end
	local pane = frame.question
	if step.t == "layout" then
		RenderLayout(pane)
	elseif step.t == "hearth" then
		RenderHearth(pane, step)
	elseif step.t == "neighbors" then
		RenderNeighbors(pane)
	else
		RenderRule(pane, step)
	end
	SetShownText(pane.notice, noticeIndex == st.index and (N("AddonName") .. " turned on Blizzard's Combined Backpack: "
		.. "it sorts in that window's order.") or nil)
	Stack(pane, { pane.notice, pane.text, pane.help, pane.now, pane.iconRow, pane.choices[1], pane.choices[2], pane.choices[3] }, 4)
end

function Render()
	if not frame or not frame:IsShown() then
		return
	end
	slotsCache = ns.Bags.Read()
	local ok, err = pcall(RenderNow)
	slotsCache = nil
	if not ok then
		error(err, 0)
	end
end

-- Entry points ---------------------------------------------------------------------------------------

-- The first page. auto: opened with the settings window (then it doesn't replace a question in progress).
function Setup.ShowIntro(auto)
	if InCombatLockdown() then
		return
	end
	if not frame then
		Build()
	end
	if auto and frame:IsShown() then
		return
	end
	page = "intro"
	if not frame:IsShown() then
		Place(false)
	end
	frame:Show()
	frame:Raise()
	Render()
end

-- Any weight rules (items, flags, subclasses, classes)? Keep-out rules don't count: Start fresh leaves them.
function HasWeightRules()
	local w = SedimentDB.weights
	return next(w.items) ~= nil or next(w.flags) ~= nil or next(w.subclasses) ~= nil or next(w.classes) ~= nil
end

-- Sediment's top-to-bottom order is the Combined Backpack's, so Setup needs Blizzard's Combined Backpack on
-- (user, 2026-11-25: turn it on when they start Setup, Start Fresh or Continue, never at login). The same
-- call Blizzard's own bag menu makes; its bag code re-lays out open bags. Returns true if it was off.
local function EnsureCombinedBackpack()
	if GetCVar("combinedBags") ~= nil and not GetCVarBool("combinedBags") then
		SetCVar("combinedBags", 1)
		return true
	end
	return false
end

-- Start (or carry on). over (Start Fresh): save the rules to History, clear them all (Weights and keep-out
-- rules: a fresh start, user 2026-11-25) and ask everything from the first question. Otherwise Continue: carry
-- on a run, or start one that keeps the rules. (Start over first kept the answers, which looked broken.)
function Setup.Start(over)
	if InCombatLockdown() then
		return
	end
	if not frame then
		Build()
	end
	local st = State()
	local resume = st and st.steps[st.index] and not over
	if not resume then
		if over then
			ns.Weights.ClearAll() -- a Snapshot of the rules first, if they aren't in History
		end
		SedimentDB.setup = { steps = StaticSteps(), index = 0 }
		if over then
			AfterChange()
		end
	end
	page = "steps"
	ns.Settings.Close() -- out of the way: the bags and this window are what matter now
	local turnedOn = EnsureCombinedBackpack()
	noticeIndex = nil -- only this start's notice, if any
	OpenAllBags()
	frame:Show()
	frame:Raise()
	Place(true)
	C_Timer.After(0, function()
		if frame:IsShown() then
			Place(true) -- again, once the bags have laid themselves out
		end
	end)
	if resume then
		Render()
	else
		Forward()
	end
	if turnedOn then
		-- Say so where they're looking (the question page) and in chat.
		noticeIndex = State().index
		ns.Print(N("AddonName") .. " turned on Blizzard's Combined Backpack (it sorts in that window's order).")
		Render()
	end
end

-- Done (the review's button): the run is over, the intro stops opening by itself.
function Setup.Finish()
	ns.Weights.Created()
	SedimentDB.setup = nil
	page = "intro"
	frame:Hide()
	ns.Print(N("Onboarding") .. " done. Alt+right-click any bag item to change its " .. N("SortValue")
		.. "; the gear on the bag opens your " .. N("SortValues") .. ".")
end

-- Should the gear and /sed open this (rather than Weights)? While there are no rules or a run isn't finished,
-- unless "Don't show this" is ticked. (SedimentDB.setupHidden: a new flag, so dismissing the old welcome
-- screen, welcomeHidden, doesn't hide these.)
function Setup.Wanted()
	local st = State()
	return not SedimentDB.setupHidden and (not HasWeightRules() or (st ~= nil and st.steps[st.index] ~= nil))
end

function Setup.IsShown()
	return frame ~= nil and frame:IsShown()
end

function Setup.Raise()
	if frame then
		frame:Raise()
	end
end

function Setup.Close()
	if frame then
		frame:Hide()
	end
end

-- Bag changes (our own sorts among them): keep counts, icons and the review current.
function Setup.OnBagUpdate()
	if frame and frame:IsShown() and page == "steps" then
		Render()
	end
end

-- Item names that weren't loaded yet.
function Setup.RefreshNames()
	Setup.OnBagUpdate()
end
