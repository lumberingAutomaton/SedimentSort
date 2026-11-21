-- Popup: Alt+right-click a bag item to see and edit its weight cascade.
--
-- Each level that applies to the item gets a box. Type a number and press Enter (or click away)
-- to set it; clear the box to make that level inherit. The winning level is marked.

local _, ns = ...
local Popup = {}
ns.Popup = Popup

local ROW_HEIGHT = 24
local WIDTH = 300
local WIN_COLOR = { 0.4, 1, 0.4 }
local NORMAL_COLOR = { 1, 0.82, 0 }
local DIM_COLOR = { 0.6, 0.6, 0.6 }

local frame
local rows = {}
local current -- { bag, slot }

local function FormatWeight(w)
	if w == nil then
		return ""
	end
	return tostring(w)
end

local function Build()
	frame = CreateFrame("Frame", "SedimentWeightPopup", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, 100)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	frame:Hide()
	tinsert(UISpecialFrames, "SedimentWeightPopup") -- Escape closes it

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(28, 28)
	frame.icon:SetPoint("TOPLEFT", 12, -12)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)
	frame.title:SetPoint("RIGHT", close, "LEFT", -4, 0)
	frame.title:SetJustifyH("LEFT")

	frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.summary:SetPoint("TOPLEFT", frame.icon, "BOTTOMLEFT", 0, -8)
	frame.summary:SetPoint("RIGHT", -12, 0)
	frame.summary:SetJustifyH("LEFT")

	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.hint:SetText("Enter a number to set a level. Clear it to inherit.")
	frame.hint:SetJustifyH("LEFT")

	frame.sortButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.sortButton:SetSize(90, 22)
	frame.sortButton:SetText("Sort now")
	frame.sortButton:SetScript("OnClick", function()
		ns.Sort.Start()
	end)

	frame:SetScript("OnHide", function()
		current = nil
	end)
end

-- Turn the text in a box into a value. Returns ok, value (value nil = clear).
local function ParseBox(text)
	text = strtrim(text or "")
	if text == "" then
		return true, nil
	end
	local n = tonumber(text)
	if n then
		return true, n
	end
	return false
end

local function GetRow(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, frame)
	row:SetSize(WIDTH - 24, ROW_HEIGHT)

	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.label:SetPoint("LEFT")
	row.label:SetJustifyH("LEFT")

	row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	row.box:SetSize(60, 20)
	row.box:SetPoint("RIGHT", -40, 0)
	row.box:SetAutoFocus(false)
	row.box:SetMaxLetters(10)

	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.mark:SetPoint("LEFT", row.box, "RIGHT", 6, 0)

	local function Commit(box)
		if not row.level then
			return
		end
		local ok, value = ParseBox(box:GetText())
		local level = row.level
		if ok and (value ~= nil or (level.kind ~= "default" and level.kind ~= "sinkLine")) then
			ns.Weights.SetLevel(level.kind, level.key, value)
		end
		Popup.Refresh()
	end
	row.box:SetScript("OnEnterPressed", function(box)
		Commit(box)
		box:ClearFocus()
	end)
	row.box:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		Popup.Refresh()
	end)
	row.box:SetScript("OnEditFocusLost", Commit)

	rows[i] = row
	return row
end

function Popup.Refresh()
	if not current or not frame:IsShown() then
		return
	end
	local item = ns.Bags.ReadSlot(current.bag, current.slot)
	if not item or item.itemID ~= current.itemID then
		-- The item moved (a sort, or the user). Follow it by item ID.
		item = nil
		for _, s in ipairs(ns.Bags.Read()) do
			if s.item and s.item.itemID == current.itemID then
				item = s.item
				current.bag, current.slot = s.bag, s.slot
				break
			end
		end
		if not item then
			frame:Hide()
			return
		end
	end

	local _, _, _, _, icon = C_Item.GetItemInfoInstant(item.itemID)
	frame.icon:SetTexture(icon)
	frame.title:SetText(item.link)

	local levels, winner = ns.Weights.Explain(item)
	local weight = levels[winner].weight
	local sinkLine = ns.Weights.SinkLine()
	frame.summary:SetText(("Weight %s from %s: %s"):format(FormatWeight(weight), levels[winner].label,
		weight < sinkLine and "floats" or "sinks"))

	-- Rows: every level that applies to this item, then the sink line.
	local shown = {}
	for i, level in ipairs(levels) do
		if level.applies then
			shown[#shown + 1] = { level = level, wins = i == winner }
		end
	end
	shown[#shown + 1] = { level = { kind = "sinkLine", label = "Sink line", weight = sinkLine } }

	local y = -76
	for i, entry in ipairs(shown) do
		local row = GetRow(i)
		local level = entry.level
		row.level = level
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 12, y)
		row:Show()
		local label = level.label
		if level.kind == "subclass" or level.kind == "class" then
			label = label .. (level.kind == "subclass" and " |cff999999(subclass)|r" or " |cff999999(class)|r")
		end
		row.label:SetText(label)
		local color = entry.wins and WIN_COLOR or (level.kind == "sinkLine" and DIM_COLOR or NORMAL_COLOR)
		row.label:SetTextColor(unpack(color))
		row.mark:SetText(entry.wins and "|cff66ff66< wins|r" or "")
		if not row.box:HasFocus() then
			row.box:SetText(FormatWeight(level.weight))
			row.box:SetCursorPosition(0)
		end
		y = y - ROW_HEIGHT
		if level.kind == "default" then
			y = y - 6 -- a little space before the sink line
		end
	end
	for i = #shown + 1, #rows do
		rows[i]:Hide()
		rows[i].level = nil
	end

	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", 12, y - 6)
	frame.hint:SetWidth(WIDTH - 24)
	frame.sortButton:ClearAllPoints()
	frame.sortButton:SetPoint("TOPRIGHT", -12, y - 24)
	frame:SetHeight(-y + 56)
end

function Popup.Open(bag, slot)
	if not frame then
		Build()
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		return
	end
	current = { bag = bag, slot = slot, itemID = info.itemID }
	if not frame:IsShown() then
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / scale - 16, y / scale + 16)
	end
	frame:Show()
	Popup.Refresh()
end

-- Every modified click on a bag item calls HandleModifiedItemClick. Alt+right-click does nothing
-- there by default, so a post-hook is safe (no taint, Blizzard's own handling still runs).
function Popup.Hook()
	hooksecurefunc("HandleModifiedItemClick", function(link, itemLocation)
		if not (IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()) then
			return
		end
		if GetMouseButtonClicked and GetMouseButtonClicked() ~= "RightButton" then
			return
		end
		if not (itemLocation and itemLocation.IsBagAndSlot and itemLocation:IsBagAndSlot()) then
			return
		end
		Popup.Open(itemLocation:GetBagAndSlot())
	end)
end

-- Keep an open popup current when the item moves or the bags change.
function Popup.OnBagUpdate()
	if frame and frame:IsShown() then
		Popup.Refresh()
	end
end
