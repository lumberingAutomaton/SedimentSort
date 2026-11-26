# Sediment

A bag sort for World of Warcraft: Forever. Every item has a **Weight**: light items float to the top of
your bags, heavy items sink to the bottom, and the **Empty Space** stays in the middle, where new loot lands.
While your bags are closed, **Sediment** keeps them in order quietly in the background.

Writing convention, here and in the game: **Sediment**'s own nouns
(**Sediment**, **Weight**, **Order**, **History**, **Pinned**, **Empty Space**) are bold here and
sand-coloured in the game; button names are `in code style` here and gold in the game. "Rules" always means
your whole set: all your **Weights** plus what you keep out of special bags.

## Getting started

Click the gear next to the bag's sort button (or type `/sed`): the settings open at **Order**, beside your
bags. The first time, a short welcome covers the list; press `Start Fresh` to begin from a common layout you
can rearrange: Hearthstone, Consumable/Potions, Consumable/Bandages, Consumable, Quest Items, BoE Gear (and
any other kind of item in your bags), the **Empty Space**, then Weapon, Armor, Trade Goods, Miscellaneous
and Gray Quality last. `Start Fresh` saves any rules you had to **History** first, clears them (Keep out of
special bags too), adds a Created entry for the new layout, and turns on Blizzard's Combined Backpack if
it's off (**Sediment** sorts in that window's order). The ? next to the settings title brings the welcome back.

**Order** lists your rules, top to bottom the way your bags sort, with the **Empty Space** among them. Drag a
row to move it: by the grip at its left, which picks it up as soon as you press, or anywhere on it once
the mouse moves a little. Clicking a row outlines its items in your bags, and your bags sort on every
change. The **Empty Space** moves the same way, and where you put it decides the layout:
- at the top: everything packs toward the bottom of your bags;
- at the bottom: everything packs from the top, like a normal bag sort;
- in between: what's above it floats to the top, what's below it sinks to the bottom, and the gap is in the
  middle, where new loot lands.

Anything not set yet stays next to the **Empty Space** and is outlined orange (the line above the list says
how many); select the **Empty Space** to see those items in gold. x removes a row; it stays greyed with
`Undo` until the list changes again or you leave the section.

`Pick from Bags` is on whenever **Order** shows its list; its button turns it off until you next open
**Order**. While it's on, hovering an item in your bags lights up the row that sorts it, and clicking an
item gives it its own row, right above the row that sorts it now, ready to move. Alt+right-click still opens
the **Weight** popup.

The column right of the list offers wider ways to sort the selected row, e.g. "Sort Mageweave Cloth as:"
`Trade Goods/Cloth`, `Trade Goods`, or `BoE Gear` for a BoE item; a group/part row offers its whole group.
Choosing one replaces the row with that one, or joins it to that row if it's already in the list; either
way, everything it covers sorts there. Hover a choice to see what it would cover.

Alt+right-click on any bag item opens its **Weight** popup: "Sorted as BoE Gear", naming the row in
**Order** it sorts with, without opening **Order**. It lists what applies to the item, most specific first:
the item itself, its flags (Equipment Set, Quest Items, Gray Quality, BoE Gear), its group/part, its group.
The one that decides is marked `wins`;
the most specific one with a row in **Order** always wins. Each level above it has `Add`, which gives that
level a row right above the deciding row, so it takes over and your bags sort. The levels below the winner
can't change this item, so they have no button. `Settings` opens **Order** with the deciding row selected.
The popup always opens just above your bag window and draws over the settings window.

## How it sorts

**Sediment** starts with no rules: until you add some, it sorts your bags by item type, like an ordinary
bag sort. Rules are how you make the order yours.

