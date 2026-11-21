-- Sediment core: saved data, the bag sort button, slash commands.
--
-- /sed sort     Sort the bags (same as clicking the bag sort button).
-- /sed cancel   Stop a sort in progress.
-- /sed why      Hover a bag item, then run this: shows its weight cascade and which level won.
-- /sed scan     List class, subclass, quality and flags for every item (also saved to SedimentDB.lastScan).

local ADDON, ns = ...

function ns.Print(msg)
	print("|cffc8a96eSediment:|r " .. msg)
end
local Print = ns.Print

-- Sort button ---------------------------------------------------------------------------------
-- We replace the click and tooltip of Blizzard's bag sort button. We never touch
-- C_Container.SortBags itself: replacing a Blizzard API function taints everything that calls it.

local function ShowButtonTooltip(button)
	GameTooltip:SetOwner(button)
	GameTooltip_SetTitle(GameTooltip, "Sediment: sort by weight", HIGHLIGHT_FONT_COLOR)
	if ns.Sort.IsRunning() then
		GameTooltip_AddNormalLine(GameTooltip, "Sorting... click to cancel.")
	else
		GameTooltip_AddNormalLine(GameTooltip, "Light items float to the top, heavy items sink to the bottom.")
	end
	GameTooltip:Show()
end

local function TakeOverSortButton()
	local button = BagItemAutoSortButton
	if not button then
		Print("bag sort button not found; use /sed sort.")
		return
	end
	button:SetScript("OnClick", function(self)
		if ns.Sort.IsRunning() then
			ns.Sort.Cancel()
		else
			PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			ns.Sort.Start()
		end
	end)
	button:SetScript("OnEnter", ShowButtonTooltip)
end

function ns.OnSortStateChanged()
	local button = BagItemAutoSortButton
	if button and GameTooltip:IsOwned(button) then
		ShowButtonTooltip(button)
	end
end

-- Slash commands ------------------------------------------------------------------------------

local function HoveredBagSlot()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()[1]
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if focus and focus.GetBagID and focus.GetID then
		local bag, slot = focus:GetBagID(), focus:GetID()
		if bag and slot then
			return bag, slot
		end
	end
end

local function FormatWeight(w)
	return w == nil and "—" or tostring(w)
end

local function Why()
	local bag, slot = HoveredBagSlot()
	if not bag then
		Print("hover an item in your bags, then run /sed why (bind it to a macro to make that easy).")
		return
	end
	local item = ns.Bags.ReadSlot(bag, slot)
	if not item then
		Print("that slot is empty.")
		return
	end
	local levels, winner = ns.Weights.Explain(item)
	local weight = levels[winner].weight
	Print(("%s: weight %s from %s (sink line %s, so it %s)."):format(item.link, FormatWeight(weight),
		levels[winner].label, ns.Weights.SinkLine(), weight < ns.Weights.SinkLine() and "floats" or "sinks"))
	for i, level in ipairs(levels) do
		local mark = i == winner and "  <- wins" or ""
		local note = level.applies and "" or " (doesn't apply)"
		print(("   %s: %s%s%s"):format(level.label, FormatWeight(level.weight), note, mark))
	end
end

local function Scan()
	local rows = {}
	local slots = ns.Bags.Read()
	for _, s in ipairs(slots) do
		local item = s.item
		if item then
			item.weight, item.weightFrom = ns.Weights.Resolve(item)
			rows[#rows + 1] = item
			print(("  %d/%d %s x%d | %s(%d) > %s(%d) | q%s%s%s | w%s from %s"):format(
				item.bag, item.slot, item.link, item.count,
				item.className or "?", item.classID, item.subclassName or "?", item.subclassID,
				tostring(item.quality), item.isQuestItem and " QUEST" or "", item.isBound and " bound" or "",
				FormatWeight(item.weight), item.weightFrom))
		end
	end
	SedimentDB.lastScan = { time = date("%Y-%m-%d %H:%M:%S"), rows = rows }
	Print(("%d items in %d sortable slots. /reload to write the scan to disk."):format(#rows, #slots))
end

SLASH_SEDIMENT1 = "/sediment"
SLASH_SEDIMENT2 = "/sed"
SlashCmdList.SEDIMENT = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "sort" then
		ns.Sort.Start()
	elseif cmd == "cancel" then
		ns.Sort.Cancel()
	elseif cmd == "why" then
		Why()
	elseif cmd == "scan" then
		Scan()
	else
		Print("/sed sort, /sed cancel, /sed why (hover an item), /sed scan")
	end
end

-- Events --------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SedimentDB = SedimentDB or {}
		SedimentDB.lastMove = nil -- left over from the 0.0.1 probe
		ns.Weights.Init()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		TakeOverSortButton()
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.Sort.OnBagUpdateDelayed()
	end
end)
