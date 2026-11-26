# Sediment working notes

Design and open questions. This file is not part of the addon.

## How it works now (0.17.0)
User-facing overview: README.md. This section is the developer's view; history is in the version log below.

- **Weights** (Weights.lua): most specific rule with a weight wins: item > flags (Equipment set > Quest > Gray >
  BoE gear, stored as unboundGear: equippable and not soulbound) > subclass > class > default. Gray quality is
  trash (not Miscellaneous > Junk: classic data files normal items there). Account-wide, in
  SedimentDB.weights; the default (DEFAULTS in Weights.lua) is no rules, so ties fall back to the full order and
  it starts out as a by-type sort. Resolve is a table-free version of Explain.
- **History** (Weights.lua + the History section, 0.17.0): versions of the rules (weights incl. sink line and
  default, keep-out; not settings) in SedimentDB.history, newest first. Saved before Reset to default, the
  setup questions starting / starting over, and loading a version; at setup Done; at login if changed
  ("<character> login", at PLAYER_LOGIN since rules are account-wide); and
  by "Save a copy" (optional name). No two in a row alike (compared by a sorted serialization), no empty
  sets unless asked; newest 20 unnamed kept, named kept until deleted. "Restore previous rules" = load the
  newest version that differs from the rules in use. Replaced the single backup slot (rulesBackup, which
  converts to the oldest version).
- **Ranking** (Weights.lua, used by the setup questions): the rules as an order: rungs of equal weight
  (the default is a rung too) with a divider at the sink line, or at 50 in the packed layouts (sink line
  >= 100 or <= 0). PlaceRule puts a rule at a named place (first, last, float = end of the start half,
  sink = start of the end half, bottom, after/before another rule), then WriteRankingList pins the default
  next to the empty space (PinDefault: middle = just above the gap, space at the bottom = last, at the top
  = first) and renumbers everything by position: start half 0-50, end half 50-100, steps of 10 while they
  fit; a sink line between 0 and 100 becomes 50. Ties stay tied, except with the default.
  dev/ranking_check.lua.
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
- **UI**: sort button (left: sort, right: toggle auto-sort); a gear next to it (or /sed) opens the setup
  questions while there are no rules or a run is unfinished, else Settings (Settings.lua) at Weights:
  a section list like WoW's Options window: Weights (Select mode, ladder, reset), Special bags (bags, fill
  switch, keep-out rules), Sorting (auto-sort options, Debug mode), History, and in debug mode Testing
  (seeded scrambles, status text, recent sorts) and Commands (ns.COMMANDS / ns.SHORTCUTS in Sediment.lua, also
  /sed help). Alt+right-click popup (Popup.lua). Every Sediment window closes and Select mode ends in combat.
