-- Bags: read the bags into a list of slots, grouped into zones.
-- Zone "main" = the backpack and every general bag, in on-screen order (verified in game: backpack
-- slot 1 is top-left, the last bag's last slot bottom-right). Every special bag is its own zone
-- with a rule for what it accepts: a reagent bag takes crafting reagents; a profession bag (herb,
-- mining, soul, ...) takes items whose family matches its own. On Forever the reagent bag slot can
-- hold a profession bag (an herb bag, say), so a bag's type is read from the bag itself, never
-- assumed from its slot.

local _, ns = ...
local Bags = {}
ns.Bags = Bags

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = Enum.BagIndex.Bag_4
local REAGENT_BAG = Enum.BagIndex.ReagentBag

local CONTAINER_CLASS = Enum.ItemClass and Enum.ItemClass.Container or 1
local REAGENT_SUBCLASS = Enum.ItemContainerSubclass and Enum.ItemContainerSubclass.Reagent or 11

-- What kind of bag is in this bag slot. Returns nil for an empty slot, else a description:
-- { zone = "main" } for a general bag, { zone, kind = "reagent" } for a reagent bag, or
-- { zone, kind = "family", family } for a profession bag. Blizzard's per-bag "Ignore cleanup"
-- setting is deliberately ignored: a bag that opts out works against the whole addon (the user's call).
function Bags.Describe(bag)
	if C_Container.GetContainerNumSlots(bag) == 0 then
		return nil
	end
	local subclass
	if bag ~= FIRST_BAG then
		local inv = C_Container.ContainerIDToInventoryID(bag)
		local bagItem = inv and GetInventoryItemID("player", inv)
		if bagItem then
			local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(bagItem)
			if classID == CONTAINER_CLASS then
				subclass = subclassID
			end
		end
	end
	if subclass == REAGENT_SUBCLASS then
		return { zone = "reagent", kind = "reagent", priority = 2 }
	end
	local _, family = C_Container.GetContainerNumFreeSlots(bag)
	if family and family ~= 0 then
		return { zone = "bag" .. bag, kind = "family", family = family, priority = 1 }
	end
	return { zone = "main" }
end

-- Does this item belong in a special bag of this description?
function Bags.Fits(item, info)
	if info.kind == "reagent" then
		return item.isCraftingReagent
	elseif info.kind == "family" then
		return bit.band(item.family or 0, info.family) ~= 0
	end
	return true
end

-- Items a special bag refused this session (in case Forever's rule differs from what the item data
-- says), keyed "zone:itemID". They stay where they are.
Bags.refused = {}

-- Kept out of special bags ("Keep ... in my normal bags" in the weight popup). People think in categories
-- ("my cloth"), so it works per subclass (all Cloth) as well as per item; either keeps an item out. Such
-- items are never moved into a special bag, and ones already in one are moved back out.
-- SedimentDB.keepOut = { items = { [itemID] = true }, subclasses = { ["classID:subclassID"] = true } }
local function KeepOutTable()
	local ko = SedimentDB.keepOut
	if not ko then
		return nil
	end
	if not ko.items then
		-- Converted from the first, per-item-only version: { [itemID] = true }.
		local items = {}
		for k, v in pairs(ko) do
			if type(k) == "number" then
				items[k] = v
			end
		end
		ko = { items = items, subclasses = {} }
		SedimentDB.keepOut = ko
	end
	ko.subclasses = ko.subclasses or {}
	return ko
end

function Bags.KeepOut(item)
	local ko = KeepOutTable()
	return ko ~= nil and (ko.items[item.itemID] == true or ko.subclasses[item.subKey] == true)
end

-- kind = "item" (key = itemID) or "subclass" (key = "classID:subclassID").
function Bags.KeepOutRule(kind, key)
	local ko = KeepOutTable()
	return ko ~= nil and ((kind == "item" and ko.items[key]) or (kind == "subclass" and ko.subclasses[key])) == true
end

function Bags.SetKeepOut(kind, key, on)
	local ko = KeepOutTable()
	if not ko then
		ko = { items = {}, subclasses = {} }
		SedimentDB.keepOut = ko
	end
	local t = kind == "item" and ko.items or ko.subclasses
	t[key] = on and true or nil
end

-- "Fill reagent and profession bags automatically" (Settings > Sorting; on unless switched off). Off: nothing
-- is moved into special bags; what's already in them stays and is still sorted there.
function Bags.FillSpecialBags()
	return SedimentDB.fillSpecialBags ~= false
end

-- Could this item ever go into a special bag (whatever bags the player has)? For showing the checkbox.
function Bags.SpecialBagItem(item)
	return item.isCraftingReagent or (item.family or 0) ~= 0
end

function Bags.ShouldTransfer(item, info)
	return Bags.FillSpecialBags() and not Bags.KeepOut(item) and Bags.Fits(item, info)
		and not Bags.refused[info.zone .. ":" .. item.itemID]
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
		local itemName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isCraftingReagent = C_Item.GetItemInfo(itemID)
		st.isCraftingReagent = isCraftingReagent or false
		st.family = C_Item.GetItemFamily(itemID) or 0
		-- Only keep it once the game actually knew the item; otherwise look again next time.
		if st.maxStack and itemName then
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
		isCraftingReagent = st.isCraftingReagent,
		family = st.family,
	}
	-- Two slots are interchangeable only if they hold the same item in the same bind state and the
	-- same equipment sets (sets remember the exact copy, so a set copy can't stand in for a spare).
	-- Never swap two slots with the same signature: the game would merge them instead.
	item.sig = item.link .. (item.isBound and "|B" or "|U") .. "|" .. item.equipmentSets
	return item
end

-- Every slot. Each entry: { bag, slot, zone, info, item = ReadSlot() or nil }, info being the bag's
-- description from Describe. Main-zone slots come first in on-screen order, then each special bag
-- (profession bags before the reagent bag). Also reports whether any slot is locked (mid-move).
function Bags.Read()
	local main, special, anyLocked = {}, {}, false
	local function AddBag(list, bag, info)
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local item = Bags.ReadSlot(bag, slot)
			if item and item.isLocked then
				anyLocked = true
			end
			list[#list + 1] = { bag = bag, slot = slot, zone = info.zone, info = info, item = item }
		end
	end
	local bagsInOrder = {}
	for bag = FIRST_BAG, LAST_BAG do
		bagsInOrder[#bagsInOrder + 1] = bag
	end
	if REAGENT_BAG then
		bagsInOrder[#bagsInOrder + 1] = REAGENT_BAG
	end
	local specialBags = {}
	for _, bag in ipairs(bagsInOrder) do
		local info = Bags.Describe(bag)
		if info and info.zone == "main" then
			AddBag(main, bag, info)
		elseif info then
			specialBags[#specialBags + 1] = { bag = bag, info = info }
		end
	end
	table.sort(specialBags, function(x, y)
		if x.info.priority ~= y.info.priority then
			return x.info.priority < y.info.priority
		end
		return x.bag < y.bag
	end)
	for _, sb in ipairs(specialBags) do
		AddBag(special, sb.bag, sb.info)
	end
	for _, s in ipairs(special) do
		main[#main + 1] = s
	end
	return main, anyLocked
end
