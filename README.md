# Sediment

A bag sort for **World of Warcraft: Forever**. Every item has a weight: light items float to the top of
your bags, heavy items sink to the bottom, and the free space stays in the middle, where new loot lands.
While your bags are closed, Sediment keeps them in order quietly in the background.

## Getting started

Open the settings with the **gear** next to the bag's sort button (or `/sed`). The first time, the
**setup questions** come up: a page on what Sediment does, then a few questions that set it up for what's
in your bags now. Each answer sorts your bags right away, so you see what it does:

1. Where you want the empty space: in the middle (things float up or sink down), at the bottom
   (everything packed from the top, like a normal sort) or at the top.
2. Your hearthstone first or last, and anything you want next to it (click items in your bags, in order).
3. Gray junk and trade goods: float or sink (or "higher up / lower down" if your space isn't in the middle).
4. If you have them: equipment set items, BoE gear, spare bags, quest items.
5. Each kind of item in your bags that still has no rule, the one covering the most items first. **Split
   this up** asks about its subkinds instead (Consumable: Potions, Food & Drink, ...).
6. A review: every rule top to bottom, with the empty space marked; click a row and move it up or down.

**Back** undoes the previous answer, **Skip** leaves a question unanswered, **Finish later** keeps your
place, and **Start over** clears your rules and asks everything again. While the questions are open, items
not set yet are outlined orange in your bags, and the ones the current question is about gold. Your rules
are saved to **History** before you start (and when you finish), so you can always go back. The **?** next
to the settings title brings the questions back any time.

To change things later: on the **Weights** section, turn **Select mode** on (it opens your bags) and click
items in them. Each slot shows its current weight (orange means it's using the default); clicking an item
opens its weight popup. Lower numbers float, higher numbers sink. **Alt+right-click** any bag item opens
the same popup without the settings window.

## How it sorts

Sediment starts with no rules: until you add some, it sorts your bags by item type, like an ordinary bag
sort. Rules are how you make the order yours.

- **Weights.** Each item's weight comes from the most specific rule that has one:
  1. a weight for that exact item (for example, Hearthstone 0, so it's always first),
  2. a flag, checked in this order: **Equipment set**, **Quest item**, **Gray quality**, **BoE gear**
     (equippable and not soulbound yet),
  3. its subclass (for example, Potions),
  4. its class (for example, Consumable),
  5. the default weight.
- **Sink line.** Items lighter than the sink line pack from the top; items at or above it pack from
  the bottom.
- **Special bags.** A reagent bag holds crafting reagents, and a profession bag (herb, mining, soul, ...)
  holds what it accepts, wherever it sits. Items that belong there are moved in, and each special bag is
  sorted on its own. To keep things out, Alt+right-click one and, under **Keep in my normal bags**, tick
  **all Cloth** (its whole kind) or just that item (e.g. **Silk Cloth**); ones already in a special bag move
  back out. The **Special bags** section in the settings lists every such rule (x removes one, with Undo)
  and has a switch to stop filling special bags at all.
- **Equipment sets** stay together, and identical stacks always sit side by side, with the partial
  stack last.
- Every normal bag is sorted: Blizzard's per-bag "Ignore cleanup" option is ignored.

## Sorting

- **The sort button** in the bag does a full sort: the exact order, the same result every time.
  Sediment takes this button over from the built-in sort. Right-click it to turn auto-sort on or off
  (the button greys out while it's off).
- **Auto-sort** (on by default) only runs while the bags are closed, about a second after they change.
  By default it moves only what the weights require, a few items at a time so the frame rate stays
  steady. Opening your bags pauses it (or, if you choose, finishes it at once). It never runs in combat
  or while a vendor, bank, mail, trade, auction or guild bank window is open.
- Sorting is silent (the item clinks are muted), and a cooldown sweep on the sort button and the
  backpack button shows a sort in progress.

## Settings

The settings window lists its sections on the left, like WoW's own Options window; the Debug group only
appears in debug mode. It closes in combat, along with everything else Sediment opens, so a click in combat
always does what you expect.

- **Weights:** Select mode (above), and every weight you've set, light to heavy, with the sink line
  drawn across. Edit numbers in place; x removes a rule (with Undo); Escape cancels an edit. **Not set**
  lists the categories in your bags that still use the default. **Reset to default** removes all rules
  (it asks first and saves them to History; **Restore previous rules** loads the most recent other version).
- **Sorting:** auto-sort on/off; its order (**Partial**: only what the weights require, fewest moves, or
  **Full**: the exact order, like the sort button); how long it waits after changes; how smoothly it
  runs; and whether opening the bags mid-sort pauses it or finishes it at once. **Debug mode** reveals
  two more sections:
- **Special bags:** the special bags you have; **Fill reagent and profession bags automatically**
  (off: nothing is moved in, what's there stays and is still sorted); and everything you keep in your
  normal bags (all Cloth, Silk Cloth, ...), with x to remove (Undo puts it back).
- **History:** saved versions of your rules (weights, sink line, default and keep-out rules; not the
  sorting options), newest first. One is saved before anything replaces your rules (Reset to default,
  the setup questions, loading a version), when you finish the setup questions, and when you log in if
  your rules changed (labelled with the character, e.g. "Thrall login"); **Save a copy** saves one now, with an optional name. Each version has **Load**
  (your current rules are saved first, so it can be undone), **Name** and **x**; hover one to see its
  rules. The newest 20 are kept, and named ones (marked "kept") until you delete them.
- **Testing** (debug mode): scramble the bags with a seed (Drift, Minimal, Full or Maximal; the same
  seed on the same sorted bag makes the same mess), then let auto-sort clean up. An optional one-line
  status text under the bag's search box shows what the last sort cost (hover for details), and the section
  lists recent sorts.
- **Commands** (debug mode): every `/sed` command and mouse shortcut.

## Commands

| Command | What it does |
|---|---|
| `/sed` | Open the settings window (also /sed config, /sed settings). |
| `/sed sort` | Sort the bags now, the same as clicking the sort button. |
| `/sed cancel` | Stop a sort that's running. |
| `/sed auto` | Turn auto-sort on or off (or right-click the sort button). |
| `/sed status` | What auto-sort is waiting for, and what the last sort cost (also /sed auto?). |
| `/sed delay [seconds]` | Show or set how long auto-sort waits after the bags change. |
| `/sed budget [ms]` | Show or set auto-sort's smoothness: time per frame it may spend moving items. |
| `/sed why` | Hover a bag item, then run this: its weight rules in chat. |
| `/sed bench` | Open the Testing section (needs debug mode). |
| `/sed scan` | List every item's class, subclass, quality and flags in chat. |
| `/sed mutetest` | Mute the item pick-up/put-down sounds for 15 seconds, to check muting works. |
| `/sed help` | List these commands in chat. |

| Mouse | What it does |
|---|---|
| Sort button | Left-click: sort now. Right-click: turn auto-sort on or off. |
| Gear button | Open the settings window (next to the sort button). |
| Alt+right-click | On any bag item: its weight popup. |

## Install

Put this folder in `World of Warcraft/_forever_/Interface/AddOns/` (copy or symlink) as `SedimentSort`,
which is what cloning this repo gives you: WoW only loads an addon whose folder matches its `.toc` name
(`SedimentSort.toc`). It shows as "Sediment" in the game. After adding or updating files, restart the
game client: a `/reload` doesn't pick up new files.

## Development

`NOTES.md` holds the design notes, decisions and to-do list. `dev/` holds offline tools, not loaded by
the game:

- `dev/check_globals.sh`: run after every change; fails on any global that isn't a known WoW API or
  Sediment's own (catches a local declared below the function that uses it).
- `dev/sim.lua`: runs the real sort code against mocked game APIs, using a saved `/sed scan`:
  `lua dev/sim.lua <SavedVariables/SedimentSort.lua> [seed] [show|bench]`. `SEDIMENT_AUTO=full` makes
  auto-sort use the full order; `SEDIMENT_MEASURE=1` compares plans with the proven minimum swaps.
- `dev/min_swaps.lua`: the proven-minimum swap solver used by that measurement.
- `dev/resolve_check.lua`: checks the fast weight lookup against the full rule cascade.
- `dev/rules_check.lua`: new installs start empty on the Full order, older saves migrate once, and
  History (saving, no duplicates, loading, naming, the 20-version limit, the login version) behaves.
- `dev/ranking_check.lua`: the order the setup questions work in: where each answer lands, weights on the
  right side of the sink line in every layout, ties kept.
- `dev/setup_check.lua`: clicks through the setup questions against mocked frames (every question type,
  Back, Skip, Split, Finish later, Start over, the review's moves, Done, the slot highlights) and the
  History section.
