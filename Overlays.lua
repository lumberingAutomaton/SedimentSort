-- Overlays: Select Mode and the bag outlines.

local _, ns = ...
ns.loadedFiles = ns.loadedFiles or {}
ns.loadedFiles["Overlays.lua"] = true -- see ns.FILES (Core.lua) and the Files section
local Overlays = {}
ns.Overlays = Overlays
local Print = function(msg) ns.Print(msg) end

-- Order turns it on while its list shows: every bag slot gets a light highlight; clicking an item adds its
-- row (Order's handler), hovering one lights up the row that sorts it. Alt+right-click still opens the weight
-- popup. The clicks land on Sediment's own catcher frames laid over the slots (children of the item buttons,
-- so they move and hide with them); Blizzard's item buttons are never changed, so nothing is tainted. While
-- it's on, a plain click can't use or pick up an item. Turning it on opens the bags; ending it leaves them
-- open. It ends with the settings window, the Order section, or combat.
--
-- Highlights (Order): while on, slots whose item has no rule of its own get an orange outline, and the items
-- of the selected row a gold one. Plain textures on a frame that takes no clicks, so the bag works as usual
-- underneath.

local selecting = false
local selectHandler, selectHover = nil, nil -- set by Order; no handler = open the weight popup
local highlighting, highlightFocus = false, nil
local hookedFrames = {}

-- Every bag window: the combined backpack, the numbered ones, and anything else in Blizzard's own list
-- (the reagent bag's window among them), without duplicates.
local function ContainerFrames()
	local list, seen = {}, {}
	local function Add(f)
		if f and not seen[f] then
			seen[f] = true
			list[#list + 1] = f
		end
	end
	Add(ContainerFrameCombinedBags)
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		Add(_G["ContainerFrame" .. i])
	end
	if ContainerFrameContainer and ContainerFrameContainer.ContainerFrames then
		for _, f in ipairs(ContainerFrameContainer.ContainerFrames) do
			Add(f)
		end
	end
	return list
end
Overlays.ContainerFrames = ContainerFrames -- also the debug addon's red overlay on locked items

local function Catcher(button)
	local c = button.DisorderSelect
	if c then
		return c
	end
	c = CreateFrame("Button", nil, button)
	c:SetAllPoints(button)
	c:SetFrameLevel(button:GetFrameLevel() + 10)
	c:RegisterForClicks("AnyUp")
	c.glow = c:CreateTexture(nil, "OVERLAY")
	c.glow:SetAllPoints()
	c.glow:SetColorTexture(0.3, 0.7, 1, 0.16)
	c:SetScript("OnClick", function(self, button)
		local b = self:GetParent()
		-- Alt+right-click still opens the weight popup, as it does outside Select Mode.
		if selectHandler and not (button == "RightButton" and IsAltKeyDown()) then
			selectHandler(b:GetBagID(), b:GetID())
		else
			ns.Popup.Open(b:GetBagID(), b:GetID())
		end
	end)
	c:SetScript("OnEnter", function(self)
		local b = self:GetParent()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(b:GetBagID(), b:GetID())
		GameTooltip:Show()
		if selectHover then
			selectHover(b:GetBagID(), b:GetID()) -- Order: light up the row that sorts it
		end
	end)
	c:SetScript("OnLeave", function()
		GameTooltip_Hide()
		if selectHover then
			selectHover(nil)
		end
	end)
	button.DisorderSelect = c
	return c
end

local UNRULED_EDGE, UNRULED_TINT = { 1, 0.5, 0.1, 0.95 }, { 1, 0.5, 0.1, 0.12 }
local FOCUS_EDGE, FOCUS_TINT = { 1, 0.85, 0.15, 1 }, { 1, 0.85, 0.15, 0.3 }

-- The highlight on one slot: a tint and a 2px outline, under the select catcher, taking no clicks.
local function Marker(button)
	local m = button.DisorderMark
	if m then
		return m
	end
	m = CreateFrame("Frame", nil, button)
	m:SetAllPoints(button)
	m:SetFrameLevel(button:GetFrameLevel() + 5)
	m.tint = m:CreateTexture(nil, "OVERLAY")
	m.tint:SetAllPoints()
	m.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = m:CreateTexture(nil, "OVERLAY", nil, 1)
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT")
			t:SetPoint(side .. "RIGHT")
			t:SetHeight(2)
		else
			t:SetPoint("TOP" .. side)
			t:SetPoint("BOTTOM" .. side)
			t:SetWidth(2)
		end
		m.edges[#m.edges + 1] = t
	end
	function m.Style(edge, tint)
		m.tint:SetColorTexture(tint[1], tint[2], tint[3], tint[4])
		for _, t in ipairs(m.edges) do
			t:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
		end
	end
	button.DisorderMark = m
	return m
end

function Overlays.Refresh()
	for _, f in ipairs(ContainerFrames()) do
		if f.EnumerateValidItems then
			if (selecting or highlighting) and not hookedFrames[f] and f.UpdateItems then
				-- Bag windows rebuild their buttons as they open and change; follow along.
				hooksecurefunc(f, "UpdateItems", Overlays.Refresh)
				hookedFrames[f] = true
			end
			-- Every bag window, the reagent bag's included. A window's slot list can run past the buttons
			-- it has (a closed window keeps its old size), so skip empty entries rather than stop: an
			-- error here used to end the loop before it reached the reagent bag.
			for _, b in f:EnumerateValidItems() do
				local c = b and b.DisorderSelect
				local m = b and b.DisorderMark
				local item = b and (selecting or highlighting) and f:IsShown() and b.GetBagID
					and ns.Bags.ReadSlot(b:GetBagID(), b:GetID())
				if item and selecting then
					c = Catcher(b) -- no numbers on the slots (user, 2026-11-25: Order replaced them)
					c:Show()
				elseif c then
					c:Hide()
				end
				local focus = item and highlighting and highlightFocus and highlightFocus(item)
				local unruled = item and highlighting and not ns.Weights.HasOwnRule(item)
				if focus or unruled then
					m = Marker(b)
					if focus then
						m.Style(FOCUS_EDGE, FOCUS_TINT)
					else
						m.Style(UNRULED_EDGE, UNRULED_TINT)
					end
					m:Show()
				elseif m then
					m:Hide()
				end
			end
		end
	end
end

function Overlays.IsSelecting()
	return selecting
end

-- Are any overlays on the bag slots (select mode or highlights)? They follow bag changes.
function Overlays.Active()
	return selecting or highlighting
end

-- Highlights for the setup questions. focus(item) -> true for the items the current question is about.
function Overlays.SetHighlight(on, focus)
	highlighting = on and true or false
	highlightFocus = highlighting and focus or nil
	Overlays.Refresh()
end

-- handler(bag, slot): a click on a bag item (Order adds its row); without one a click opens the weight
-- popup. hover(bag, slot) as the mouse enters an item, hover(nil) as it leaves.
function Overlays.SetSelectMode(on, handler, hover)
	if on and InCombatLockdown() then
		Print("not in combat.")
		on = false
	end
	local was = selecting
	selecting = on and true or false
	selectHandler = selecting and handler or nil
	selectHover = selecting and hover or nil
	Overlays.Refresh() -- hooks the bag windows first, so opening them below refreshes the overlays
	-- Starting select mode opens the bags (no change if they're open). Ending it leaves them as they are
	-- (user: turning select mode off shouldn't close the bags).
	if selecting and not was then
		OpenAllBags()
		C_Timer.After(0, Overlays.Refresh)
	end
end

