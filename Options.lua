-- Options: one section (user, 2026-11-27: Timing and Special bags merged), Timing on top, then Special bags.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Options.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Options = {}
ns.Options = Options
local Settings = ns.Settings
local UI = Settings.UI
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)
local Flow, Text, HelpText, NewBox, LabeledBox, CheckRow = UI.Flow, UI.Text, UI.HelpText, UI.NewBox, UI.LabeledBox,
	UI.CheckRow
local GAP_HELP, GAP_GROUP, CONTROL_X, CONTENT_W, ROW_HEIGHT, CLICK_GUARD = UI.GAP_HELP, UI.GAP_GROUP, UI.CONTROL_X,
	UI.CONTENT_W, UI.ROW_HEIGHT, UI.CLICK_GUARD
local Changed, WeightChanged, FormatWeight = UI.Changed, UI.WeightChanged, UI.FormatWeight
local ItemLabel, ClassLabel, SubclassLabel, KeepOutLabel = UI.ItemLabel, UI.ClassLabel, UI.SubclassLabel, UI.KeepOutLabel

-- A heading inside the section: Timing, Special bags.
local function Heading(page, place, gap, text)
	return place(Text(page, "GameFontNormalLarge", text), gap, 4)
end

-- Timing: the two numbers worth tuning. Auto-sort itself is always on, sorts in the full order, and an
-- auto-sort running when the bags open finishes at full speed (user, 2026-11-26: those aren't choices).
local function BuildTiming(page, place)
	Heading(page, place, 0, "Timing")
	LabeledBox(page, place, GAP_GROUP, "Wait after changes (seconds)",
		"How long the bags must be quiet before they sort. Long enough for a burst of looting to finish and "
		.. "new quest items to register.",
		ns.AutoSort.Delay, function(n) DisorderItemManagerDB.autoSortDelay = math.max(0, math.min(30, n)) end)
	LabeledBox(page, place, GAP_GROUP, "Smoothness (ms per frame)",
		"How much time per frame, on average, sorting may spend moving items while the bags are closed. "
		.. "Lower is smoother but slower. The sort button always goes full speed.",
		ns.Sort.BudgetMs, function(n) DisorderItemManagerDB.streamBudgetMs = math.max(0.01, math.min(50, n)) end)
end

-- Special bags: which special bags you have, the fill switch, and every keep-out rule (Keep out of special
-- bags: all Cloth, or one item) with x to remove it. Removing doesn't re-sort the list: the row greys out
-- with Undo, so nothing moves under the mouse. Rules are added from the weight popup.
local specialRows = {}

local function BuildSpecialBags(page, place)
	Heading(page, place, GAP_GROUP * 2, "Special bags")
	local bagsText = place(Text(page, "GameFontHighlight"), GAP_GROUP, 4, true)
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
				DisorderItemManagerDB.fillSpecialBags = nil -- the default: fill
			else
				DisorderItemManagerDB.fillSpecialBags = false
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
	function Options.RefreshSpecialList()
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

local function BuildOptionsPage(page)
	local place = Flow(page)
	BuildTiming(page, place)
	BuildSpecialBags(page, place)
end

Settings.AddPage("Options", {
	build = BuildOptionsPage,
	onShow = function()
		if Options.RefreshSpecialList then
			Options.RefreshSpecialList()
		end
	end,
})
