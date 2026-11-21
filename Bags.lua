-- Bags: read the general bags into a list of slots in on-screen order.
-- On-screen order (verified in game): backpack slot 1 is top-left, the last bag's last slot is bottom-right.

local _, ns = ...
local Bags = {}
ns.Bags = Bags

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = Enum.BagIndex.Bag_4

-- Sortable = a general bag (no profession or other special family) that the user hasn't set to
-- "Ignore cleanup" in the bag menu. Special bags and the reagent bag are left alone for now.
function Bags.IsSortable(bag)
	if C_Container.GetContainerNumSlots(bag) == 0 then
		return false
	end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	if family ~= 0 then
		return false
	end
	if bag == FIRST_BAG then
		return not C_Container.GetBackpackAutosortDisabled()
	end
	return not C_Container.GetBagSlotFlag(bag, Enum.BagSlotFlags.DisableAutoSort)
end

-- Facts about an item type that never change (class, names, stack size), looked up once per item
-- ID instead of on every read.
local static = {}

local function Static(itemID)
	local st = static[itemID]
	if not st then
		local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
		classID, subclassID = classID or -1, subclassID or -1
		st = {
			classID = classID,
			subclassID = subclassID,
			subKey = classID .. ":" .. subclassID,
			className = classID >= 0 and C_Item.GetItemClassInfo(classID) or nil,
			subclassName = classID >= 0 and subclassID >= 0 and C_Item.GetItemSubClassInfo(classID, subclassID) or nil,
			equipLoc = equipLoc,
			maxStack = C_Item.GetItemMaxStackSizeByID(itemID),
		}
		-- Only keep it once the game actually knew the item; otherwise look again next time.
		if st.maxStack then
			static[itemID] = st
		end
		st.maxStack = st.maxStack or 1
	end
	return st
end

-- Full description of one slot's item, or nil if the slot is empty.
function Bags.ReadSlot(bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info then
		return nil
	end
	local st = Static(info.itemID)
	local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
	local inSet, setList = C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
	local item = {
		bag = bag,
		slot = slot,
		itemID = info.itemID,
		name = info.itemName,
		link = info.hyperlink,
		count = info.stackCount,
		quality = info.quality,
		isBound = info.isBound,
		isLocked = info.isLocked,
		classID = st.classID,
		subclassID = st.subclassID,
		subKey = st.subKey,
		className = st.className,
		subclassName = st.subclassName,
		equipLoc = st.equipLoc,
		isQuestItem = quest and quest.isQuestItem or false,
		inEquipmentSet = inSet or false,
		equipmentSets = inSet and setList or "", -- comma-separated set names
		maxStack = st.maxStack,
	}
	-- Two slots are interchangeable only if they hold the same item in the same bind state and the
	-- same equipment sets (sets remember the exact copy, so a set copy can't stand in for a spare).
	-- Never swap two slots with the same signature: the game would merge them instead.
	item.sig = item.link .. (item.isBound and "|B" or "|U") .. "|" .. item.equipmentSets
	return item
end

-- Every sortable slot in on-screen order. Each entry: { bag, slot, item = ReadSlot() or nil }.
-- Also reports whether any slot is locked (an item mid-move).
function Bags.Read()
	local slots, anyLocked = {}, false
	for bag = FIRST_BAG, LAST_BAG do
		if Bags.IsSortable(bag) then
			for slot = 1, C_Container.GetContainerNumSlots(bag) do
				local item = Bags.ReadSlot(bag, slot)
				if item and item.isLocked then
					anyLocked = true
				end
				slots[#slots + 1] = { bag = bag, slot = slot, item = item }
			end
		end
	end
	return slots, anyLocked
end
