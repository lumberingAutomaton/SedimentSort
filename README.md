# Disorder - Item Manager

A bag sort for World of Warcraft: Forever that keeps your bags in your own order, by itself. You rank the
kinds of items you carry from top to bottom, and put the **Empty Space** where new loot should land. Whenever
your bags are closed, **Disorder** quietly puts everything where it belongs.

Writing convention, here and in the game: **Disorder**'s own nouns (**Disorder**, **Ordering**, **Select
Mode**, **History**, **Pinned**, **Empty Space**) are bold here and sand-coloured in the game; button names
are `in code style` here and gold in the game. "Rules" always means your whole set: your **Ordering** plus
what you keep out of special bags.

## 1. Sorting

This is the point of **Disorder**: your bags sort themselves.

- **Auto-sort is always on.** About a second after your bags change (loot, crafting, using something up),
  and only while they're closed, **Disorder** sorts them. It moves a few items per frame so the game stays
  smooth. If you open your bags while it's running, it finishes at full speed right away.
- **It waits** while you're in combat (a sort that's running stops at once and finishes afterwards), while
  an item is on your cursor, and while a vendor, bank, mail, trade, auction or guild bank window is open.
- **The sort button** in the bag sorts right now, at full speed. **Disorder** takes it over from the built-in
  sort. Clicking it again during a sort cancels that sort.
- **Every sort uses the same exact order**, so every item always has the same spot. Identical stacks sit
  side by side with the partial stack last, and equipment sets stay together. Every normal bag is sorted:
  Blizzard's per-bag "Ignore cleanup" option is ignored.
- **It's quiet:** the item clinks are muted while it sorts, and a cooldown sweep on the sort button and the
  backpack button shows it working.

The gear next to the sort button, or `/dim`, opens the settings at your **Ordering**. The settings window
closes in combat, along with everything else **Disorder** opens, so a click in combat always does what you
expect.

## 2. Ordering

Where you decide the order. The settings open here, next to your bags.

