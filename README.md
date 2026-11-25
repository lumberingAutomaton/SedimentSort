# Sediment

A bag sort for World of Warcraft: Forever. Every item has a **Weight**: light items float to the top of
your bags, heavy items sink to the bottom, and the **Empty Space** stays in the middle, where new loot lands.
While your bags are closed, **Sediment** keeps them in order quietly in the background.

Writing convention, here and in the game: **Sediment**'s own nouns
(**Sediment**, **Weight**, **Select Mode**, **Setup**, **History**, **Pinned**, **Empty Space**) are bold here and
sand-coloured in the game; button names are `in code style` here and gold in the game. "Rules" always means
your whole set: all your **Weights** plus what you keep out of special bags.

## Getting started

Click the gear next to the bag's sort button (or type `/sed`). While you have no rules, or haven't finished
setting up, it opens **Setup**: a page on what **Sediment** does, then a few questions about what's in your
bags now. After that, the gear opens the settings at your **Weights**. Each answer sorts your bags right
away, so you see what it does:

1. Where you want the **Empty Space**: in the middle (things float up or sink down), at the bottom
   (everything packed from the top, like a normal sort) or at the top.
2. Your hearthstone first or last, and anything you want next to it (click items in your bags, the one you
   want right beside it first).
3. Gray junk and trade goods: float or sink (or higher up / lower down if your space isn't in the middle).
4. If you have them: equipment set items, BoE gear, spare bags, quest items.
5. A question for each part of your bags that's still not set (Consumable, Weapon, ...), biggest first.
   `Split This Up` asks about its parts instead (Consumable: Potions, Food & Drink, ...).
6. A review: everything you've set, top to bottom, with the **Empty Space** marked; click a row, then
   `Move Up` or `Move Down`.

The first page always has the same two buttons. `Start Fresh` saves your rules to **History** (if you have
any), clears them all (**Weights** and Keep out of special bags) and asks everything. `Continue` keeps your
rules: it carries on where you left off, or asks only about what isn't set yet. A line above them says
which applies, and `Continue` is greyed out until there's something to continue. Either one turns on
Blizzard's Combined Backpack if it's off (**Sediment** sorts in that window's order) and says so.

`Back` undoes the previous answer, `Skip` leaves a question unanswered, and `Finish Later` keeps your place
(`Continue` picks it up again). While **Setup** is open, items not set yet are outlined orange in your bags,
and the ones the current question is about gold. Your rules are saved to **History** before you start and
when you finish, so you can always go back. The ? next to the settings title brings **Setup** back any time.

To change things later: in **Weights**, click `Select Mode: off` to enter **Select Mode** (it opens your
bags), then click items in them. Each slot shows its current **Weight** (orange means not set yet);
clicking an item opens its **Weight** popup. Lower numbers float, higher numbers sink. Alt+right-click on
any bag item opens the same popup without the settings window.

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

The **Empty Space** is where new loot lands. It has a number too: items with a **Weight** below it pack from
the top, items at or above it pack from the bottom, so the gap sits between them.

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

### Weights
**Select Mode** (above), and every **Weight** you've set, light to heavy, with the **Empty Space** drawn
across (edit its number to move it).
Edit numbers in place; x removes a **Weight** (with `Undo`); Escape cancels an edit. "Not set" lists what
in your bags still uses the default. `Start Fresh` asks first, then saves your rules to **History**, clears
them and opens **Setup**. To go back to earlier rules, `Load` them in **History**.

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
- **Created**: added when you finish **Setup**.
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
| `/sed` | Open the settings at your **Weights**, or **Setup** while you have no rules (also /sed config, /sed settings). |
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
| Gear button | Next to the sort button: the settings at your **Weights**, or **Setup** while you have no rules. |
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
- `dev/ranking_check.lua`: the order **Setup** works in: where each answer lands, weights on the
  right side of the **Empty Space** in every layout, ties kept.
- `dev/setup_check.lua`: clicks through **Setup** against mocked frames (every question type,
  Back, Skip, Split, Finish Later, Start Fresh / Continue, Combined Backpack, the review's moves, Done, the
  slot highlights) and the
  History section.
