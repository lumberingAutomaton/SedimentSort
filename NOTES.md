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
  progress, 2s of bag quiet (a burst of looting gives one sort; raised from 0.5s at the user's request so new
  quest items carry their quest flag by then), and the first 2s after login. QUEST_LOG_UPDATE also makes a sort
  pending, for quest flags that show up later still.
- The wait is adjustable with /sed delay <seconds> (SedimentDB.autoSortDelay, 0-30, default 2) so the user can
  find a good value; then make that the default.
- Auto sorts are quiet: chat only on errors.
- Streaming (the user's idea): button sorts send each round in one frame; auto-sorts stream the same rounds,
  spending on average at most a time budget per frame on swaps (/sed budget <ms>, SedimentDB.streamBudgetMs).
  Default 0.1ms, picked in game: 1ms still judders. Swaps cost ~5ms each (handlers, nearly all outside
  Sediment; planning is ~3-5ms per whole sort), so 0.1 = one swap every ~50 frames, ~4s for 11 swaps at
  144 FPS. To do: make the budget per second so duration doesn't depend on frame rate; finish in a burst if
  the bags open mid-stream; test swap cost with WoW Task Manager disabled (done: no meaningful change). Each swap fires events whose handlers (Blizzard + other addons) run in the same
  frame, so a whole round at once was a visible hitch: user saw 144 -> 124 fps ~2s after swapping equipment sets.
  The budget is measured around each swap, so it includes the other handlers' time.
- Per-item facts (class, names, stack size) are cached by item ID, and Weights.Resolve no longer builds the
  Explain tables (dev/resolve_check.lua checks they agree). Sorts report "our code: X ms"; /sed auto? shows the
  last sort's moves, rounds, frames and ms.
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

## To do (as of end of 2026-11-20)
In-game tests done:
- WoW Task Manager off: no meaningful change in swap cost. The ~5ms per swap isn't the profiler.
- Partial stacks: the partial ends up after the full stacks (restack assumption confirmed).

In-game tests left:
- Herb bag character (0.7.0 fix): sort; feathers and other non-herbs stay in the normal bags, no errors. Put an
  herb in the normal bags and sort: it moves into the herb bag.
- 0.7.0 GCD sweep: swap sets with bags closed, sweep + bling on the backpack button; open bags mid-sweep:
  sweep clears, nothing moves; close: it finishes. Button sort: quick sweep on the sort button.
- Loot a quest item: counts settle, item lands with quest items. Tune /sed delay, then make that the default.
- Alt+right-click a bank item opens the popup.
- Special bags left alone: put an item in a reagent/profession bag, mess up, sort; nothing moves in or out.
  /sed scan also prints "N items in M sortable slots": M should leave out the special bag's slots.
- Two identical items, one in a set (e.g. put one Patterned Bronze Bracers in a set): the set copy sorts with
  the set, the spares with the other gear. (A gray item in a set is a different, also useful test: it checks
  Equipment set beats Gray.)
- Combat mid-sort: swap sets with bags closed, wait ~2s for the sort to start (it streams for a few seconds),
  then attack a mob. Expect the chat line "stopped: entered combat", nothing on the cursor, no error popup.

Code left:
- Done 2026-11-21: Blizzard's per-bag "Ignore cleanup" setting is ignored (the user: antithetical to the addon).
  Bags.IsSortable no longer reads it; the user's Blizzard settings are left untouched.
- 0.6.0: reagent bag (verified in game 2026-11-21: silk moved out came back to its spot). The user noticed it "doesn't work very well anymore":
  Blizzard's sort used to move crafting reagents into it, and Sediment had replaced that sort. Now:
  merge (preferring reagent bag stacks as destination) -> transfer (reagents from normal bags into empty
  reagent bag slots, one round) -> placement planned per zone (a chain crossing zones could route a
  non-reagent through a reagent slot mid-sort) -> restack within a zone. Eligibility = isCraftingReagent
  (C_Item.GetItemInfo, 17th return). If the game refuses a transfer, the item goes back, is remembered for
  the session (Bags.notReagentBag), and the sort carries on. Sim covers a 24-slot bag and an overflowing 6-slot
  one, plus a flagged-but-refused item.
- Done 2026-11-21: combat. The streaming sender didn't re-check combat between swaps, so a stream running into
  a pull hit ADDON_ACTION_BLOCKED (user screenshot in Shadowfang Keep). Now every swap path checks
  InCombatLockdown, PLAYER_REGEN_DISABLED stops a running sort at once, and an interrupted auto-sort resumes
  after combat.
- Rule (user, 2026-11-21): bags closed, auto-sort moves things; bags open, ONLY the sort button does. Opening the
  bags mid-auto-sort pauses it on the spot; it re-plans and finishes once they close. (Replaced a same-day
  version that finished the sort in a burst when the bags opened: the user had a scroll jump twice under the
  cursor while trying to use it.)
  A spell waiting for a target doesn't matter with the bags closed (user, 2026-11-21): no check for it.
- 0.7.0 (uncommitted, untested in game): special bags by their own type. Bug found by the user: on another
  character the reagent bag slot holds an herb bag, and Sediment tried to put a feather (a crafting reagent)
  in it. A bag's type now comes from the bag item (container subclass 11 = reagent bag) and its family
  (GetContainerNumFreeSlots); a profession bag takes items whose C_Item.GetItemFamily matches, wherever it sits,
  so profession bags in the normal slots are sorted too (was parked). Profession bags fill before the reagent
  bag (an herb that's also a reagent goes to the herb bag). Refusals remembered per bag. Sim: big/small
  reagent bag, herb bag in the reagent slot, mining bag in a normal slot; 300 seeds pass.
- 0.7.0 also: progress sweep. A cooldown frame (GCD clock) over
  BagItemAutoSortButton and MainMenuBarBackpackButton runs for the estimated time left (Sort.EstimateSeconds:
  rounds x 0.3s server wait + streamed swaps x running-average swap cost / budget / FPS), re-aimed every
  round. Success ends it with the cooldown bling; interruptions clear it; sorts that move nothing never show it.
  Lives in Sediment.lua (no new file, so no client restart).
- Auto-sort speed slider (smoother <-> faster), per-second budget underneath. Waiting on the user.
- Settings panel (design in chat 2026-11-20): own window via /sed, Settings button in the popup, stub under
  Options > AddOns. Sections: Auto-sort (on/off, wait, speed slider, with explanations), General, Flags,
  Categories (inherited values in grey), Item weights (remove, drag to add), Reset to starter weights.
- Later/parked: ladder view tab; Buff food and Drink flags; category row
  breaks; neutral-buoyancy layer; splitting a swap's pick-up and put-down across frames; README.md.

## Open question: how to present the auto-sort budget (user is sleeping on it, 2026-11-20)
- Per-frame budget (current, 0.1ms/frame) vs per-second (~14ms/s, same as 0.1 at 144 FPS). Each swap costs a
  fixed ~5ms, so a slow frame is worse at high FPS (144: 6.9 -> ~12ms) than at low FPS (60: 16.7 -> ~22ms).
  Per-frame: slow frames every ~0.35s at 144 but every ~0.8s at 60, and the sort takes ~9s at 60.
  Per-second: slow frames every ~0.35s at any FPS, sort ~4s at any FPS; no FPS measuring needed (use the
  OnUpdate elapsed time). I recommended per-second; the user thinks that's right but wants a clearer way to
  think and talk about it for users before deciding.
- Presentation (user, 2026-11-20): one slider, the math stays behind the scenes. Left = slow and smooth,
  right = quick, with more stutter. No ms or FPS shown to the user.

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
