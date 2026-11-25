# Sediment

A bag sort for **World of Warcraft: Forever**. Every item has a weight: light items float to the top of
your bags, heavy items sink to the bottom, and the free space stays in the middle, where new loot lands.
While your bags are closed, Sediment keeps them in order quietly in the background.

## Getting started

Open the settings with the **gear** next to the bag's sort button (or `/sed`). The first time, a short
welcome explains the idea; the **?** next to the title brings it back.

Then give your items weights: on the **Weights** tab, turn **Select mode** on (it opens your bags) and
click items in them. Each slot shows its current weight (orange means it's using the default); clicking an item opens
its weight popup. Lower numbers float, higher numbers sink. **Alt+right-click** any bag item opens the
same popup without the settings window.

## How it sorts

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
  back out. To stop filling special bags at all, untick **Fill reagent and profession bags
  automatically** on the Sorting tab.
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

The settings window closes in combat, along with everything else Sediment opens, so a click in combat
always does what you expect.

- **Weights:** Select mode (above), and every weight you've set, light to heavy, with the sink line
  drawn across. Edit numbers in place; x removes a rule (with Undo); Escape cancels an edit. **Not set**
  lists the categories in your bags that still use the default. **Reset to starter weights** asks first.
- **Sorting:** auto-sort on/off; its order (**Partial**: only what the weights require, fewest moves, or
  **Full**: the exact order, like the sort button); how long it waits after changes; how smoothly it
  runs; and whether opening the bags mid-sort pauses it or finishes it at once. **Debug mode** reveals
  two more tabs:
- **Testing** (debug mode): scramble the bags with a seed (Drift, Minimal, Full or Maximal; the same
  seed on the same sorted bag makes the same mess), then let auto-sort clean up. An optional one-line
  status text under the bag's search box shows what the last sort cost (hover for details), and the tab
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
| `/sed bench` | Open the Testing tab (needs debug mode). |
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
