# Sediment working notes

Design and open questions. This file is not part of the addon.

## How it works now (0.13.0)
User-facing overview: README.md. This section is the developer's view; history is in the version log below.

- **Weights** (Weights.lua): most specific rule with a weight wins: item > flags (Equipment set > Quest > Gray >
  BoE gear, stored as unboundGear: equippable and not soulbound) > subclass > class > default. Gray quality is
  trash (not Miscellaneous > Junk: classic data files normal items there). Account-wide, in
  SedimentDB.weights; the default (DEFAULTS in Weights.lua) is no rules, so ties fall back to the full order and
  it starts out as a by-type sort. One backup (SedimentDB.rulesBackup) before rules are replaced; restore swaps. Resolve is a table-free version of Explain.
- **Layout**: below the sink line packs from the top, at or above it from the bottom, gap in the middle.
  Full order (button): weight, equipment set names, class, subclass, item ID, bigger stack first. Partial
  order (auto-sort default): weight, then groups of identical items in their current order, with whole
  groups rotated between band ends when a band shifts (BestBands). Identical stacks stay together; the
  partial stack goes last. An item's identity (sig) = link + bound + equipment sets.
- **Zones** (Bags.lua): normal bags in on-screen order (backpack slot 1 top-left), then each special bag,
  identified by the bag item (container subclass 11 = reagent) or its family. Profession bags fill before the
  reagent bag. Blizzard's per-bag "Ignore cleanup" flag is ignored.
- **Sort engine** (Sort.lua): phases merge -> evict kept-out items -> transfer into special bags -> placement (per zone; every chain in
  two rounds by double reversal) -> restack. Every round re-reads the bags and checks them against the plan.
  Combat is checked before every swap and stops a sort at once. Button sorts send a round in one frame;
  auto-sorts stream it at an average budget per frame (default 0.3ms). Takes over BagItemAutoSortButton's
  click; never replaces C_Container.SortBags (taint).
- **Auto-sort** (AutoSort.lua): any bag change or quest-log update makes a sort pending. It waits for: bags
  closed, no combat, empty cursor, no vendor/bank/mail/trade/auction/guild bank window, 1.1s of bag quiet,
  2s after login. Bags opening mid-sort: pause (default; the plan is kept) or finish now (SedimentDB.openBags).
  Quiet in chat; item sounds muted during sorts (Sound.lua); the gliding sweep shows progress.
- **UI**: sort button (left: sort, right: toggle auto-sort); a gear next to it opens Settings (Settings.lua):
  a section list like WoW's Options window: Weights (Select mode, ladder, reset), Sorting (auto-sort
  options, Debug mode), Special bags (bags, fill switch, keep-out rules), and in debug mode Testing
  (seeded scrambles, status text, recent sorts) and Commands (ns.COMMANDS / ns.SHORTCUTS in Sediment.lua, also
  /sed help). A welcome screen shows on opening until dismissed; ? brings it back. Alt+right-click popup
  (Popup.lua). Every Sediment window closes and Select mode ends in combat.

## To do (updated 2026-11-24)
In-game tests left: none.

Code left:
- Onboarding (see "Planned: onboarding questionnaire" below), agreed 2026-11-24, in this order:
  1. Done (0.16.0): "Reset to default"; empty default rules; Full order for new installs.
  2. Done (0.16.0): automatic backup before rules are replaced, if there are any; "Restore previous rules".
  3. The questionnaire, whose first page replaces the welcome screen; it walks through getting the bag right
     with what's in it now. While it runs, bag slots with no rule of their own ("no sort for this") are
     highlighted, so progress is visible as answers cover them.
- Settings window extras: Options > AddOns entry; drag items onto the ladder to add them; a full category
  browser (today "Not set" only lists categories in the bags).

Ideas / parked (decided not now):
- Rules export and import (user, 2026-11-24): copy all rules (weights, flags, keep-out, sink line, default) as a
  text string to share or back up; paste a string to load one. Pairs with weight versions: an export string is
  a snapshot. Questions: replace vs merge on import; include settings (auto-sort options) or rules only.
