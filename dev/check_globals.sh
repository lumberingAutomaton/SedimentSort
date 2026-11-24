#!/bin/sh
# Fail if any addon file reads or writes a global that isn't a known WoW API, Lua library or
# Sediment's own. Catches "local declared below the function that uses it" bugs (twice so far:
# cpuMs in Sort.lua, lastBagUpdate in AutoSort.lua), which the sim misses for files it mocks.
# Usage: sh dev/check_globals.sh   (from the addon folder). Add new legitimate names to ALLOWED.
ALLOWED="_G bit date ipairs math pairs print select string table tonumber tostring type unpack
strtrim tinsert hooksecurefunc
C_Container C_Item C_Timer Enum CreateFrame UIParent UISpecialFrames GameTooltip
GameTooltip_AddBlankLineToTooltip GameTooltip_AddInstructionLine GameTooltip_AddNormalLine
GameTooltip_SetTitle GameTooltip_Hide HIGHLIGHT_FONT_COLOR SOUNDKIT PlaySound MuteSoundFile UnmuteSoundFile
BagItemAutoSortButton ContainerFrameCombinedBags BagItemSearchBox IsAnyBagOpen GetInventoryItemID
NUM_CONTAINER_FRAMES ContainerFrameContainer OpenAllBags
GetCursorInfo ClearCursor GetCursorPosition GetMouseButtonClicked GetMouseFoci GetMouseFocus
IsAltKeyDown IsControlKeyDown IsShiftKeyDown InCombatLockdown GetTime GetFramerate debugprofilestop
SlashCmdList SLASH_SEDIMENT1 SLASH_SEDIMENT2 SedimentDB
StaticPopupDialogs StaticPopup_Show YES NO"
status=0
for f in *.lua; do
	luac -p "$f" || { status=1; continue; }
	for name in $(luac -p -l "$f" | grep -E '(GET|SET)TABUP.*_ENV' | grep -oE '"[A-Za-z_][A-Za-z_0-9]*"' | tr -d '"' | sort -u); do
		case " $(echo $ALLOWED) " in
			*" $name "*) ;;
			*) echo "$f: unexpected global '$name'"; status=1 ;;
		esac
	done
done
[ $status -eq 0 ] && echo "globals OK"
exit $status
