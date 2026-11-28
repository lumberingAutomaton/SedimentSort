# Plan: restructure Sediment into Disorder - Item Manager

Agreed with the user 2026-11-27. For players: a new name, one section fewer, no welcome screen. For the code:
smaller and clearer, and the saved data matches what the UI shows. Every phase ends with all checks passing,
then a stop for the user to try it in game; commits only when the user says so.

## Decisions

- [x] Name: **Disorder - Item Manager**. "Disorder" is the brand, "Item Manager" the product; the user's other
      addons may join the brand later (see "The Disorder family" below). In the game it's just "Disorder"
      where space is short (chat prefix, window title).
- [x] Folder `Disorder_ItemManager`, saved settings `DisorderItemManagerDB`, debug addon
      `Disorder_ItemManager_Debug` (user's OK, 2026-11-27).
- [x] Command: `/dim` (the initials; user, 2026-11-27). `/disorder` stays free for the family (a shared
      window one day); the pattern would give `/dqt`, `/dvf`, `/dpm` to the others.
- [x] Store the **Ordering** as a list instead of weight numbers.
- [x] Item entries keep their item's name in the saved data, so they never show as "item 6218" when the
      game hasn't loaded that item this session (seen in History's hover list, 2026-11-27).
- [x] Sections: **Ordering**, **Options** (Timing on top, then Special bags: the bags you have, the fill
      switch, the kept-out list), **History**.