- Sort demo on the welcome screen (user, 2026-11-24, optional): snapshot the bags, sort them to a sample set of
  weights so a new user sees it work, with Undo restoring the snapshot.
- Reverse (user, 2026-11-24): flip the whole layout so light items (hearthstone, "good stuff") pack from the
  bottom and heavy from the top, gap still in the middle. Implementation: reverse the on-screen slot order in
  Bags.Read (all zones); everything else unchanged. Open questions: a Sorting-tab checkbox and/or
  Shift+click on the sort button to flip and sort at once.
- Per-account vs per-character settings (user, 2026-11-24): today everything is account-wide (SedimentDB).
  Candidates for per-character: reverse, maybe auto-sort options. Weights stay account-wide.
- Highlight items with no weight of their own / using the default weight (user, 2026-11-24), e.g. a marker
  on those bag slots, so missing weights are visible in the bag itself (the ladder's "Not set" lists them).
- Weight versions (user, 2026-11-24: "would love it, not critical"): keep snapshots of the weights (e.g. before
  a reset, and on each session or on demand), with a way to restore one. A reset already asks to confirm.
- Ranking instead of numbers (rungs, sink line as a divider); the ladder is laid out to become that.
- Buff food and Drink flags; category row breaks; neutral-buoyancy layer.
- Never-worse partial order; improved target-choice planner (~10% fewer swaps, not noticeable); exact
  matching (2.3%); splitting pick-up/put-down across frames (per-swap cost isn't noticeable).
- An exact 99th-percentile frame time in the bench (worst frame already bounds it).

Done in game: settings rework, select mode incl. the reagent bag, windows closing in combat (2026-11-24;
the combat close had been cut short by the same select-mode error); editing safety (2026-11-24); gliding sweep and combat mid-sort (2026-11-24); dropped the identical-copy-in-a-set test (the
set flag is read per slot from the game and is part of an item's identity, so it can't land on the wrong copy); herb bag character (2026-11-24); quest items with a 1.1s delay, now the default (was 2s;
checks run every 0.25s, so 1.1 waits 1.1-1.35s); Alt+right-click on bank items; Task Manager off (no change); partial stacks last; GCD sweep (first version); bags-open pause;
pause keeps the plan (cloak); reagent bag (silk); test bench; partial order (ring case); settings window.

## Planned: onboarding questionnaire and empty starter rules (designed 2026-11-24, not built)
Why: first real user feedback (2026-11-24): onboarding was hard (didn't use "Set weights", didn't realize OK did
anything), the default weights were bad (they carried the developer's opinions, e.g. hearthstone on top, and a
weight for a Blacksmith Hammer the user didn't have), and they wanted to keep items out of the reagent bag.

Decisions (user, 2026-11-24):
- **Start with no rules.** Tied items fall back to the full order (class > subclass > item), so with no rules
  Sediment behaves like an ordinary by-type bag sort; weights add preferences on top. The starter set (and
  "Reset to starter weights") becomes empty; existing users' saved weights are untouched.
- **New installs default auto-sort to the Full order.** With no rules everything ties, and Partial keeps tied
  items where they are, so a new user's bag would never get organized. Partial stays as the option for people
  with weights.
- **A questionnaire instead of a wall of text**, with Back on every step and Skip on every question.

The questionnaire:
1. Layout first: "Where do you want your empty space?" Middle (Sediment's float/sink split; sink line 50),
   bottom (everything packed from the top, like a normal sort; sink line >= 100) or top (everything packed
   from the bottom; sink line <= 0). This is the "sink line at 0 or 100" case, in plain words. Later
   questions say "float/sink" in the middle layout and "near the start/end" in the packed ones.
2. Fixed questions, each sorting live (button speed; the bags are open):
   - Hearthstone: first or last?
   - Anything you want next to your hearthstone? Select mode opens; click items; OK sorts.
   - Gray junk: float or sink?
   - Trade goods: float or sink?
3. Special cases, only if the player has such items: Equipment set items (keep together, near the top?),
   BoE gear (float or sink?), spare bags/containers (float or sink?), Quest items.
4. N more questions generated from the item classes actually in the bags, ordered by how many items each
   covers (so the first answers sort most of the bag). "Split this up" on big classes asks per subclass
   (e.g. Consumables -> Potions / Food & Drink / Bandages). The remaining questions are the "Not set" list.
5. Review: the resulting stack top to bottom, with up/down arrows to reorder and the sink line between the
   halves. This is where "ranking instead of numbers" lands: answers assign rungs, the review orders them,
   numbers stay hidden.
- Progress ("4 of 9"), Skip, Back (undoes that step's rules and re-sorts), "Finish later" (remembers the
  step). Re-runnable from the ? / welcome later; answers only overwrite the rules they're about.
- Pitch (draft): "Your bags, always in your order. Sediment keeps your bags sorted all the time, quietly,
  while they're closed. You decide the order: what floats to the top, what sinks to the bottom, and what
  sticks together. New loot lands in the gap between, so you always see what's new. Start broad ('trade goods
  sink') and add exceptions ('but keep my fishing pole up top'): the most specific rule wins."

Separately (same feedback): **keep items out of special bags.** A "Keep in my normal bags" checkbox in the
weight popup (per item, maybe per category); such items are never transferred into a special bag, and ones
already there are moved back out (a new phase: today nothing leaves a special bag). Maybe also a switch to turn
reagent-bag filling off entirely.

Order to build (proposed): keep-out-of-special-bags -> empty starter rules + Full default for new installs ->
questionnaire.

## Matching vs the proven minimum (2026-11-24)
External review (pasted by the user): PlanPlacement matches identical items/empties greedily (fixed points,
direct pairs, then slot order), which can make fewer, longer chains; swaps = misplaced - chains, so it can
use more swaps than needed for the same target. Its example (B C A B C D -> D B C A B C: 5 swaps vs 4) is
correct. Measured with dev/min_swaps.lua (exhaustive max-cycle search, checked against brute force; run
`SEDIMENT_MEASURE=1 lua dev/sim.lua <SV> <seed> bench`), everyday bench events, 20 seeds:
- auto-sort (partial): 21290 swaps vs proven minimum 20821 = 2.3% extra; 90% of plans already optimal;
  worst plan +2 swaps.
- full order: 1.3% extra; 14% of plans above minimum; worst +2.
Decision (user): not worth acting on.

## Target choice vs better layouts (2026-11-24, same bench, SEDIMENT_MEASURE=1)
For each plan: min swaps to the partial order's layout vs the best layout a local search finds (move any
whole group anywhere in its band, keep changes that lower the proven count), and a floor (contents outside
their band region must move; one swap moves at most two). 20 seeds:
| event       | ours  | best found | floor | found vs ours |
| loot + use  | 3055  | 2637       | 1815  | -13.7%        |
| use 3       | 9222  | 8145       | 5539  | -11.7%        |
| weight edit | 1121  | 1011       | 829   | -9.8%         |
| set swap    | 1570  | 1479       | 1134  | -5.8%         |
| loot 3      | 5853  | 5515       | 3796  | -5.8%         |
| all         | 20821 | 18787      | 13113 | -9.8%         |
Headroom of at least ~10% in target choice (the floor is loose). Reviewer suggested a candidate planner behind
a switch. Decision (user, 2026-11-24): not worth it: ~one swap saved every 3-4 loot events, and a swap's
5-10ms on one frame isn't noticeable. If revisited: score candidates with PlanPlacement's own swap count (not
the exponential solver), hard time budget with the current choice as fallback, a "Partial+" bench toggle for
in-game A/B, test on fresh seeds and a second character's bags. Splitting pick-up/put-down across frames is
parked for the same reason (per-swap cost isn't noticeable).

## Version log
- 0.16.0: onboarding groundwork. The default rule set is empty (it shipped the developer's opinions; the first
  outside tester found them unhelpful): with no rules, ties fall back to the full order, so it starts as a
  by-type sort. New installs (no saved rules) also start on the Full auto-sort order and at the current rules
  version (WEIGHTS_VERSION 3), so old migrations don't add anything; existing saves keep their rules and order.
  "Reset to starter weights" -> "Reset to default" (also clears keep-out rules). Weights.Backup keeps one copy
  of the rules (weights + keep-out) before a wholesale change, only if there are rules; "Restore previous
  rules" (shown while a backup exists) swaps it back in, so it can be undone, except that an empty rule set
  isn't kept as a backup (found in game: after reset + restore, the button offered to restore "no rules"). dev/rules_check.lua tests the
  lifecycle; the sim uses the old starter rules as a fixture.
- 0.15.0: Special bags tab (user's call: its own tab, not the Sorting tab nor ladder rows; the ladder only lists
  weighted rules, so Cloth usually has no row there). Shows the special bags the player has (Bags.SpecialBags),
  the "Fill reagent and profession bags automatically" switch (moved from Sorting) and every keep-out rule
  (Bags.KeepOutRules: categories first) with x; removal greys the row with Undo, no re-sort under the mouse;
  the list rebuilds when the section shows or a rule is added from the popup. The tab row is replaced by a
  section list on the left like WoW's Options window (user: tabs would run out of space as it grows): grouped
  entries (Sediment; Debug only in debug mode), the selected one highlighted, its name over the pane. Window
  600 wide (140px list). UI text says "section" instead of "tab".
- 0.14.3: keep-out checkboxes compacted (the long "Keep all Mageweave Cloth in my normal bags" ran off the popup):
  a "Keep in my normal bags:" heading, then "all Cloth" and "<item>" side by side; a long item name is cut off.
  Mutually exclusive (user): ticking one clears the other's rule.
- 0.14.2: the weight popup remembers where it was dragged (SedimentDB.popupPos, top-left corner relative to the
  screen, kept across sessions; clamped to the screen); until first moved it opens next to the cursor.
- 0.14.1: wording. The item-level keep-out box named the item ("Keep all Silk Cloth in my normal bags"), not "Keep
  just this item", which read like one stack; item weights read with the item's name ("Silk Cloth") instead of
  "This item" (a "(this type)" suffix was tried and dropped, user: just the name). Both cover every stack.
- 0.14.0: keep items out of special bags (first outside user's feedback: she didn't want her cloth in the
  reagent bag, so it works per subclass: "Keep all Cloth in my normal bags", plus one item type: "Keep all Silk Cloth"). Two
  checkboxes in the weight popup (shown for items a special bag would take or that are in one;
  SedimentDB.keepOut = { items, subclasses }; an early per-item-only format converts):
  never transferred in; a new evict phase (after merge, before transfer) moves ones already in a special bag to
  empty normal-bag slots; their partial stacks merge towards the normal bags. Global switch on the Sorting tab,
  "Fill reagent and profession bags automatically" (SedimentDB.fillSpecialBags): off = nothing moved in, what's
  there stays and is sorted. Sim: keep-out and fill-off tests.
- 0.13.0: onboarding and docs. A welcome screen in the settings window explains float/sink, background sorting,
  and how to start (Select mode), with "Set weights", OK and "Don't show this again"; ? brings it back.
  "Show testing tools" became "Debug mode", which also reveals a Commands tab. All /sed commands live in one
  table (ns.COMMANDS, plus ns.SHORTCUTS for the mouse), used by /sed help and the Commands tab; unknown
  commands say so instead of printing a stale list. README rewritten from the code (commands table generated
  from ns.COMMANDS); NOTES' design sections replaced with "How it works now". Select mode opens the bags when
  it starts and leaves them open when it ends (user's call).
- 0.12.1: bag button = Blizzard's button-style gear, Interface\Buttons\UI-OptionsButton (user's pick after trying
  candidates in game). The old dice fit because it was a button graphic (small art, transparent padding);
  item icons fill their square and looked heavy. 15px in a 20x20 click area, centred on the search bar: the
  bar is 18 units (even), so not an odd/even centring issue as first thought; 16 looked about half a pixel
  low, 15 with no nudge lines up (probably uneven border art in the input box, or UI-scale rounding). UI
  units scale with the bag, so a large UI scale keeps the proportions; "search bar height - 3" would also
  follow a skinned/resized search bar (not done). Tuning commands (/sed icon, nudge, iconsize) removed and their saved values
  cleared.
- 0.12.0: settings streamlined (user, 2026-11-24). One window, three tabs: Weights (ladder + select mode +
  reset; sink line and default edited only in the ladder), Sorting (auto on/off, Partial/Full order moved
  from the bench, wait, smoothness, open-bags behaviour, "Show testing tools"), Testing (hidden by default:
  scramble mode/seed, status text toggle, recent sorts). The separate bench window and dice button are gone;
  a bag button (placeholder icon, /sed icon cycles candidates) opens Settings on the Sorting tab. Select mode
  (user's idea; a one-shot picker was rejected as too many clicks): Sediment's own click-catchers parented to
  each bag item button (follow them, no taint), highlight + weight number (orange = default), click opens
  the popup. Every Sediment window closes when combat starts. Fix found in game: a bag window's slot list
  (EnumerateValidItems) can run past its buttons (a closed window keeps its old size), so a nil entry
  errored (Settings.lua:476) and ended the loop before the reagent bag's window; entries are now skipped
  if empty or the window isn't shown, and bag windows also come from ContainerFrameContainer.ContainerFrames.
- 0.11.0 also: smoothness budget default 0.3ms/frame (was 0.1), picked in game: Drift clean-ups ~1s instead
  of 2s+, worst second about -6%. Speed slider dropped from the to-do: a good default is enough.
- 0.11.0: setting for opening the bags during an auto-sort (SedimentDB.openBags): "pause" (default, as before)
  or "finish" (send everything left at once, unpaced, in auto-sort's own order; a separate `hurry` flag, not
  the button takeover, which switches to the full order). Idea (user): sort slowly in the background, finish
  now when the bags open; makes a full-order background sort viable. Sim: finish-now gives the same placement
  moves as an uninterrupted auto-sort and never pauses.
- 0.10.2: editing safety. Bug (2026-11-24): two weights (Miscellaneous class 15, Blacksmith Hammer 0.02)
  vanished from the ladder unseen. Cause: the ladder re-sorts on every change, so a row frame can change
  hands; a still-focused number box saved its stale text (blank = remove) onto whatever rule now owned the
  row. Fix: a box remembers the rule and text it was focused with and only saves if both still apply; any
  focused box is finished before a re-sort; removing doesn't re-sort (row stays, greyed, with Undo); clicks
  within 0.3s of a re-sort are ignored; late item names relabel in place. The weight popup gets the same
  guard (it follows its item when a sort moves it). Escape now cancels instead of saving, everywhere.
  Recovered from SavedVariables/SedimentSort.before-accidental-removal.lua (the 13:26 save) by diffing.
- 0.10.1: progress sweep shows work, not time: swaps done out of swaps known, never backwards,
  held below full until the sort really ends, kept across pauses. It glides smoothly (user: plain steps per
  swap "isn't useful"): toward the next swap's mark at this sort's pace, waiting there if the swap is late,
  catching up in a straight line within 0.15s when behind. Tested with a fake clock: never backwards, never
  full early, never past the next mark. User report: after sending mail and
  closing the bags, a full sweep then a smaller second one (a too-short time estimate let the cooldown finish,
  then the next round put up a new one); and a slow sweep on a fast sort (too-long estimate). The time
  estimate (Sort.EstimateSeconds) is gone. Sim also checks auto-sort settles: right after an auto-sort, a
  second one never moves anything (it didn't; not the cause).
- Renamed 2026-11-22 to match the GitHub repo: folder ~/Source/SedimentSort, SedimentSort.toc, AddOns symlink
  SedimentSort, saved settings in SavedVariables/SedimentSort.lua (copied from Sediment.lua with the game
  closed; the old file is left as a backup). Display name, chat prefix, /sed and SedimentDB unchanged.
- 0.10.0: settings window (Settings.lua), /sed or the popup's Settings button. Ladder tab: every set weight
  (items, flags, subclasses, classes, default) light to heavy with the sink line drawn across; edit in place,
  x clears; "Not set" lists bag categories falling through to the default, with counts and a box each. General
  tab: auto-sort on/off, wait, speed budget, sink line, default weight, reset to starter weights (confirmed).
  Edits queue an auto-sort. /sed help lists commands (bare /sed now opens the window).
- 0.9.0 bench: Drift scramble mode (four distinct items move to the top of the gap, each leaving a hole: the
  everyday case; default mode). Smoothness metrics replace average FPS (which flattered long sorts): worst
  second (lowest FPS over any one-second window during the sort and the second after, as a % drop from normal
  - the headline), hitches per second (frames over 1.5x normal frame time), worst frame vs normal. Readout
  shows as one line ("Partial: 2 moves, 1.4s, -2%, 20ms"; details in its tooltip) in the strip under the bag's search box whenever the bench's "Status text" checkbox is on
  (SedimentDB.benchStatusText, default on); the bench window sits above the bag.
  Fix: the swap allowance reset at each round, so a two-round sort's two hitches came a quarter-second apart
  (seen in game after a quest reward: 2 moves, worst frame 22ms); it's now set once per sort.
- 0.9.0: auto-sort uses the partial order (stableFill2 from the benchmark): equal-weight groups keep their order,
  identical stacks stay together, and a band whose position shifted moves whole groups adding up to the shift
  from one end to the other instead of sliding. Button sorts keep the full order. Toggle in the test bench
  ("Auto: Partial/Full", SedimentDB.autoOrder) for in-game A/B. Sim (built-in, 20 seeds): loot+use 8.6 -> 2.7,
  set swap 7.3 -> 1.3, loot 3 15.8 -> 5.5, use 3 16.9 -> 8.1 moves. Bench history records which order ran.
  The sim's pause test now compares placement moves only: which of two same-item stacks (different counts)
  ends where can differ by run, so the restack phase may differ by a move; the sim now also asserts partial
  stacks end last.
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
- 0.7.0: special bags by their own type. Bug found by the user: on another
  character the reagent bag slot holds an herb bag, and Sediment tried to put a feather (a crafting reagent)
  in it. A bag's type now comes from the bag item (container subclass 11 = reagent bag) and its family
  (GetContainerNumFreeSlots); a profession bag takes items whose C_Item.GetItemFamily matches, wherever it sits,
  so profession bags in the normal slots are sorted too (was parked). Profession bags fill before the reagent
  bag (an herb that's also a reagent goes to the herb bag). Refusals remembered per bag. Sim: big/small
  reagent bag, herb bag in the reagent slot, mining bag in a normal slot; 300 seeds pass.
- 0.7.1: pausing keeps the plan (user: "I think that worked", 2026-11-22). Opening the bags mid-auto-sort used to stop
  it and throw the plan away; re-planning after every interruption made a long chain crawl one slot per
  interruption (user: a non-set cloak swapped into the set band stepped down one slot each time they opened
  the bags as the sweep started; the first swap of a chain's reversal is "first slot <-> its neighbour").
  Now it pauses with the plan and the streamed round's progress kept; when the bags close and have been quiet
  for the auto-sort delay, it checks the remaining swaps still find what they expect (item and count at both
  ends) and carries on, else re-plans. The sort button during a paused auto-sort takes it over at full speed
  (it used to cancel it). Sim: interrupting after every swap gives exactly the uninterrupted move count.
- 0.8.0: test bench (verified in game 2026-11-22). Dice button left of the sort button opens a small window:
  mode button (Minimal: a few top/bottom swaps; Full: shuffle; Maximal: reverse + a few swaps), seed box
  (Park-Miller, since math.random can't be seeded: same seed on the same sorted bag = same mess), Scramble.
  Scrambles run through the sort engine at full speed, normal bags only, then queue an auto-sort. Every sort
  records moves, rounds, seconds, our ms, worst frame and FPS vs the frame rate just before it
  (SedimentDB.benchHistory, last 20; the window shows the latest). Gotcha found: empty slots as nil make # stop
  at a gap, so the slot count is passed separately.
- 0.7.0 also: progress sweep. A cooldown frame (GCD clock) over
  BagItemAutoSortButton and MainMenuBarBackpackButton runs for the estimated time left (Sort.EstimateSeconds:
  rounds x 0.3s server wait + streamed swaps x running-average swap cost / budget / FPS), re-aimed every
  round. Success ends it with the cooldown bling; interruptions clear it; sorts that move nothing never show it.
  Lives in Sediment.lua (no new file, so no client restart).

## Within-weight order: benchmark (2026-11-22, dev/sim.lua bench mode, 10 seeds x 60 events)
Idea (user): equal weight means "don't care", so auto-sort shouldn't impose an order inside a weight band.
Proposed split (user): the button does the full canonical sort; auto-sort does the partial one.
Average moves per event, starting from a sorted bag:
| event        | current (class/subclass/ID) | stable (current position) | stableFill |
| loot + use   | 14.8                        | 13.6                      | 4.2        |
| set swap     | 12.8                        | 1.5                       | 0.9        |
| weight edit  | 1.5                         | 1.4                       | 1.0        |
- stable: within a band, identical items together, groups in current order (light bands append, heavy bands
  prepend: both grow toward the gap). Adding set-name grouping (stableSets) cost most of the set-swap win (9.4),
  and the user doubted its use, so it's out.
- stableFill: stable, plus within each band one whole group of identical items may move to the band's front or
  back when that leaves fewer slots wrong. A used-up item then costs about one move per later band instead of
  one per later item. Identical stacks are never split (sim asserts it); classes may mix inside a band (the user
  is fine with that, not with split stacks).

Second bench (20 seeds x 60 rounds of five events; bags fuller, so loot + use differs from the first table):
| event        | current | stable | stableFill | stableFill2 |
| loot + use   | 8.1     | 7.6    | 2.7        | 2.8         |
| set swap     | 7.1     | 2.1    | 1.3        | 1.3         |
| weight edit  | 1.3     | 1.3    | 0.8        | 0.5         |
| loot 3       | 14.9    | 14.3   | 7.6        | 5.3         |
| use 3        | 16.0    | 16.3   | 11.1       | 7.9         |
- stableFill2 (user's idea): also every rotation at group boundaries, i.e. when the bands before grew or shrank
  by N, move whole groups adding up to exactly N from one end of the band to the other. Same as stableFill when
  bands shift by 1; clearly better when they shift by more (multi-item loot, several things used up).

## Idea details: Buff food and Drink flags (parked; see To do)
- Buff food flag (discussed 2026-11-20, user said "not quite yet"). Classic data files all food and drink under
  Consumable > Food & Drink. Buff food's tooltip says "well fed" ("If you spend at least 10 seconds eating you
  will become well fed and gain ..."). Plan: for Food & Drink items only, read C_TooltipInfo.GetItemByID(itemID)
  lines, look for "well fed" (case-insensitive), cache per itemID for the session. Make it a flag, so it beats
  the Food & Drink subclass weight. Suggested starter weight 9.5 (just after food at 9).
  Caveats: English text only; odd buff foods (e.g. Dragonbreath Chili) may not say "well fed" and need an item
  weight; Forever may word some foods differently, so show the flag in /sed scan and check against real food.
- Drink flag, same idea: C_Item.GetItemSpell(itemID) names the use spell "Food", "Drink" or "Refreshment".
  Also English names.

## Early history (0.1.0-0.4.0, 2026-11-20)
Historical; current behaviour is under "How it works now" at the top.
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
- dev/check_globals.sh: run after every change. Fails on any global that isn't a known WoW API or Sediment's
  own; catches a local declared below the function that uses it (bitten twice: cpuMs in Sort.lua, then
  lastBagUpdate in AutoSort.lua's QuietLongEnough, 129 errors in game). The sim mocks AutoSort, so it can't.
- dev/sim.lua runs the real sort against mocked APIs using a saved /sed scan, with slot locks modelled:
  `lua dev/sim.lua <SV file> [seed] [show]`. 200 shuffles: full sort 3-6 rounds (extra rounds are merges; the
  sim splits stacks on purpose); "last floater jumps to the top" and back: always 2 rounds.
- In game: 17 moves in 2 rounds = 0.7s; 13 moves in 3 rounds = 0.8s; no server errors.
- Dropping a full stack onto a partial one tops it up and leaves the rest behind (confirmed in game).

## First probe findings (0.0.1, 2026-11-20)
Still true: how Forever classifies items, which shaped the starter weights.
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