Each item's **Weight** comes from the most specific rule that has one:
1. a **Weight** for that exact item (for example, Hearthstone 0, so it's always first),
2. a flag, checked in this order: Equipment set, Quest item, Gray quality, BoE gear (equippable and not
   soulbound yet),
3. its subclass (for example, Potions),
4. its class (for example, Consumable),
5. the default **Weight**.

The **Empty Space** is where new loot lands. Rules above it float to the top, rules below it sink to the
bottom; in **Order** you drag it like any row.

Special bags: a reagent bag holds crafting reagents, and a profession bag (herb, mining, soul, ...) holds
what it accepts, wherever it sits. Items that belong there are moved in, and each special bag is sorted on
its own. To keep things out, Alt+right-click one and, under Keep out of special bags, tick "all Cloth"
(every cloth) or just that item (e.g. "Silk Cloth"); ones already in a special bag move back out. The Special
bags section in the settings lists every such rule (x removes one, with `Undo`) and has a switch to stop
filling special bags at all.

Equipment sets stay together, and identical stacks always sit side by side, with the partial stack last.
Every normal bag is sorted: Blizzard's per-bag "Ignore cleanup" option is ignored.

## Sorting

- The sort button in the bag does a full sort: the exact order, the same result every time. **Sediment**
  takes this button over from the built-in sort. Right-click it to turn auto-sort on or off (the button
  greys out while it's off).
- Auto-sort (on by default) only runs while the bags are closed, about a second after they change. It
  moves a few items at a time so the frame rate stays steady, and by default sorts to the same exact order
  as the button. Opening your bags mid-sort finishes it at once (or, if you choose, pauses it until they
  close). It never runs in combat or while a vendor, bank, mail, trade, auction or guild bank window is open.
- Sorting is silent (the item clinks are muted), and a cooldown sweep on the sort button and the backpack
  button shows a sort in progress.

## Settings

The settings window lists its sections on the left, like WoW's own Options window; the Debug group only
appears in debug mode. It closes in combat, along with everything else **Sediment** opens, so a click in
combat always does what you expect.

### Order
The list described above.

### Special bags
The special bags you have; Fill reagent and profession bags automatically (off: nothing is moved in, what's
there stays and is still sorted); and everything kept out of special bags (all Cloth, Silk Cloth, ...),
with x to remove (`Undo` puts it back).

### Sorting
You shouldn't need it: the defaults are auto-sort on, Full order, wait 1.1 seconds, smoothness 0.3, and
`Finish Now` when the bags open mid-sort. Here you can change them: auto-sort on/off; its order (`Full`:
the exact order, like the sort button, or `Partial`: only what the **Weights** require, fewest moves); how
long it waits after changes; how smoothly it runs; and whether opening the bags mid-sort finishes it at
once or pauses it. Debug mode reveals two more sections (below).

### History
A safety net of your rules (**Weights**, the **Empty Space**, default and Keep out of special bags; not the sorting
options), newest first. Two kinds of entry, titled like "Rook — Snapshot — Nov 25, 10:32" (the character
you were on):
- **Created**: added when `Start Fresh` lays out a new order.
- **Snapshot**: taken automatically when you log out (or `/reload`), and before `Load` or `Start Fresh`, but
  only if your rules have changed since they were last in **History**.

Each entry has `Pin` / `Unpin` on the left, and `Load` and x on the right. `Load` needs no confirmation:
your current rules get a Snapshot first if they aren't saved, so it can be undone. x greys the entry out
with `Undo` until you close the window. One entry can be **Pinned**: it stays at the top and is never
dropped. Of the rest, the newest 20 are kept. Hover an entry to see its rules. **Active** marks the entry
holding the rules you're using; **Previous** marks the one you were using before, which is what you'd go
back to.

### Testing (debug mode)
Scramble the bags with a seed (Drift, Minimal, Full or Maximal; the same seed on the same sorted bag makes
the same mess), then let auto-sort clean up. An optional one-line status text under the bag's search box
shows what the last sort cost (hover for details), and the section lists recent sorts.

### Commands (debug mode)
Every `/sed` command and mouse shortcut.

### Files (debug mode)
The version the game read from the addon's `.toc`, and every file **Sediment** expects, each marked loaded
or missing. A missing file usually means the game needs a full restart.

## Commands

| Command | What it does |
|---|---|
| `/sed` | Open the settings at your **Order** (also /sed config, /sed settings). |
| `/sed sort` | Sort the bags now, the same as clicking the sort button. |
| `/sed cancel` | Stop a sort that's running. |
| `/sed auto` | Turn auto-sort on or off (or right-click the sort button). |
| `/sed status` | What auto-sort is waiting for, and what the last sort cost (also /sed auto?). |
| `/sed delay [seconds]` | Show or set how long auto-sort waits after the bags change. |
| `/sed budget [ms]` | Show or set auto-sort's smoothness: time per frame it may spend moving items. |
| `/sed why` | Hover a bag item, then run this: its **Weight** rules in chat. |
| `/sed bench` | Open the Testing section (needs debug mode). |
| `/sed scan` | List every item's class, subclass, quality and flags in chat. |
| `/sed mutetest` | Mute the item pick-up/put-down sounds for 15 seconds, to check muting works. |
| `/sed help` | List these commands in chat. |

| Mouse | What it does |
|---|---|
| Sort button | Left-click: sort now. Right-click: turn auto-sort on or off. |
| Gear button | Next to the sort button: the settings at your **Order**. |
| Alt+right-click | On any bag item: its **Weight** popup. |

## Install

Put this folder in `World of Warcraft/_forever_/Interface/AddOns/` (copy or symlink) as `SedimentSort`,
which is what cloning this repo gives you: WoW only loads an addon whose folder matches its `.toc` name
(`SedimentSort.toc`). It shows as "Sediment" in the game. After updating, a `/reload` is enough (checked on
Forever, 2026-11-25, with a newly added file). If the settings' Debug > Files section ever shows a file as
missing, restart the game client.

## Development

`NOTES.md` holds the design notes, decisions and to-do list. `dev/` holds offline tools, not loaded by
the game:

- `Text.lua` (in the addon): every word for one of **Sediment**'s own things and every button label, under
  keys named for their role. Change a word there and nowhere else. `dev/text_check.lua` checks every key
  the code uses is defined (and every defined one is used).
- `dev/files_check.lua`: the file list behind Debug > Files and the login check matches the `.toc`, and
  every file marks itself loaded.
- `dev/check_globals.sh`: run after every change; fails on any global that isn't a known WoW API or
  Sediment's own (catches a local declared below the function that uses it).
- `dev/sim.lua`: runs the real sort code against mocked game APIs, using a saved `/sed scan`:
  `lua dev/sim.lua <SavedVariables/SedimentSort.lua> [seed] [show|bench]`. `SEDIMENT_AUTO=full` makes
  auto-sort use the full order; `SEDIMENT_MEASURE=1` compares plans with the proven minimum swaps.
- `dev/min_swaps.lua`: the proven-minimum swap solver used by that measurement.
- `dev/resolve_check.lua`: checks the fast weight lookup against the full rule cascade.
- `dev/rules_check.lua`: new installs start empty on the Full order, older saves migrate once, and
  **History** (saving, no duplicates, loading, naming, the 20-version limit, the login version) behaves.
- `dev/ranking_check.lua`: the order behind the **Order** list: the default layout, moving rows and the
  **Empty Space**, unset items attached to it, old saves converting, ties kept.
- `dev/setup_check.lua`: clicks through the settings against mocked frames: the **Order** section (welcome,
  `Start Fresh`, outlines, moves, the **Empty Space**, unset items, x with `Undo`, `Pick from Bags` and widen,
  drag and drop), **History**, Special bags and Debug > Files.
