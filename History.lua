-- History: the History section (the saves themselves are in Rules.lua until the data change).

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["History.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Settings = ns.Settings
local UI = Settings.UI
local N, B, L = ns.Noun, ns.Btn, ns.L -- nouns, button names in sentences, plain words (see Text.lua)
local Flow, Text, HelpText, NewBox, LabeledBox, CheckRow = UI.Flow, UI.Text, UI.HelpText, UI.NewBox, UI.LabeledBox,
	UI.CheckRow
local GAP_HELP, GAP_GROUP, CONTROL_X, CONTENT_W, ROW_HEIGHT, CLICK_GUARD = UI.GAP_HELP, UI.GAP_GROUP, UI.CONTROL_X,
	UI.CONTENT_W, UI.ROW_HEIGHT, UI.CLICK_GUARD
local Changed, WeightChanged, FormatWeight = UI.Changed, UI.WeightChanged, UI.FormatWeight
local ItemLabel, ClassLabel, SubclassLabel, KeepOutLabel = UI.ItemLabel, UI.ClassLabel, UI.SubclassLabel, UI.KeepOutLabel

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

Settings.AddPage("History", {
	build = BuildHistoryPage,
	onWindowHide = function()
		ns.Weights.PurgeDeleted() -- saves marked with x go for good when the window closes
	end,
})
