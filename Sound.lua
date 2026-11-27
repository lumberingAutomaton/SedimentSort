-- Sound: silence the item pick-up and put-down sounds while a sort runs.
--
-- Every swap plays the item's pick-up and put-down sound, so a sort round is a burst of clinks.
-- MuteSoundFile silences specific sound files; we mute just these for the length of the sort and
-- unmute them when it stops, however it stops. Mutes aren't saved, so a crash mid-sort is undone
-- by /reload. The sort button still plays Blizzard's single "bag sorting" sound when clicked.
--
-- File IDs from the community listfile (github.com/wowdev/wow-listfile), sound/interface/pickup/.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Sound.lua"] = true -- see ns.FILES (Sediment.lua) and the Files section
local Sound = {}
ns.Sound = Sound

local ITEM_SOUNDS = {
	567542, -- pickupring.ogg
	567543, -- pickupbag.ogg
	567544, -- pickupwand.ogg
	567545, -- pickupbook.ogg
	567546, -- pickupfoodgeneric.ogg
	567547, -- putdownmeat.ogg
	567548, -- putdownbook.ogg
	567549, -- putdownwand.ogg
	567550, -- pickuplargechain.ogg
	567551, -- putdownring.ogg
	567552, -- pickupherb.ogg
	567553, -- putdownherb.ogg
	567554, -- pickupmetallarge.ogg
	567555, -- pickupwater_liquid01.ogg
	567556, -- putdownparchment_paper.ogg
	567557, -- putdownwater_liquid01.ogg
	567558, -- pickupwoodlarge.ogg
	567559, -- putdownbag.ogg
	567560, -- pickupmetalsmall.ogg
	567561, -- pickupsmallchain.ogg
	567562, -- pickupparchment_paper.ogg
	567563, -- putdownsmallmetal.ogg
	567564, -- pickuprocks_ore01.ogg
	567565, -- pickupcloth_leather01.ogg
	567566, -- putdownwoodsmall.ogg
	567567, -- putdownwoodlarge.ogg
	567568, -- pickupgems.ogg
	567569, -- putdownlargemetal.ogg
	567570, -- putdownfoodgeneric.ogg
	567571, -- putdowncloth_leather01.ogg
	567572, -- putdownlargechain.ogg
	567573, -- pickupmeat.ogg
	567574, -- putdowngems.ogg
	567575, -- putdownrocks_ore01.ogg
	567576, -- pickupwoodsmall.ogg
	567577, -- putdownsmallchain.ogg
}

-- Mutes are counted: a sort and the Tools section's Mute test can overlap, and the sounds only come back once
-- nobody wants them muted.
local holds = 0

local function Apply(mute)
	local f = mute and MuteSoundFile or UnmuteSoundFile
	if not f then
		return
	end
	for _, id in ipairs(ITEM_SOUNDS) do
		f(id)
	end
end

local function Hold()
	holds = holds + 1
	if holds == 1 then
		Apply(true)
	end
end

local function Release()
	if holds == 0 then
		return
	end
	holds = holds - 1
	if holds == 0 then
		Apply(false)
	end
end

-- The last round's put-down sounds can play a moment after the server confirms the move, so a
-- sort keeps its mute for a little after it stops.
local UNMUTE_DELAY = 1

local sortHeld = false

function Sound.MuteItemSounds()
	if sortHeld then
		return
	end
	sortHeld = true
	Hold()
end

function Sound.UnmuteItemSounds()
	if not sortHeld then
		return
	end
	sortHeld = false
	C_Timer.After(UNMUTE_DELAY, Release)
end

-- Tools > Mute test (debug addon): mute the item sounds for 15 seconds so the user can move items by hand and hear
-- whether the mute takes. Separates "no MuteSoundFile" from "Forever uses other sound files".
function Sound.Test()
	if not MuteSoundFile then
		ns.Print("MuteSoundFile doesn't exist on this client, so the item sounds can't be muted this way.")
		return
	end
	Hold()
	ns.Print(("muted %d item sounds for 15s. Move some items by hand: do they still clink?"):format(#ITEM_SOUNDS))
	C_Timer.After(15, function()
		Release()
		ns.Print("mute test over.")
	end)
end
