-- Core: start-up, the load check, events, and /dim (the only command: it opens the settings; user,
-- 2026-11-26). Everything else lives in its feature's file (see ns.FILES).

local ADDON, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Core.lua"] = true -- see ns.FILES below and the Files section
local N, L = ns.Noun, ns.L -- nouns in its colour, plain words (see Text.lua)

function ns.Print(msg)
	print("|cffc8a96e" .. ns.L("AddonName") .. ":|r " .. msg)
end
local Print = ns.Print

-- Every file the addon expects, in .toc order. Each marks itself in ns.loadedFiles as it loads; the login
-- check and the Debug > Files section compare the two (dev/files_check.lua keeps this list equal to the .toc).
ns.FILES = { "Text.lua", "Rules.lua", "Bags.lua", "Sound.lua", "Sort.lua", "AutoSort.lua", "Settings.lua",
	"Overlays.lua", "Popup.lua", "Ordering.lua", "Options.lua", "History.lua", "Debug.lua", "SortButton.lua",
	"Core.lua" }
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

SLASH_DISORDERITEMMANAGER1 = "/dim"
SlashCmdList.DISORDERITEMMANAGER = function()
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
		DisorderItemManagerDB = DisorderItemManagerDB or {}
		DisorderItemManagerDB.lastMove = nil -- left over from the 0.0.1 probe
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
		ns.SortButton.Setup()
		ns.Popup.Hook()
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
		if ns.Overlays.Active() then
			ns.Overlays.Refresh()
		end
		ns.Order.OnBagUpdate()
	end
end)
