-- SortButton: the bag's sort button (taken over from the built-in sort), the gear next to it that opens the
-- settings, and the progress sweep while a sort runs.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["SortButton.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local SortButton = {}
ns.SortButton = SortButton
local N, L = ns.Noun, ns.L -- nouns in their colour, plain words (see Text.lua)
local Print = function(msg) ns.Print(msg) end

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
	ns.Debug.BenchRefresh()
end

function ns.OnSortStateChanged()
	local button = BagItemAutoSortButton
	if button and GameTooltip:IsOwned(button) then
		ShowButtonTooltip(button)
	end
end

-- The bag button: a small icon left of the sort button (a child of it, so it shows and moves with
-- it) that opens the settings window on the Sorting tab. Picked in game (2026-11-24):
-- - Blizzard's button-style gear: people read a gear as "settings", and a button graphic has
--   transparent padding like the old dice, so it sits lightly where a full-square item icon looked heavy.
-- - 15 units, not 16: an empirical fit (16 looked about half a pixel low). The search bar is 18 units
--   tall, so not an odd/even centring issue; most likely its border art isn't centred in its frame, or
--   the UI scale's rounding onto screen pixels. Sizes are in UI units, so the gear scales with the bag
--   at any UI scale; at other scales the rounding may land half a pixel differently.
-- - Vertically centred on the search bar (the sort button sits a little lower), re-measured when shown
--   and whenever Blizzard repositions the sort button.
local ICON = "Interface\\Buttons\\UI-OptionsButton"
local bagButton
local ICON_SIZE = 15

local function CreateBagButton()
	local sortButton = BagItemAutoSortButton
	if not sortButton or bagButton then
		return
	end
	-- Values left over from tuning the icon in game (/sed icon, nudge, iconsize, now removed).
	DisorderItemManagerDB.bagIcon, DisorderItemManagerDB.bagIconNudge, DisorderItemManagerDB.bagIconSize, DisorderItemManagerDB.bagIconVersion = nil, nil, nil, nil
	local b = CreateFrame("Button", nil, sortButton)
	b:SetSize(20, 20)
	b:SetPoint("RIGHT", sortButton, "LEFT", -2, 0)
	local function Align()
		local search = BagItemSearchBox
		local searchY, sortY
		if search and search:IsVisible() then
			searchY = select(2, search:GetCenter()) -- GetCenter returns x, y; "a and f()" would keep only x
		end
		sortY = select(2, sortButton:GetCenter())
		local dy = (searchY and sortY) and (searchY - sortY) or 0
		b:ClearAllPoints()
		b:SetPoint("RIGHT", sortButton, "LEFT", -2, dy)
	end
	b:SetScript("OnShow", function()
		Align()
		C_Timer.After(0, Align) -- again once the bag has finished laying itself out
	end)
	hooksecurefunc(sortButton, "SetPoint", function() C_Timer.After(0, Align) end)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(ICON_SIZE, ICON_SIZE)
	b.icon:SetPoint("CENTER")
	b.icon:SetTexture(ICON)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetScript("OnClick", function()
		ns.Settings.OpenDefault() -- the settings at Order
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip_SetTitle(GameTooltip, L("AddonName") .. " settings")
		GameTooltip_AddNormalLine(GameTooltip, N("OrderSection") .. " and the other settings.")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	bagButton = b
	ns.Debug.BenchRefresh() -- put the status text in the bag from the start, if it's on
end

-- At login: take over the sort button and add the gear.
function SortButton.Setup()
	TakeOverSortButton()
	CreateBagButton()
end
