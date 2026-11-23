-- Sediment core: saved data, the bag sort button, slash commands.
--
-- /sed          Open the settings window (ladder of weights, general settings). /sed help lists the rest.
-- /sed sort     Sort the bags (same as clicking the bag sort button).
-- /sed cancel   Stop a sort in progress.
-- /sed auto     Toggle auto-sort on loot (same as right-clicking the bag sort button).
-- /sed status   Show whether a sort is pending, what it's waiting for, and the last sort's cost.
--               (/sed auto? does the same.)
-- /sed delay [s] Show or set how long auto-sort waits after the last bag change.
-- /sed budget [ms] Show or set auto-sort's time budget per frame for sending swaps.
-- /sed why      Hover a bag item, then run this: shows its weight cascade and which level won.
--               Alt+right-click a bag item opens the same thing as an editable popup (Popup.lua).
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
	if ns.Sort.IsRunning() and ns.Sort.IsQuiet() then
		GameTooltip_AddNormalLine(GameTooltip, "Auto-sort waiting for the bags to close. Click to finish it now.")
	elseif ns.Sort.IsRunning() then
		GameTooltip_AddNormalLine(GameTooltip, "Sorting... click to cancel.")
	else
		GameTooltip_AddNormalLine(GameTooltip, "Light items float to the top, heavy items sink to the bottom.")
	end
	GameTooltip_AddBlankLineToTooltip(GameTooltip)
	GameTooltip_AddInstructionLine(GameTooltip, "Left-click: sort now")
	local state = ns.AutoSort.IsEnabled() and "|cff66ff66ON|r" or "|cffff6666OFF|r"
	GameTooltip_AddInstructionLine(GameTooltip, "Right-click: auto-sort on loot (" .. state .. ")")
	GameTooltip:Show()
end

-- Dim the button while auto-sort is off, so the mode is visible at a glance.
local function UpdateButtonLook()
	local button = BagItemAutoSortButton
	if not button then
		return
	end
	local on = ns.AutoSort.IsEnabled()
	local normal = button:GetNormalTexture()
	if normal then
		normal:SetDesaturated(not on)
	end
	button:SetAlpha(on and 1 or 0.6)
end

local function TakeOverSortButton()
	local button = BagItemAutoSortButton
	if not button then
		Print("bag sort button not found; use /sed sort.")
		return
	end
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ns.AutoSort.Toggle()
		elseif ns.Sort.IsRunning() and not ns.Sort.IsQuiet() then
			ns.Sort.Cancel() -- a second click on a button sort cancels it
		else
			-- Starts a sort, or takes over an auto-sort (paused while the bags are open) at full speed.
			PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			ns.Sort.Start()
		end
	end)
	button:SetScript("OnEnter", ShowButtonTooltip)
	UpdateButtonLook()
end

function ns.OnAutoSortChanged()
	UpdateButtonLook()
	local button = BagItemAutoSortButton
	if button and GameTooltip:IsOwned(button) then
		ShowButtonTooltip(button)
	end
end

-- Progress sweep -----------------------------------------------------------------------------
-- While a sort moves things, a cooldown sweep (the GCD clock) runs over the bag sort button and
-- the backpack button in the bag bar, so you can see it working with the bags open or closed.
-- It runs for the estimated time left and re-aims every round, so it ends when the sort does.
-- A sort that finishes ends it with the cooldown "bling"; an interrupted one just clears it.
-- Sorts that move nothing never show it.

local sweeps
local sweepStartedAt