- **Order** (Order.lua, 0.19.0: the settings' Order section, which replaced the Weights page and the Setup
  window; see the version log. The Setup notes below are history): their own window, opened with the
  settings until dismissed or done; ? brings the first page back. Steps: layout, hearthstone, neighbours
  (Select mode with Setup's click handler), gray, trade goods, then equipment sets / BoE / bags / quest
  items if present, then generated class questions (most unruled items first; Split = per subclass),
  then the review (select a rung, Move up/down). Every answer is a PlaceRule plus a button-speed sort
  (SortSoon waits out a running sort). State in SedimentDB.setup: the steps, the index, and per step a
  copy of the weights from when it was shown (Back restores it). Highlights (Settings.SetHighlight):
  orange outline = no rule of its own, gold = what the question is about; frames that take no clicks.
  dev/setup_check.lua clicks through it against mocked frames.

## Writing style (user, 2026-11-25)
- Every word for one of Sediment's own things, and every button label, lives in Text.lua (ns.TEXT), under
  keys named for a role, never the word (SaveInUse = "Active", ClearAllButton = "Start Fresh"): a word change
  is one edit in that one file, and keys are never renamed with it (user, 2026-11-25, after a rename touched
  two files). dev/text_check.lua fails on a key used but not defined (it would show as the key in game) or
  defined but unused. Section ids "Weights" and "History" are internal; their shown names come from Text.lua. L(key) plain (titles, button labels),
  N(key) a noun in a sentence (sand `c8a96e`, the chat prefix's colour), B(key) a button name in a sentence
  (gold `ffd100`, like button text). README: nouns **bold**, button names `code style`. No quotation marks.
- The nouns, and only these: **Sediment**, **Weight(s)**, **Select Mode**, **Setup** (the questions),
  **History**, **Pinned** (a save kept at the top; was "Kept"), **Empty Space** (the gap where new loot
  lands; also the name for the number that used to be shown as "sink line": user, 2026-11-25). Code still
  calls it sinkLine. Buttons in Title Case (Start Fresh, Save Rules).
- "Rules" means the whole set (all Weights plus keep-out), never one entry: "x removes a Weight", "Save
  Rules", "Start Fresh clears your rules". A History entry is "a save".
- The keep-out rule is "Keep out of special bags" (list heading "Kept out of special bags"). "Not set" is a
  plain phrase, lowercase in sentences. No "kind" / "category": "all Cloth", "Silk Cloth", the game's own
  class names. "Empty Space", not "gap" or "sink line". Not reformatted: these notes' history sections.

## To do (updated 2026-11-25)
In-game tests left (0.17.1, uncommitted; /reload is enough):
- Layout: the 760x600 window, opaque now (solid WHITE8X8 background: the tooltip art is translucent itself),
  Weights rows 430 wide and striped so each x sits by its item, and the new spacing on every section (Sorting's boxes no longer on their help
  text); History rows (Pin / Unpin left, Load and x right; long reasons and summaries fit).
- History: Pin asks for an optional name and moves the save to the top (no "(Pinned)" text: the Unpin button
  says it; "Active" (was "in use"; "Current" read as "newest") leads the summary line, which cut it off at the end); Unpin; x greys the row
  with Undo, and closing the window removes it; your "original rules" shows as Pinned (converted from Kept).
- Start Fresh: on the first page and in Weights (asks first, then Setup); clears Weights and keep-out rules
  (both are in the save); Combined Backpack: switch it to separate bags, then Start Fresh / Continue turns it
  back on and the question page and chat say so (the CVar call is what Blizzard's bag menu does; untested).
- The gear and /sed: Setup with no rules or an unfinished run, else Weights; first-page Settings button.
- Earlier, still open: a clean full Setup run; does the generated-question order make sense on real bags.

Code left:
- Onboarding (see "Planned: onboarding questionnaire" below), agreed 2026-11-24, in this order:
  1. Done (0.16.0): "Reset to default"; empty default rules; Full order for new installs.
  2. Done (0.16.0): automatic backup before rules are replaced, if there are any; "Restore previous rules".
  3. Done (0.17.0, not yet tried in game): the questionnaire (Setup.lua), whose first page replaced the
     welcome screen, with the "no rule yet" highlight on bag slots while it runs.
- Settings window extras: Options > AddOns entry; drag items onto the ladder to add them; a full category
  browser (today "Not set" only lists categories in the bags).

Ideas / parked (decided not now):
- Profiles (user, 2026-11-25, parked): several named setups (Herbing, Raiding) to switch between, as their own
  small section like other addons' profile lists, if anyone needs it. Came out of a History design with
  named mains and snapshot lineage that grew too complicated for a bag sort (main/snapshot, Save on the main,
  Make Main for rollback or fork, unique names, legacy users choosing a Main). History stays a safety net.
- History order while on the page (user, 2026-11-25, parked; "moving under the mouse is gross"): hold the
  list's order while the History page is open (a new entry right under the row you clicked, pin changes in
  place, re-sort on reopening). Dropped for now: it only matters with unsaved changes plus a Load while on
  the page, and Load ignores clicks right after a redraw.
- Guided tour (user, 2026-11-26, parked): the Order help paragraph is small and dense, and nobody reads it.
  Idea: a short "wizard-like" tour of callouts pointing at one thing at a time, each with an Okay button.
  Discussed (2026-11-25):
  - Forever has Blizzard's HelpTip (Blizzard_SharedXML/HelpTip.lua: arrow callout, Okay / Next / Got It
    buttons, acknowledge callbacks), but it shows nothing when the player has turned tutorials off (CVar
    hideHelptips). Claude's lean: our own small callout styled like it, which always shows and is testable.
  - Suggested steps (at most 5-6): the bag's gear ("Set up how your bags sort"; advances on the click), Start
    Fresh on the welcome (advances on the click), the Empty Space row (rows above pack at the top; new loot
    lands there), the first row below it (sinks to the bottom), any row (drag to reorder; bags re-sort as
    you go), the Select Mode button (hover to find a row, click to add one).
  - A step that asks for a click advances on that click; only explanation steps get Okay. Point at rows and
    buttons, not bag slots (Start Fresh sorts the bags just as the tour starts). An x on every callout ends
    the tour; ? replays it. It doesn't auto-start for players who already have rules.
  - The paragraph then shrinks to one line in a normal-size font, or goes. (The bigger font alone is a quick
    win either way.) Cost: each step is tied to a button or row, so UI changes need the tour updated.
  - Undecided: own callout or HelpTip; advance on the action or Okay on every step; start at the bag's gear
    the first time the bags open or only once settings open; keep the welcome in front (tour after Start
    Fresh) or let the tour replace it.
- Setup questions (user, 2026-11-25, the "skinning knife" case): a question lists, outlines and counts only
  the items its answer would decide, so not items a more specific rule already places (an item's own
  Weight, an earlier flag). A special question (sets, BoE, bags, quest items) with nothing left to decide is
  skipped.
- Setup redesign: BUILT in 0.18.0 (2026-11-25) as described below, except the last point:
  - Setup becomes just "Your order": the kinds of items in your bags in plain by-type order (no opinions),
    plus the Empty Space row; Move Up / Move Down; click a row to outline its items; the bag sorts on each
    move. The per-category questions (layout, hearthstone, neighbours, gray, trade goods, specials,
    generated classes) go; single items are placed afterwards with Select Mode.
  - The Empty Space row is movable, and its position is the layout: at the top = everything packs toward
    the bottom; at the bottom = packed from the top; in between = float above / sink below. No layout
    question, no float/sink or higher/lower wording. Underneath, one layout: the stored number stays 50 and
    the divider's position does the rest (the 0 / 100 packed values go away).
  - Unset items stay attached to the Empty Space (user: agreed), on the side that has items: just below it
    when it's at the very top, just above it otherwise. Not a movable row (a movable "Everything else" was
    tried and rejected the day before); add a movable "Not set" row only if someone asks.
  - NOT the user's request (Claude suggested it and recorded it here as agreed by mistake): Empty Space
    Move Up / Move Down buttons on the Weights page. Built, then removed the same day: the user didn't ask
    for them, and the Empty Space already moves there by its number.
  - Root cause noted by the user: the tester mostly wanted simple, and the old rules weren't consistent
    (the hammer and pick had Weights, the skinning knife didn't). Idea, not decided: a "Profession tools"
    flag from a fixed item-ID list, since WoW files tools under unrelated categories.
- Setup review (user, 2026-11-25): clicking a row outlines its items in the bag gold (items whose winning
  rule is in that row). The Empty Space row is just "Empty Space" (a parenthetical was removed; the user's
  rule: no parentheticals in UI text without asking). Open, from the same feedback: "Higher up / Lower down"
  says nothing about "than what" in the packed layouts (options: name the bag edges, use the Empty Space as
  the reference, or skip float/sink there and order in the review); "Quest" (item class) and "Quest item"
  (the game's flag) look like duplicates (proposed: one question and row). Other UI parentheticals
  ("Not set (default)", "(question 4 of 9)", "(the version in the .toc)", "missing (restart the game)",
  "(removed)", "(deleted)") left for now, pending the user.
- History simplified (user, 2026-11-25), replacing everything below about names, Save Rules and several pins:
  two kinds of entry, Created (Setup done; always new) and Snapshot (logout via PLAYER_LOGOUT, before Load
  and Start Fresh, and a login safety net; only if no entry holds the rules in use); titles "<character> —
  <kind> — Nov 25, 10:32" (EntryTitle), the date no longer in the summary line; one pin (pinning moves it);
  newest 20 unpinned kept. Removed: Save Rules and the name box, names, the Pin dialog. Upgrade keeps the
  most recently pinned entry; older entries show their name or reason in place of the character.
- History, 2026-11-25 (user): Load has no "are you sure?" (it's safe; Load clicks are ignored for 0.3s after
  the list redraws, so a double-click can't load the save it just made). No save is made when any save
  already holds the rules in use (was: only the newest). Active / Previous are tracked by save id
  (SedimentDB.activeSaveId / previousSaveId, NoteActive): Previous = the save Active before the current one,
  or the last Active one while edited rules match no save.
- History preview: dropped (user, 2026-11-25): Load already saves the rules first, so it's a safe way to
  try a save; History marks the save to roll back to as Previous instead.
- Unset items (user, 2026-11-25): the Weights list shows both the broad group and the narrower one for the
  same item (Projectile and Arrow), and nothing ties them together. Options discussed: one orange row per
  narrower group with an item icon (broad groups set from Select Mode / the popup), pointing to Select Mode
  instead of listing them, or a step-by-step wizard for what's unset. Decide later.
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
  Built for the setup questions (0.17.0, only while they're open); a switch to show it any time is a small
  step from there (Settings.SetHighlight).
- Weight versions: built as History (0.17.0).
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

## Planned: onboarding questionnaire and empty starter rules (designed 2026-11-24, built 0.16.0-0.17.0)
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
- 0.19.0 (2026-11-25, user's calls): one place to arrange. The settings window's Weights page (rules as
  numbers) and the separate Setup window are merged into the **Order** section (Setup.lua -> Order.lua, the
  list built into the settings page): the same list everywhere, no numbers shown. Section order: Order,
  Special bags, Sorting, History. The gear and /sed always open Order; on Order the window opens the bags and
  sits beside them unless dragged (SedimentDB.settingsPos). A welcome covers the list while there are no
  rules, or after ?. Start Fresh (welcome button, or the bottom button, which asks first): ClearAll + the
  default order + a Created History entry + Combined Backpack. x on a row removes its rules; the row stays
  greyed in place with Undo until the list next changes or the section closes. Rows are drag and drop, Move
  Up / Move Down, click to outline, Pick from Bags with widen. Gone: Continue, Done, "Don't show this", the
  Select Mode button (Pick from Bags replaces it; Alt+right-click still opens the popup), the ladder.
  Weights.AddKindRows removed. Old Setup saved state (setup, setupHidden, setupPos) cleared on load.
  Weight popup (user's sketch): no numbers. The levels that apply, most specific first (item, flags,
  group/part, group; "Not set" only when nothing applies); the winner marked "< wins"; Add only on levels
  above the winner (only those can change this item: a flag beats any group, so e.g. Armor/Cloth can't
  override Gray Quality); levels below the winner dimmed with nothing beside them (user: no "has a row"
  text). Add = Weights.AddRuleAbove (same as Pick from Bags). Settings opens Order with the deciding row
  selected (Order.Select). Hint: "Add gives it a row; arrange rows in Order."
  Trade-off accepted (user): rearranging on the run needs Order open; the idea is to dial it in and forget it.
  Then, from the user's in-game review (2026-11-25):
  - Popup: "Sorted as <the Order row's name>" (the Quest group sorts as "Quest Items", the row that holds
    it; Order.RowLabel); no floats/sinks; a part named like its group ("Quest/Quest") isn't listed unless it
    has a rule; Sort Now removed (Add sorts, auto-sort runs, the bag has its own button).
  - Order: rows were hard to pick up even when nothing was updating. Pickup no longer uses WoW's
    RegisterForDrag/OnDragStart: a grip at each row's left starts the drag on the press; a press anywhere
    else drags after 5 px of movement; the release is caught wherever the mouse is (IsMouseButtonDown polled
    in OnUpdate). If it's still hard to grab, next step is a debug trace of what the row receives.
  - Move Up / Move Down removed. The right column: Pick from Bags, then the selected row's widen choices
    (any item row, not just the last pick; a group/part row offers its group). The strip under the list is
    gone; the list runs down to Start Fresh; the window is 680 tall (was 600).
  - Pick from Bags is on whenever the list shows (not under the welcome); the button turns it off until
    Order next opens. Hovering a bag item lights up the row that sorts it (LockHighlight; scrolled into view
    if needed); click still adds a row (user chose this over "click selects, Add adds").
  - Select Mode: no weight numbers on the slots; Alt+right-click opens the popup even while picking.
  Then (user, 2026-11-25): dragging confirmed good and easy. Widen heading is "Sort X as:" and the choices
  are named exactly like rows, no "all" (user: drop it for now; if it confuses, revisit; hover outlines
  show what a choice covers). The popup always opens just above the bag window (Settings.BagWindow),
  left edges lined up, grows upward, isn't draggable, and SedimentDB.popupPos is cleared. Overlap fix: the
  settings window is HIGH strata, the popup DIALOG (both were DIALOG and their parts interleaved: the
  window's buttons drew through the popup's text); the popup's background is solid (WHITE8X8, alpha 1).
  Then (user): "Pick from Bags" / "Stop Picking" read badly once it was on by default: the button shows the
  state, "Select Mode: On" / "Select Mode: Off" (Select Mode is a noun again). The drag grip went: press
  anywhere on a row and move works well (user: "the new drag and drop code is really good").
- 0.18.0 (2026-11-25): Setup is the first page plus "Your order" only; the per-category questions (layout,
  hearthstone and neighbours, gray, trade goods, specials, generated classes, Split, Back/Skip, progress) are
  gone. Start Fresh lists a class rule per item class in the bags, in class order, with the Empty Space at the
  bottom; Continue adds rows for classes with unset items next to the Empty Space. The Empty Space row is
  selectable and movable, and its position is the layout (Weights.MoveEmptySpace); one layout underneath:
  the sink line is always 50 after a write, old 100 / 0 saves read with the divider at the end / start.
  Unset items are pinned on the Empty Space's side with items (PinDefault). Removed from Weights.lua: PlaceRule, SetLayout,
  RuleSide, RankSplit. Text.lua: unused question buttons removed; PrevQuestionButton -> BackButton.
  dev/ranking_check.lua and the Setup part of dev/setup_check.lua rewritten.
  Also (user, same day): Pick from Bags in "Your order" (Select Mode with Setup's click handler). A click adds
  the item's row right above the row deciding it today (Weights.AddRuleAbove), selected; a strip ("Widen
  <item> to:") offers its subclass, class and any applicable flags; hovering outlines what the choice would
  cover; choosing swaps the rule in the same row (Weights.ReplaceRule). One click for the item, one more to
  widen; double-click was rejected (it delays every single click and only reaches two levels), Shift/Ctrl+click
  shortcuts not added. No remove on rows yet (open question).
  Then (user, same day): Setup window 420x640 and the selected row scrolls into view after a pick or move;
  drag and drop in "Your order" (any row or the Empty Space; a gold drop line; the list scrolls near its
  edges; Weights.MoveRow); names as Group/Part paths ("Armor/Cloth", widen "all Armor/Cloth", "all Armor",
  "all BoE Gear"; Settings.SubclassLabel, so the Weights list and History read the same) and Title Case flags
  (Equipment Set, Quest Items, Gray Quality, BoE Gear). Start Fresh's default order (Weights.DefaultOrder),
  from the user's own rules: Hearthstone, Consumable/Potions, Consumable/Bandages, Consumable, Quest Items
  (one row: the quest flag and the Quest class), BoE Gear, other classes in the bags, Empty Space, Weapon,
  Armor, Trade Goods, Miscellaneous, Gray Quality. Equipment Set left out (set pieces still group by set).
- 0.17.1 also (2026-11-25, user's calls): ns.TEXT names table (nouns + button labels); "Kept" -> "Pinned", with
  a Pin / Unpin button (left, far from x) that asks for an optional name, pinned saves first by pin time; x in
  History greys the row with Undo and deletes on window close (no dialog); "Restore previous rules" removed
  (History's Load covers it); "Reset to default" became Start Fresh (save, clear Weights and keep-out, open
  Setup); Start Fresh on the first page clears keep-out too; Start Fresh and Continue turn on Blizzard's
  Combined Backpack (CVar combinedBags, as Blizzard's bag menu sets it) and say so; window 760x600 with one
  spacing system (Flow, GAP_HELP 6, GAP_GROUP 18, controls centred on their label); wording per "Writing
  style". Found by the tests: Setup's Combined Backpack notice came back on later runs (cleared per start).
  A Weight change (typed or removed in Weights, Undo, the weight popup, a History load) now sorts at once,
  bags open or not (Sort.StartSoon, moved from Setup; user, 2026-11-25: show the outcome). Other settings
  don't sort.
  Weights section: one list (user, 2026-11-25). Unset groups are orange rows right after the default's row
  (where they sort), both the broad and the narrow group for now; once given a Weight a row sorts normally.
  Above the list, a bright orange line "N items in your bags have no Weight yet." whose space is always kept
  (text empty when none), so the list never shifts. (Tried and rejected the same day: a separate "Not set"
  section, first below then above the list, that vanished when everything was set and made the list jump.)
  Text.lua holds the words under role keys (new file; without it words show as keys and the login check says
  to restart). Debug > Files (user's idea, 2026-11-25): the .toc version and each expected file loaded or
  missing. Each file marks ns.loadedFiles itself; ns.FILES (Sediment.lua) drives this and the login check;
  dev/files_check.lua keeps it equal to the .toc. Open question it answers: does a /reload load a new file
  on Forever? Answered 2026-11-25: yes. After adding Text.lua to the .toc, a plain /reload (no restart) showed
  "All 10 files loaded" in Debug > Files. The older "new files need a full client restart" (from 0.0.x/0.7.0)
  no longer holds, or never did on this client; the login check stays as a safety net.
  Fixed (user, 2026-11-25): "Fill reagent and profession bags automatically" couldn't be ticked again once
  off, since 0.14.0: it saved `on and nil or false`, which is always false. The same idiom in
  dev/resolve_check.lua meant its random levels were never cleared; fixed, and it still passes.
- 0.17.1 (2026-11-25, user's calls): the gear and /sed open the setup questions' first page while there are
  no weight rules or a run is unfinished (unless "Don't show this" is ticked: SedimentDB.setupHidden, a new
  flag so the old welcome's welcomeHidden doesn't hide them), else Settings at Weights; the first page's
  "Not now" became "Settings". Sections ordered Weights, Special bags, Sorting, History. Defaults as the
  user's screenshot: auto-sort order Full for everyone who never picked one (Sort.AutoOrder; was Partial
  for saves older than 0.16.0), Finish now when the bags open mid-sort (was Pause). Done no longer sets
  the "don't show" flag (with rules set, the gear opens Weights anyway). The first page's buttons are a
  fixed Start fresh / Continue pair with a status line (see 0.17.0 notes). Weights section: "Click below to
  enter Select Mode." above the button, what to do while it's on below it. Writing style applied (see
  "Writing style"); History reasons read "before Setup", "Setup done", "before Start fresh".
- 0.17.0: the setup questions (the questionnaire planned below), in a new Setup.lua with its own window;
  its first page (the pitch) replaced the welcome screen. Decisions made while building, open to change:
  - Answers are places in an order (Weights ranking), not numbers: float = end of the top part, sink =
    first below the gap. Unset items (the default) are pinned next to the empty space in every layout and
    aren't a row in the review; its empty-space row reads "empty space (and anything not set)" (user,
    2026-11-24, after the first try: a movable "Everything else" row put random stuff among packed items); gray sink = the
    very bottom (above a hearthstone put last); neighbours next to the hearthstone, the first clicked
    nearest (fixed after the first in-game try: with the hearthstone last, the first pick was farthest). Every answer renumbers all weights by position, existing ones included (the order is kept;
    the backup is taken when a run starts, only once per run even with Start over).
  - Packed layouts (sink line 100 / 0) still split at 50; their answers read "Higher up" / "Lower down"
    (first tried "Near the start / end": hard to understand, user 2026-11-24). The review hides that divider
    and shows the empty space at the end (or start).
  - The review moves a selected rung with Move up / Move down buttons, not arrows on each row: rows
    re-render under the mouse after a move, so per-row arrows would move the neighbour on a second click.
  - Rungs (rules sharing a weight) move together; splitting a tie is done in the Weights section.
  - Starting closes the settings window and opens the bags; the window goes left of the bag unless dragged
    (SedimentDB.setupPos). Done sets "don't show" (SedimentDB.welcomeHidden, same flag as the old welcome).
  - Generated questions are per item class among unruled items; "Split this up" appears with 2+ subclasses.
    The class question stays in the list marked split, so Back from its first subclass question returns to
    it un-split (it used to be replaced, so Back skipped it).
  - Starting over (now Start fresh mid-run) saves the rules to History, clears the weights (keep-out rules
    stay) and asks everything again (user, 2026-11-24). It first kept the answers, so classes already answered were never asked again
    ("consumes didn't resplit"). A new run after Done still keeps earlier answers by design, so only unset
    classes get generated questions.
  - History (user's call, 2026-11-24) replaced the single backup slot, which a reset or a second run after
    Done could overwrite with test answers. The user picked the triggers: setup Done, login, a button, names.
  - The first page has two fixed buttons, Start fresh (save to History, clear the weights, keep-out stays,
    ask everything) and Continue (keep the rules: resume a run, or start one that asks only what's unset;
    greyed with no rules and no run), with a status line saying which applies (user, 2026-11-25: labels
    that changed per state, Continue / Start over / Start fresh / Keep my rules / Set up my bags, were
    confusing). Anyone with rules always gets a fresh start (user, 2026-11-24). The first outside run had no such option: her old rules carried into
    the review, a likely source of a "random" Light Feather in the list (unconfirmed; the other candidate is
    a feather in her reagent bag, since the questions count special bags too).
  Settings: Select mode takes an optional click handler and slot labels (used by the neighbours question);
  Settings.SetHighlight. dev/ranking_check.lua, dev/setup_check.lua (mocked frames).
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
