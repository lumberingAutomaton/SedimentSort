-- Sediment core: saved data, the bag sort button, the /sed command.
-- /sed is the only command: it opens the settings (user, 2026-11-26: "/sed is all we need"). The developer
-- tools that used to be commands are buttons in the Debug group's Tools section (needs the debug addon).

local ADDON, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Sediment.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local N, L = ns.Noun, ns.L -- nouns in its colour, plain words (see Text.lua)

function ns.Print(msg)
	print("|cffc8a96eSediment:|r " .. msg)
end
local Print = ns.Print

-- Every file the addon expects, in .toc order. Each marks itself in ns.loadedFiles as it loads; the login
-- check and the Debug > Files section compare the two (dev/files_check.lua keeps this list equal to the .toc).
ns.FILES = { "Text.lua", "Weights.lua", "Bags.lua", "Sound.lua", "Sort.lua", "AutoSort.lua", "Popup.lua",
	"Settings.lua", "Order.lua", "Sediment.lua" }
ns.ADDON = ADDON

-- Files in ns.FILES that didn't load (a /reload may not pick up a file new to the .toc; a restart does).
function ns.MissingFiles()
	local missing = {}
	for _, file in ipairs(ns.FILES) do
		if not ns.loadedFiles[file] then
			missing[#missing + 1] = file
		end
	end
	return missing
end

-- Sort button ---------------------------------------------------------------------------------
-- We replace the click and tooltip of Blizzard's bag sort button. We never touch
-- C_Container.SortBags itself: replacing a Blizzard API function taints everything that calls it.

local function ShowButtonTooltip(button)
	GameTooltip:SetOwner(button)
	GameTooltip_SetTitle(GameTooltip, L("AddonName"), HIGHLIGHT_FONT_COLOR)
	if ns.Sort.IsRunning() and not ns.Sort.IsQuiet() then
		GameTooltip_AddNormalLine(GameTooltip, "Sorting... click to cancel.")
	elseif ns.Sort.IsRunning() then
		GameTooltip_AddNormalLine(GameTooltip, "Sorting.")
	else
		GameTooltip_AddNormalLine(GameTooltip, "Your bags sort themselves whenever they're closed. Click to sort now.")
	end
	GameTooltip:Show()
end

local function TakeOverSortButton()
	local button = BagItemAutoSortButton
	if not button then
		Print("bag sort button not found; your bags still sort themselves while they're closed.")
		return
	end
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function()
		if ns.Sort.IsRunning() and not ns.Sort.IsQuiet() then
			ns.Sort.Cancel() -- a second click on a button sort cancels it
		else
			-- Starts a sort, or takes over a running auto-sort at full speed.
			PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
			ns.Sort.Start()
		end
	end)
	button:SetScript("OnEnter", ShowButtonTooltip)
end

-- Progress sweep -----------------------------------------------------------------------------
-- While a sort moves things, a cooldown sweep (the GCD clock) runs over the bag sort button and
-- the backpack button in the bag bar, so you can see it working with the bags open or closed.
-- It shows real progress (swaps done out of swaps known) but moves smoothly: after each swap it
-- glides toward the next swap's mark at the pace swaps have been arriving in this sort, and waits
-- at that mark if the next swap is late. If it falls behind the work done, it catches up quickly.
-- So it's never more than one swap ahead of the sort, never goes backwards, holds short of full
-- until the sort really ends, then finishes with the cooldown "bling".
-- (Time estimates made it finish early then start again, or crawl; plain steps looked broken.)
-- Sorts that move nothing never show it.

local MAX_SHOWN = 0.95  -- held here until the sort actually finishes
local FROZEN = 100000   -- a cooldown this long stands still; the glide below moves it each frame
local CATCH_UP = 0.15   -- seconds to close the gap when the sweep is behind the work done

local sweeps
local shown              -- fraction shown now; nil when no sort is showing
local floorF, capF = 0, 0 -- done/total, and the next swap's mark (never glide past it)
local pace = 0            -- fraction per second, from the time between swaps
local catchUp = 0         -- fraction per second to close a gap behind the work done in CATCH_UP
local swapInterval = 0.3  -- seconds between swaps, learned as sorts run
local lastDone, lastReport = 0, 0

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

local function Draw(fraction)
	local now = GetTime()
	for _, cd in ipairs(Sweeps()) do
		cd:SetCooldown(now - fraction * FROZEN, FROZEN)
	end
end