**Getting started.** The first time you open it, the list starts with three entries: Hearthstone, the
**Empty Space**, and Gray Quality. Everything else isn't ordered yet and sorts by type next to the **Empty
Space**, so your bags look much like WoW's own sort: Hearthstone first, junk last. It also turns on
Blizzard's Combined Backpack if it's off (**Disorder** sorts in that window's order). From there, add the
things you care about (see Select Mode below) and drag them where you want them; your bags sort as you go.

`Start Fresh`, at the bottom, goes back to those three entries whenever you like. It asks first, saves your
rules to **History**, clears them (Keep out of special bags too), and adds a Created entry.

**The list** shows your **Ordering** top to bottom, the way your bags sort, with the **Empty Space** among
the entries. Drag an entry to move it: press anywhere on it and move the mouse. Click one to outline its
items in your bags in gold. Your bags sort on every change. x removes an entry; it stays greyed with `Undo`
until you leave **Ordering**, right below the entry that was above it, wherever that entry moves. `Undo`
puts it back there.

**The Empty Space** moves the same way, and where you put it decides the layout:
- at the top: everything packs toward the bottom of your bags;
- at the bottom: everything packs from the top, like a normal bag sort;
- in between: what's above it goes to the top, what's below it goes to the bottom, and the gap is in the
  middle, where new loot lands.

Items that aren't ordered yet stay next to the **Empty Space** and are outlined orange; the line above the
list says how many. Select the **Empty Space** to see them in gold.

**Select Mode** is on whenever the list shows; its button, `Select Mode: On`, turns it off until you next
open **Ordering**. While it's on, hovering an item in your bags lights up the entry that sorts it, and
clicking an item gives it an entry of its own, right above the one that sorts it now, ready to move.
Alt+right-click still opens the ordering popup.

**Wider choices.** The column right of the list offers wider ways to sort the selected entry, e.g. "Sort
Mageweave Cloth as:" `Trade Goods/Cloth`, `Trade Goods`, or `BoE Gear` for a BoE item; a group/part
offers its whole group. Choosing one replaces the entry, or joins it to that entry if it's already in the
list; either way, everything it covers sorts there. Hover a choice to see what it would cover.

**How an item finds its place.** With nothing ordered, **Disorder** sorts by item type, like an ordinary bag
sort. Otherwise each item sorts with the most specific entry in your **Ordering** that matches it:
1. that exact item (for example, Hearthstone);
2. a flag, checked in this order: Equipment Set, Quest Items, Gray Quality, BoE Gear (equippable and not
   soulbound yet);
3. its group/part (for example, Consumable/Potions);
4. its group (for example, Consumable).

## 3. The ordering popup

Alt+right-click any bag item: a small window opens just above your bags and says how that item sorts, for
example "Sorted as BoE Gear", naming the entry in your **Ordering**. Below that, everything that applies to
the item, most specific first: the item itself, its flags, its group/part, its group. The one that decides
is marked `wins`. Each one above it has `Add`, which gives it an entry right above the deciding one, so it
takes over and your bags sort; the ones below it can't change this item, so they have no button. For items a
special bag would take, it also has the Keep out of special bags checkboxes. `Settings` opens **Ordering**
with the deciding entry selected.

## 4. Options

**Timing.** Two numbers, and the defaults should suit nearly everyone:
- **Wait after changes:** how long your bags must be quiet before they sort (default 1.1 seconds), long
  enough for a burst of looting to finish and new quest items to register.
- **Smoothness:** how much time per frame, on average, sorting may spend moving items while your bags are
  closed (default 0.3 ms). Lower is smoother but slower. The sort button always goes full speed.

**Special bags.** A reagent bag holds crafting reagents, and a profession bag (herb, mining, soul, ...) holds what it accepts,
wherever it sits. Items that belong there are moved in, and each special bag is sorted on its own.

To keep something out, Alt+right-click it and, under Keep out of special bags, tick its group/part (every
cloth) or just that item (e.g. Silk Cloth); ones already in a special bag move back out. Options lists the special
bags you have, every keep-out rule (x removes one, with `Undo`), and a switch,
Fill reagent and profession bags automatically. Off: nothing is moved in; what's already there stays and is
still sorted.

## 5. History

A safety net of your rules (your **Ordering**, the **Empty Space** and Keep out of special bags; not
Options), newest first, each with a short summary like "24 ordered, 1 kept out". Two kinds of entry, titled
like "Rook — Snapshot — Nov 25, 10:32" (the character you were on):
- **Created**: added when `Start Fresh` lays out a new order.
- **Snapshot**: taken automatically when you log out (or `/reload`), and before `Load` or `Start Fresh`, but
  only if your rules have changed since they were last in **History**.

Each entry has `Pin` / `Unpin` on the left, and `Load` and x on the right. `Load` needs no confirmation:
your current rules get a Snapshot first if they aren't saved, so it can be undone. x greys the entry out
with `Undo` until you close the window. One entry can be **Pinned**: it stays at the top and is never
dropped. Of the rest, the newest 20 are kept. Hover an entry to see its rules. **Active** marks the entry
holding the rules you're using; **Previous** marks the one you were using before, which is what you'd go
back to.

## Install

Put this folder in `World of Warcraft/_forever_/Interface/AddOns/` (copy or symlink) as
`Disorder_ItemManager`: WoW only loads an addon whose folder matches its `.toc` name
(`Disorder_ItemManager.toc`). It shows as "Disorder - Item Manager" in the AddOns list and as "Disorder" in
the game. After updating, a `/reload` is enough (checked on
Forever, 2026-11-25, with a newly added file). A brand-new addon folder needs a full restart of the game.

## For developers

`NOTES.md` holds findings, design records, research and test results; `TODO.md` is the parking lot (what to
build next, ideas waiting for a decision); `PLAN.md` is the restructure in progress.

**The files**, one per feature, in load order: `Text.lua` (the words), `Rules.lua` (the rules and how an item
finds its place, and History's saves for now), `Bags.lua` (reading the bags and special bags), `Sound.lua`,
`Sort.lua` (the sort engine), `AutoSort.lua`, `Settings.lua` (the window, its section list and shared
helpers; each section registers itself), `Overlays.lua` (Select Mode and the outlines), `Popup.lua` (the
ordering popup), `Ordering.lua`, `Options.lua` (Timing and Special bags), `History.lua`, `Debug.lua` (the Debug
group and test bench, until it moves into the debug addon), `SortButton.lua` (the sort button, the gear, the
progress sweep), `Core.lua` (start-up, events, `/dim`).

**The debug addon.** `Disorder_ItemManager_Debug/` is a second addon, installed as its own folder
(`AddOns/Disorder_ItemManager_Debug`, copy or symlink; restart the game the first time). While it's loaded, the
settings show a Debug group; players without it never see any of it:
- **Testing:** scramble the bags with a seed (Drift, Minimal, Full or Maximal; the same seed on the same
  sorted bag makes the same mess), then let auto-sort clean up. An optional status line under the bag's
  search box shows what the last sort cost (hover for details), and the section lists recent sorts.
- **Tools:** `Auto-sort status` (what auto-sort is waiting for, what the last sort cost), `Scan bags` (every
  item's class, subclass, quality, flags and weight in chat, saved for `dev/sim.lua` after a `/reload`),
  `Mute test` (the item sounds muted for 15 seconds), `Cancel sort`.
- **Files:** the version the game read from the `.toc`, and every file **Disorder** expects, each marked
  loaded or missing. A missing file usually means the game needs a full restart.
- **Red overlay on locked items:** any bag item the game has locked gets a red overlay over its whole slot as
  soon as the game reports it, and loses it when it unlocks. A normal move flashes red for a moment; an item that stays red is
  stuck (a move the game never answered; a full restart of the game frees it).

**Words.** `Text.lua` holds every word for one of **Disorder**'s own things and every button label, under
keys named for their role. Change a word there and nowhere else.

**Checks** in `dev/`, not loaded by the game; run them from the addon folder:
- `dev/check_globals.sh`: run after every change; fails on any global that isn't a known WoW API or
  Disorder's own (catches a local declared below the function that uses it).
- `dev/text_check.lua`: every word key the code uses is defined, and every defined one is used.
- `dev/files_check.lua`: the file list behind Debug > Files and the login check matches the `.toc`, and
  every file marks itself loaded.
- `dev/sim.lua`: runs the real sort code against mocked game APIs, using a saved scan:
  `lua dev/sim.lua <SavedVariables/Disorder_ItemManager.lua> [seed] [show|bench]` (scans saved before the
  rename, in `SedimentSort.lua`, work too). `SEDIMENT_MEASURE=1` compares
  plans with the proven minimum swaps (`dev/min_swaps.lua`).
- `dev/resolve_check.lua`: the fast lookup of an item's place against the full rule cascade.
- `dev/rules_check.lua`: new installs start empty, older saves migrate once, retired settings are cleared,
  and **History** (saving, no duplicates, loading, the 20-entry limit) behaves.
- `dev/ranking_check.lua`: the order behind the **Ordering** list: the default layout, moving entries and the
  **Empty Space**, unset items attached to it, old saves converting, ties kept.
- `dev/setup_check.lua`: clicks through the settings against mocked frames: **Ordering** (the first layout, `Start
  Fresh`, outlines, moves, the **Empty Space**, unset items, x with `Undo`, **Select Mode**, wider choices,
  drag and drop), **History**, Options, the Debug group's gating, Tools and Files, and the ordering
  popup.
