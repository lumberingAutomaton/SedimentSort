# Sediment working notes

Design and open questions. This file is not part of the addon.

## Idea
Replace the Omnibag sort with our own. Every item has a weight. Items below the sink line float to the top of
the bags, items at or above it sink to the bottom, and the free space stays in the middle.

## Weight cascade (most specific wins, a level applies only if it has a weight)
1. Item weight (this exact item)
2. Flags, checked in order Quest > Gray > Unbound gear (equippable and not soulbound, i.e. BoE not yet bound)
3. Subclass (Consumable > Potion)
4. Class (Consumable)
5. Default

- Trash = gray quality. NOT the Miscellaneous > Junk subclass: classic data files normal items there.
- Ties: category, then item ID, then bigger stack first.
- Weights are account-wide.
- No pins in v1. Weight 0 works as a pin for the top slots.

## Sort
- Client-side: plan the target layout, then move items one at a time, waiting for each move to settle.
  Pause in combat, and when the cursor is holding an item.
- Merge partial stacks first.
- Special bags (reagent, profession) sorted separately, outside the gravity layout.
- Take over BagItemAutoSortButton's OnClick and the "Clean Up Bags" menu entry.
  Never overwrite C_Container.SortBags: that taints.

## Auto-place on loot
- On by default.
- Cheap version: a new item goes to the correct side of the gap, or next to copies of itself.
  The sort button does the full exact sort.
- Tell loot from the user's own moves by item GUID. Only place items that newly arrived.
- Hold off while: cursor is holding something, in combat, vendor/bank/mail/trade/AH open.
- Toggle: right-click our sort button, plus a settings checkbox. Print the new state on every flip.
  The button looks different while auto-place is off.

## Editing weights
- Alt+right-click an item: popup showing the cascade, which rule won, and editable boxes for each level.
  Blank = inherit.
- Settings panel: class/subclass tree, flags, list of item weights, default, sink line, starter preset.
- Optional tooltip line "Weight 8 · Potion", off by default.

## Open
- Category row breaks: option, off by default?
- Starter weights: draft in chat 2026-11-20 (tools as item weights, Consumable 10, Trade Goods 30, Quest 51, Gray 100).
- Parked: neutral-buoyancy middle layer (a weight band held mid-gap). v1 keeps two layers.
- Decided 2026-11-20: "Unbound gear" flag so BoE gear sorts apart from bound gear. Bound gear falls through to its
  class weight. The user will give item weights to anything that shouldn't be in the BoE group (tools like
  Rock Chipper are unbound weapons).

## Status: 0.1.0 (2026-11-20)
- Built: weight cascade with the starter preset, gravity sort, takeover of the bag sort button, /sed why, /sed scan.
- Sort runs in rounds: re-read the bags, send every move that uses no slot twice (up to MAX_BATCH = 40), wait
  for the game to confirm, repeat. Phases, one per round: merge partial stacks, place items, then put partial
  stacks last in their group (drop the group's last bigger stack onto the partial one).
- Sim (with slot locks modelled): your scan, shuffled, sorts in 4-10 rounds, usually 6-7. It was 55+ waits
  when moves went one at a time.
- Honors the per-bag "Ignore cleanup" setting in the bag menu. Skips special bags and the reagent bag.
- dev/sim.lua runs the real sort against mocked APIs using a saved /sed scan: `lua dev/sim.lua <SV file> [seed]`.
- Not built yet: weight editing UI, auto-place on loot, right-click toggle.
- In game 2026-11-20: 17 moves in 2 rounds, 0.7s, no errors. Still to check: does dropping a full stack onto a partial one top it up and leave the rest behind? How long
  does a full sort take? Does the server accept 40 moves in one go, or does it reject some ("item is busy")?

## Probe checks (0.0.1)
- [x] /sed movetest: addon item moves work ("move OK", 2026-11-20).
- [x] Combined view: backpack slot 1 = top-left, last bag's last slot = bottom-right (confirmed in game 2026-11-20).
- [x] /sed scan (2026-11-20, mid-crafting so not a typical spread):
  - Hearthstone: Miscellaneous > Junk, white, bound. Cozy Sleeping Bag and Night Watchman's Torch are there too
    (blue and green). Confirms Misc > Junk is not trash.
  - Profession tools land in Weapon: Blacksmith Hammer = Weapon > Miscellaneous, Fishing Pole = Weapon > Fishing
    Pole, Rock Chipper (mining pick) = Weapon > Two-Handed Axes. Flint and Tinder = Trade Goods > Other.
    Class or subclass weights can't separate them from gear; they need item weights.
  - Memories of Valor is gray but bound: the gray flag would sink it as trash. Needs an item weight if kept.
  - Quest items are class Quest and carry the quest flag.
  - Consumable subclasses seen: Food & Drink, Potions, Other, Permanent (shield spike).
