-- Text: every word for one of Sediment's own things, and every button label, in one place.
--
-- Keys name a role, never the current word (SaveInUse, not "Active"), so changing a word is one edit here
-- and nothing else: the buttons and the sentences that mention them follow. (User, 2026-11-25; keys that
-- spelled their word got renamed along with it, which touched other files.) dev/text_check.lua checks that
-- every key the code uses is here, since a missing one would quietly show the key itself.
--
-- Style: in sentences, nouns are sand (Sediment's colour, the chat prefix's) and button names gold (like a
-- button's own text); no quotation marks. Titles, headings and the buttons themselves use L (plain). WoW text
-- can't be bold, hence colours. This file loads first.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Text.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section

ns.TEXT = {
	-- Nouns: Sediment's own things.
	AddonName = "Sediment",
	SortValue = "Weight",          -- an item's or group's number: lighter floats, heavier sinks
	SortValues = "Weights",        -- plural; also the settings section
	PickMode = "Select Mode",      -- clicking bag items to see or change them
	Onboarding = "Setup",          -- the questions
	SavedRules = "History",        -- the list of saves, and its section
	KeptSave = "Pinned",           -- a save that stays at the top and is never dropped
	LootGap = "Empty Space",       -- the gap where new loot lands; its number is the old "sink line" (user, 2026-11-25)
	SaveInUse = "Active",          -- the save holding the rules in use
	SaveBefore = "Previous",       -- the newest save that isn't the rules in use: what you'd roll back to
	EntryCreated = "Created",      -- a History entry made when Setup is done
	EntrySnapshot = "Snapshot",    -- a History entry made automatically

	-- Buttons.
	ClearAllButton = "Start Fresh",
	ResumeButton = "Continue",
	OpenSettingsButton = "Settings",
	LeaveSetupButton = "Finish Later",
	PrevQuestionButton = "Back",
	SkipQuestionButton = "Skip",
	FinishSetupButton = "Done",
	RowUpButton = "Move Up",
	RowDownButton = "Move Down",
	SplitGroupButton = "Split This Up",
	LoadSaveButton = "Load",
	KeepSaveButton = "Pin",
	UnkeepSaveButton = "Unpin",
	UndoButton = "Undo",
	SortNowButton = "Sort Now",
	OpenBagsFinish = "Finish Now", -- if the bags open mid auto-sort
	OpenBagsPause = "Pause",
	OrderExact = "Full",           -- auto-sort order choices
	OrderMinimal = "Partial",

	-- The rule that keeps items out of reagent and profession bags.
	KeepOutRule = "Keep out of special bags",
	KeepOutList = "Kept out of special bags",
}

-- L: the word, plain. Noun / Btn: a noun or a button name in a sentence, coloured.
function ns.L(key)
	return ns.TEXT[key] or key
end

function ns.Noun(key)
	return "|cffc8a96e" .. ns.L(key) .. "|r"
end

function ns.Btn(key)
	return "|cffffd100" .. ns.L(key) .. "|r"
end
