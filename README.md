# Sediment

A bag sort for **World of Warcraft: Forever**. Every item has a weight: light items float to the top of
your bags, heavy items sink to the bottom, and the free space stays in the middle, where new loot lands.

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
  holds what it accepts. Items that belong there are moved in, and each special bag is sorted on its own.
- **Equipment sets** stay together, and identical stacks always sit side by side, with the partial
  stack last.

## Sorting

- **The sort button** in the bag does a full sort: the exact order, the same result every time.
  Sediment takes this button over from the built-in sort.
- **Auto-sort** (on by default) keeps the bags sorted by itself, but only while they're closed. A
  second after your bags change, it sorts quietly, moving only what the weights require.
  Opening your bags pauses it; it finishes when you close them. It never runs in combat or while a
  vendor, bank, mail, trade or auction window is open. Right-click the sort button to turn it on or off
  (the button greys out while it's off).
- Sorting is silent (the item clinks are muted), and a cooldown sweep on the sort button and the
  backpack button shows a sort in progress.

## Setting weights

- **Alt+right-click** any bag item: a popup shows every rule that applies to it, which one wins, and
  lets you edit any of them. Clear a box to let that rule inherit.
- **`/sed`** (or **Settings** in that popup) opens the settings window:
  - **Ladder:** every weight you've set, light to heavy, with the sink line drawn across. Edit in
    place; x clears a rule. **Not set** lists the categories in your bags that still use the default.
  - **General:** auto-sort on/off, how long it waits, how smoothly it runs, the sink line, the default
    weight, and a reset to the starter weights.

## Commands

| Command | What it does |
|---|---|
| `/sed` | Open the settings window |
| `/sed sort` / `/sed cancel` | Sort now / stop a sort |
| `/sed auto` | Turn auto-sort on or off |
| `/sed status` | What auto-sort is waiting for, and what the last sort cost |
| `/sed delay [seconds]` | Show or set auto-sort's wait |
| `/sed budget [ms]` | Show or set auto-sort's smoothness (lower is smoother) |
| `/sed why` | Hover an item, then run this: its weight rules in chat |
| `/sed help` | List commands |

## Test bench

The small dice button next to the sort button opens a test bench: scramble the bags (Drift, Minimal,
Full or Maximal) with a seed, so the same mess can be repeated, then let auto-sort clean up. A one-line
readout under the bag's search box shows what the last sort cost; hover it for details. Useful for
comparing changes; not needed for normal play.

## Install

Put this folder in `World of Warcraft/_forever_/Interface/AddOns/` (copy or symlink) as `SedimentSort`,
which is what cloning this repo gives you: WoW only loads an addon whose folder matches its `.toc` name
(`SedimentSort.toc`). It shows as "Sediment" in the game. After adding or updating files, restart the
game client: a `/reload` doesn't pick up new files.

`NOTES.md` holds the design notes and to-do list; `dev/` holds offline tests (not loaded by the game).
