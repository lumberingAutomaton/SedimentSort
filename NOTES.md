# Sediment working notes

Design and open questions. This file is not part of the addon.

## Idea
Replace the Omnibag sort with our own. Every item has a weight. Items below the sink line float to the top of
the bags, items at or above it sink to the bottom, and the free space stays in the middle.

## Weight cascade (most specific wins, a level applies only if it has a weight)
1. Item weight (this exact item)
2. Flags, checked in order Equipment set > Quest > Gray > Unbound gear (equippable and not soulbound, i.e. BoE
   not yet bound). Equipment set added 2026-11-20 at the user's request; starter weight 35. Items in the same set
   sort together (set names are the first tie-break after weight).
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

## Auto-sort on loot (0.4.0, AutoSort.lua)
- Decided 2026-11-20: a full sort (not a cheap nudge), debounced, and never while the bags are open. The user's
  idea: "if the bag is open, don't sort unless I click the sort button". Changes while the bags are open are
  remembered; closing the bags sorts them.
- Any bag change triggers it (loot, crafting, using something up, selling), so closed bags are always in exact
  order. A first version only reacted to new item GUIDs, a leftover from the nudge design; the user pointed out
  it only delayed undoing manual moves, so it was removed.
- Also waits out: combat, cursor holding an item, vendor/bank/mail/trade/auction/guild bank windows, a sort in
  progress, 0.5s of bag quiet (a burst of looting gives one sort), and the first 2s after login.
- Auto sorts are quiet: chat only on errors.
- On by default (SedimentDB.autoSort). Right-click the bag sort button or /sed auto toggles; chat says the new
  state; the button is dimmed and desaturated while off; its tooltip shows the state.

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

## Ideas, not yet built
- Buff food flag (discussed 2026-11-20, user said "not quite yet"). Classic data files all food and drink under
  Consumable > Food & Drink. Buff food's tooltip says "well fed" ("If you spend at least 10 seconds eating you
  will become well fed and gain ..."). Plan: for Food & Drink items only, read C_TooltipInfo.GetItemByID(itemID)
  lines, look for "well fed" (case-insensitive), cache per itemID for the session. Make it a flag, so it beats
  the Food & Drink subclass weight. Suggested starter weight 9.5 (just after food at 9).
  Caveats: English text only; odd buff foods (e.g. Dragonbreath Chili) may not say "well fed" and need an item
  weight; Forever may word some foods differently, so show the flag in /sed scan and check against real food.
- Drink flag, same idea: C_Item.GetItemSpell(itemID) names the use spell "Food", "Drink" or "Refreshment".
  Also English names.

## Status (2026-11-20)
- 0.1.0: weight cascade with the starter preset, gravity sort, takeover of the bag sort button (left-click sorts,
  click again cancels), /sed why, /sed scan. Honors the per-bag "Ignore cleanup" setting. Skips special bags and
  the reagent bag.
- 0.2.0: Alt+right-click popup (Popup.lua), a post-hook on HandleModifiedItemClick. Shows the levels that apply
  to the item plus the sink line, all editable; blank = inherit; "Sort now" button; follows the item by item ID
  when a sort moves it. Two-round placement (below).
- 0.3.0: Equipment set flag.
- 0.4.0: auto-sort on loot (section above), right-click toggle, /sed auto, /sed auto? (what it's waiting for).
  Busy-window and bag checks use IsVisible: IsShown on SendMailFrame was true with the mailbox closed, which
  blocked auto-sort forever.
- 0.4.0 also: item pick-up/put-down sounds muted while a sort runs (Sound.lua, MuteSoundFile on the 36
  sound/interface/pickup files, IDs 567542-567577 from the community listfile). Verified on Forever with
  /sed mutetest. Mutes are reference-counted, and a sort releases its mute 1s after it stops: unmuting right at
  the stop let the last round's put-down sounds through.
- On login Sediment checks every module loaded and says so in chat if not (new .toc files can need a client
  restart).
- Not built yet: the settings panel (categories not in the bags, item weight list, preset reset).

### How the sort works
- Rounds: send every move that uses no slot twice (no cap: a round is at most half the slots), wait for the
  game to confirm, repeat. Phases: merge partial stacks, place items, then put partial stacks last in their
  group (drop the group's last bigger stack onto the partial one).
- Placement is always 2 rounds: the rearrangement splits into chains, and shifting a chain by one = reverse it,
  then reverse all but its first slot. Each reversal is disjoint swaps. No free slot needed. Direct pairs (two
  slots that each hold what the other wants) are matched first to keep chains short. The user had the same idea
  independently ("almost any move in 2 swaps").
- Every round re-reads the bags and checks them against the plan; a mismatch (loot, user moves) re-plans.
- dev/sim.lua runs the real sort against mocked APIs using a saved /sed scan, with slot locks modelled:
  `lua dev/sim.lua <SV file> [seed] [show]`. 200 shuffles: full sort 3-6 rounds (extra rounds are merges; the
  sim splits stacks on purpose); "last floater jumps to the top" and back: always 2 rounds.
- In game: 17 moves in 2 rounds = 0.7s; 13 moves in 3 rounds = 0.8s; no server errors.
- Still to check in game: does dropping a full stack onto a partial one top it up and leave the rest behind?

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