- [x] No welcome screen. The first time Ordering opens with nothing in it, it lays out the default order by
      itself (what Start Fresh does now, without asking: there's nothing to lose yet), including turning on
      the Combined Backpack. The ? button goes with it. `Start Fresh` stays at the bottom of Ordering.
- [x] Rename at the same time as the file split.
- [x] Old saves: the main addon never reads them. A dev script converts them once (Lua or Python).
- [x] Work on a feature branch, `disorder`, checked out in its own folder (see Phase 0).

## Phase 0: working setup

The game loads the addon straight from the repo folder (the AddOns symlink), so switching branches in that
folder would hand the game a half-built addon. A second checkout of the same repo keeps the old one playable.

- [x] Create the branch `disorder` and check it out in a second folder, `~/Source/Disorder-wip` (a git
      worktree: same repo, same history, its own folder).
- [x] After Phase 1 creates its `.toc`: link the new addon folder and its debug addon into AddOns.
- [ ] The rule while both exist: enable only one of Sediment and Disorder in the AddOns list. Two sorters at
      once would fight over the bags.

## Phase 1: rename and split (no change in behaviour)

- [x] New `.toc` (title "Disorder - Item Manager", version 0.21.0, saved settings `DisorderItemManagerDB`),
      `/dim`, window and frame names, the debug addon (`Disorder_ItemManager_Debug`), the addon's name in
      Text.lua.
- [x] One file per feature (load order): `Text.lua`, `Rules.lua` (from Weights.lua), `Bags.lua`, `Sound.lua`,
      `Sort.lua`, `AutoSort.lua`, `Settings.lua` (only the window: frame, section list, placement, closing in
      combat, shared helpers in `Settings.UI`), `Overlays.lua` (Select Mode and the outlines, from
      Settings.lua), `Popup.lua` (the popup only), `Ordering.lua` (from Order.lua), `Options.lua` (Timing and
      Special bags, still two sections until Phase 2), `History.lua` (the section), `Debug.lua`,
      `SortButton.lua` (the sort button, the gear, the sweep), `Core.lua` (start-up, events, /dim).
- [x] Each section registers itself with the window (`Settings.AddPage`: build, onShow, onHide,
      onWindowHide, refresh), so the window knows nothing about what's in them.
- Differences from the plan, all to keep this phase mechanical:
  - [x] `Debug.lua` is new: the Debug group's sections, the test bench and the bag scan, gathered from
        Settings.lua, Popup.lua and Sediment.lua. It moves into the debug addon in Phase 3.
  - [x] History's saves stay in `Rules.lua` for now; they move to `History.lua` with the data change
        (Phase 4), which rewrites them anyway.
  - [x] The rules module keeps its code name `ns.Weights` until Phase 4 renames it with the data change.
- [x] Tests and dev scripts follow the new file and frame names; nothing else in them changed. All checks
      and the simulator pass.
- [x] The user tries it in game ("basically an in place copy and code split"); commit. The Sediment AddOns
      links were removed at the user's request; the game loads only Disorder now.

## Phase 2: the player-facing changes

- [x] One **Options** section: Timing (wait after changes, smoothness) on top, then Special bags. The section
      list is Ordering, Options, History (and the Debug group with the debug addon).
- [x] No welcome screen and no ? button: the first open with nothing ordered lays out the default order (what
      Start Fresh does, without asking), once per install (`DisorderItemManagerDB.laidOut`), so a list
      emptied on purpose stays empty. The welcome's Close word went from Text.lua.
- [x] README (Getting started, Options), help text and the click-through test follow (the test now also
      checks that an emptied list stays empty, and stops visiting the long-gone "Sorting" section).
- [x] All checks and the simulator pass.
- [x] Also, from the user's in-game review: Start Fresh (and the first open) lays out only Hearthstone, the Empty
      Space and Gray Quality; a removed row's Undo stays until Ordering closes, under the row that was above it.
- [x] Bug found while testing (it predates the refactor: Sediment 0.19 did the same; see NOTES.md, "Moving an
      item again mid-flight"): fast edits made the game drop moves and leave items locked until a client
      restart, and the sort then waited for ever. Fixed: one swap waiting for the game at a time, for every sort
      (auto-sort already worked that way); locked slots are sorted around quietly; edits settle 0.5 s before
      sorting. Debug addon: a sort trace, and a red overlay on any locked item.
- [x] The user tried it in game ("so far, so good"); commit.

## Phase 3: debug code into the debug addon

- [ ] The settings window lets another addon add a group of sections.
- [ ] The sort engine gets small hooks (a sort started, a sort finished, a frame's timing), so the frame-time
      tracking can live outside it.
- [ ] Move into the debug addon: the test bench (scrambles, recent sorts, the status line under the bag's
      search box), frame-time tracking, the Testing, Tools and Files sections, Scan bags, Mute test, Auto-sort
      status.
- [ ] The main addon keeps only what players use. `dev/files_check.lua` covers both `.toc` files.
- [ ] All checks pass; the user tries it in game; commit.

## Phase 4: the Ordering list becomes the data

- [ ] New saved format: the Ordering as an ordered list of entries, the Empty Space being one of them; an
      entry can hold more than one rule (Quest Items holds the quest flag and the Quest group). An item entry
      also keeps the item's name (and icon), updated whenever the game tells us the name. Keep out of special
      bags as today. History saves hold the same list, names included.
- [ ] An item's place = the position of the entry that decides it (most specific match: item, flag,
      group/part, group). Above the Empty Space packs from the top, below it from the bottom; items not
      ordered yet stay next to the Empty Space, as today. Ties inside an entry keep today's order (class,
      group/part, item, bigger stack first).
- [ ] **Equivalence check before deleting anything:** a dev check that runs the old code (kept in dev/ only)
      and the new code on thousands of random rule sets and real bag scans, and requires the same item
      order every time.
- [ ] Move onto the list: Ordering (drag, x and Undo, Select Mode adds, "Sort X as"), Start Fresh's default
      order, the popup (what decides, Add), History (save, Load, summary, tooltip).
- [ ] Remove: weight numbers, `sinkLine`, renumbering after every move, the tie and Empty Space special
      cases that numbers needed, every migration and old-layout conversion, the clearing of retired
      settings.
- [ ] The simulator and checks move to the new format (resolve, ranking, rules, the click-through test).
- [ ] All checks pass; the user tries it in game; commit.

## Phase 5: the converter (dev script, not in the addon)

- [ ] `dev/convert_save` (Lua, since the save file is Lua; Python works too): reads the old
      `SavedVariables/SedimentSort.lua` and writes the new addon's saved settings file.
- [ ] Converts: the rules into the Ordering list, Keep out of special bags, every History save (with its
      pin, Active and Previous), the Timing values, the fill switch, the settings window's position. Item
      names aren't in old saves; the addon fills them in as the game loads the items.
- [ ] Backs up the old file first; refuses to run while the game is running (the game writes saves when it
      exits and would overwrite the result).
- [ ] A check: a converted save loads, and its Ordering matches the old one entry for entry.

## Phase 6: comments and docs

- [ ] Comments say what the code does and why; the dated conversation notes move into NOTES.md.
- [ ] README (name, install, the debug addon), NOTES.md (How it works, version log), TODO.md (done items out).
- [ ] All checks pass; commit.

## Phase 7: switch over

- [ ] Close the game; back up the WTF saves; run the converter.
- [ ] Remove the old `AddOns/SedimentSort` and `AddOns/SedimentSort_Debug` links.
- [ ] Merge `disorder` into `main` and push; remove the second checkout.
- [ ] Rename the repo folder and point the AddOns links at it.
- [ ] Rename the GitHub repo (the user, on GitHub; the old address keeps redirecting) and update the remote.
- [ ] Start the game and check everything once more.

## Risks

- Both addons enabled at once: they fight over the bags. Only one at a time.
- The new data placing an item differently from the old: caught by the equivalence check in Phase 4.
- Things only the game shows (frames, events, timing): the user tries it in game after every phase.
- Converting a save while the game runs: the game overwrites it on exit. The converter checks for that.

## The Disorder family (idea, not part of this plan)

The user's other addons could share the brand: Disorder - Item Manager (this one), Disorder - Quest Tracker
(Marquee), Disorder - Vendor Filter, Disorder - Pet Manager (CheapFeed, Name Hider). Each stays its own addon
(folder, saved settings, repo). Later, possibly: a shared look (the words and colour conventions in Text.lua),
and one Disorder settings window where each installed addon adds its own group of sections (the same
mechanism Phase 3 builds for the debug addon).