local function Sweeps()
	if not sweeps then
		sweeps = {}
		for _, name in ipairs({ "BagItemAutoSortButton", "MainMenuBarBackpackButton" }) do
			local parent = _G[name]
			if parent then
				local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
				cd:SetAllPoints(parent)
				cd:SetHideCountdownNumbers(true)
				cd:SetDrawEdge(true)
				cd:SetDrawBling(true)
				sweeps[#sweeps + 1] = cd
			end
		end
	end
	return sweeps
end

function ns.OnSortProgress(secondsLeft)
	sweepStartedAt = sweepStartedAt or GetTime()
	local duration = (GetTime() - sweepStartedAt) + secondsLeft
	for _, cd in ipairs(Sweeps()) do
		cd:SetCooldown(sweepStartedAt, duration)
	end
end

-- A paused auto-sort: clear the sweep; it starts fresh, re-aimed, when the sort carries on.
function ns.OnSortPaused()
	if sweepStartedAt then
		for _, cd in ipairs(Sweeps()) do
			cd:Clear()
		end
		sweepStartedAt = nil
	end
end

-- A sort's smoothness numbers are final a second after it ends (see Sort.lua); show them.
function ns.OnBenchRun()
	ns.Popup.BenchRefresh()
end

function ns.OnSortFinished(success)
	if sweepStartedAt then
		for _, cd in ipairs(Sweeps()) do
			if success then
				-- Run out a moment from now, so the cooldown's finishing bling plays.
				cd:SetCooldown(sweepStartedAt, (GetTime() - sweepStartedAt) + 0.15)
			else
				cd:Clear()
			end
		end
		sweepStartedAt = nil
	end
	ns.Popup.OnBagUpdate()
	ns.Popup.BenchRefresh()
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
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "config" or cmd == "settings" then
		ns.Settings.Toggle()
	elseif cmd == "help" then
		Print("/sed (settings), /sed sort, /sed cancel, /sed auto, /sed status, /sed delay [s], /sed budget [ms], "
			.. "/sed why (hover an item), /sed bench, /sed scan")
	elseif cmd == "budget" then
		if arg ~= "" and not tonumber(arg) then
			Print("/sed budget <ms>, e.g. /sed budget 0.5")
		else
			ns.Sort.SetBudget(tonumber(arg))
		end
	elseif cmd == "delay" then
		if arg ~= "" and not tonumber(arg) then
			Print("/sed delay <seconds>, e.g. /sed delay 1.5")
		else
			ns.AutoSort.SetDelay(tonumber(arg))
		end
	elseif cmd == "sort" then
		ns.Sort.Start()
	elseif cmd == "cancel" then
		ns.Sort.Cancel()
	elseif cmd == "auto" then
		ns.AutoSort.Toggle()
	elseif cmd == "auto?" or cmd == "status" then
		ns.AutoSort.Status()
	elseif cmd == "bench" then
		ns.Popup.ToggleBench(ns.Popup.benchButton)
	elseif cmd == "mutetest" then
		ns.Sound.Test()
	elseif cmd == "why" then
		Why()
	elseif cmd == "scan" then
		Scan()
	else
		Print("/sed sort, /sed cancel, /sed auto (toggle auto-sort on loot), /sed status, /sed delay [seconds], /sed budget [ms], /sed why (hover an item), /sed scan")
	end
end

-- Events --------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SedimentDB = SedimentDB or {}
		SedimentDB.lastMove = nil -- left over from the 0.0.1 probe
		ns.Weights.Init()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		-- /reload doesn't pick up files newly added to the .toc; only a full client restart does.
		-- Without them the rest of the addon can't work, so say so instead of failing quietly.
		local missing = {}
		for _, module in ipairs({ "Weights", "Bags", "Sound", "Sort", "AutoSort", "Popup", "Settings" }) do
			if not ns[module] then
				missing[#missing + 1] = module .. ".lua"
			end
		end
		if #missing > 0 then
			Print("|cffff6666not loaded: " .. table.concat(missing, ", ")
				.. ". Exit WoW completely and start it again (a /reload isn't enough for new files).|r")
			self:UnregisterAllEvents()
			return
		end
		TakeOverSortButton()
		ns.Popup.Hook()
		ns.Popup.CreateBenchButton()
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.AutoSort.OnEnteringWorld()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		ns.Settings.Refresh() -- item names in the ladder that weren't loaded yet
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.Sort.OnCombatStart()
	elseif event == "QUEST_LOG_UPDATE" then
		ns.AutoSort.OnQuestLogChanged()
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.Sort.OnBagUpdateDelayed()
		ns.AutoSort.OnBagUpdateDelayed()
		ns.Popup.OnBagUpdate()
	end
end)