local glider = CreateFrame("Frame")
glider:Hide()
glider:SetScript("OnUpdate", function(self, elapsed)
	if not shown then
		self:Hide()
		return
	end
	if shown < floorF then
		shown = math.min(floorF, shown + math.max(catchUp, pace) * elapsed)
	elseif shown < capF then
		shown = math.min(capF, shown + pace * elapsed)
	end
	Draw(shown)
end)

function ns.OnSortProgress(done, total)
	local now = GetTime()
	if not shown then
		shown, lastDone, lastReport = 0, 0, now
	end
	if done > lastDone then
		local per = (now - lastReport) / (done - lastDone)
		if per > 0 then
			swapInterval = swapInterval * 0.6 + per * 0.4
		end
		lastDone, lastReport = done, now
	end
	floorF = math.min(total > 0 and done / total or 0, MAX_SHOWN)
	capF = done < total and math.min((done + 1) / total, MAX_SHOWN) or MAX_SHOWN
	pace = total > 0 and (1 / total) / math.max(swapInterval, 0.02) or 0
	catchUp = math.max(0, floorF - shown) / CATCH_UP -- a straight line, closing the gap in CATCH_UP
	glider:Show()
end

-- A sort's smoothness numbers are final a second after it ends (see Sort.lua); show them.
function ns.OnBenchRun()
	ns.Popup.BenchRefresh()
end

function ns.OnSortFinished(success)
	glider:Hide()
	if shown then
		local now = GetTime()
		for _, cd in ipairs(Sweeps()) do
			if success then
				-- Run the rest out in 0.15s, so the cooldown's finishing bling plays.
				local duration = 0.15 / (1 - shown)
				cd:SetCooldown(now - shown * duration, duration)
			else
				cd:Clear()
			end
		end
	end
	shown = nil
	ns.Popup.OnBagUpdate()
	ns.Popup.BenchRefresh()
end

function ns.OnSortStateChanged()
	local button = BagItemAutoSortButton
	if button and GameTooltip:IsOwned(button) then
		ShowButtonTooltip(button)
	end
end

-- Scan and /sed --------------------------------------------------------------------------------

local function FormatWeight(w)
	return w == nil and "—" or tostring(w)
end

-- Every item in the bags with its class, subclass, quality, flags and weight, in chat; also saved to
-- SedimentDB.lastScan for dev/sim.lua. The Debug group's Tools section has a button for it.
function ns.Scan()
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
SlashCmdList.SEDIMENT = function()
	ns.Settings.Toggle()
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
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		SedimentDB = SedimentDB or {}
		SedimentDB.lastMove = nil -- left over from the 0.0.1 probe
		ns.Weights.Init()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		-- A file new to the .toc may not load on a /reload (a full restart always works). Without it the rest
		-- of the addon can't work, so say so instead of failing quietly. Debug > Files shows the same list.
		local missing = ns.MissingFiles()
		if #missing > 0 then
			Print("|cffff6666not loaded: " .. table.concat(missing, ", ")
				.. ". Exit WoW completely and start it again (a /reload isn't enough for new files).|r")
			self:UnregisterAllEvents()
			return
		end
		ns.Weights.SetCharacter(UnitName("player"))
		ns.Weights.Snapshot() -- safety net; logout normally takes it (only if the rules aren't in History)
		TakeOverSortButton()
		ns.Popup.Hook()
		ns.Popup.CreateBagButton()
	elseif event == "PLAYER_LOGOUT" then
		-- Logout, quit and /reload all fire this before WoW writes saved data: a Snapshot of the rules if
		-- they've changed (user, 2026-11-25: logout rather than login; a crash skips it, but then the
		-- session's changes aren't written either).
		ns.Weights.Snapshot()
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.AutoSort.OnEnteringWorld()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		ns.Settings.RefreshNames() -- item names in the ladder that weren't loaded yet (no re-sort)
		ns.Order.OnBagUpdate() -- item names in the Order list
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.Sort.OnCombatStart()
		ns.Settings.OnCombat()
	elseif event == "QUEST_LOG_UPDATE" then
		ns.AutoSort.OnQuestLogChanged()
	elseif event == "BAG_UPDATE_DELAYED" then
		ns.Sort.OnBagUpdateDelayed()
		ns.AutoSort.OnBagUpdateDelayed()
		ns.Popup.OnBagUpdate()
		if ns.Settings.OverlaysActive() then
			ns.Settings.RefreshOverlays()
		end
		ns.Order.OnBagUpdate()
	end
end)
