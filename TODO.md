# Sediment: to do

The parking lot: what's agreed to build, and ideas waiting for a decision. Findings, research, test results
and dropped ideas live in NOTES.md. Reviewed with the user 2026-11-26.

## Next (agreed useful)

- **Readable help.** The Order help paragraph is small (GameFontHighlightSmall) and dense; nobody reads it.
  Quick win: a normal-size font. Full answer: a guided tour of callouts, one thing at a time (parked
  2026-11-26; the discussion, suggested steps and open decisions are in NOTES.md, "Idea details: Guided tour").
- **Leftover UI parentheticals** (the user's rule: none without asking). Needs discussion, one by one
  (rechecked 2026-11-26 after 0.20 removed the commands list, /sed why and the Sorting choices):
  - Special bags: "(removed)" after a removed keep-out rule; "none right now (reagent bags and profession
    bags like herb or mining bags)".
  - Timing: "Wait after changes (seconds)", "Smoothness (ms per frame)".
  - History: "(deleted)" after a save marked with x.
  - Ordering popup, Keep out tooltips: "(when there's room)", "(every stack of it)".
  - The login warning about a missing file: "(a /reload isn't enough for new files)".
  - Debug only: Testing's "Status text in the bag (last sort's cost)"; Files' "(the version in the .toc)",
    "missing (restart the game)".
- **Keep out names.** The popup's Keep out of special bags checkbox says "all Other" for Consumable/Other, a
  part without its group (seen on Waylaid Crate: Earthly Expert Herbs, 2026-11-26), and the Special bags
  section's kept-out list shows the same "all Cloth" style. Name them like the rows: "Consumable/Other", no
  "all".
- **No "row" in player-facing text** (user, 2026-11-26: "users won't know what a row is"). The popup's hint
  "Add gives it a row; arrange rows in Order." is unwieldy; "row" is also in the Order help paragraph and
  the welcome text. The README says "entry" instead (0.20) until the game's word is decided. "Add to Order"
  as the button was considered and set aside (wider popup).
- **Options > AddOns entry.** Sediment isn't in Blizzard's AddOns settings list, where players look first. An
  entry there that opens the settings window.
- **Rules export / import.** Copy the rules (weights, flags, keep-out, Empty Space) as a text string to share
  or back up; paste one to load it. Open: replace or merge on import; rules only, or the Sorting options too.
  An import would save to History first, like Load.
- **Buff food and Drink flags, and name patterns.** Buff food from the tooltip's "well fed", Drink from the
  use spell (details in NOTES.md, "Idea details: Buff food and Drink flags"). Also, user 2026-11-26: rules
  matched by name, e.g. name contains "Waylaid" for the Waylaid Crates the game files under
  Consumable/Other. Open: how a pattern rule is made and named in Order, and where it sits in the cascade
  (with the flags?).
- **Rename the addon to "Disorder - Item Manager"** (decided by the user, 2026-11-26). "Sediment" came from
  the float/sink model, which the UI no longer shows. No players yet, so a full rename costs nothing. Still to
  settle: the slash command (/sed today; /disorder?), the folder and .toc name (Disorder?), the saved
  settings name (SedimentDB: copy the user's WTF file across, or keep the internal name), the debug addon's
  name (it follows the folder: <folder>_Debug), and renaming the GitHub repo (the user's action on GitHub;
  the old address redirects). The words in Text.lua (AddonName) and README follow. The search history:
  - LootLadder is taken: an active CurseForge addon (gear comparison from raider.io data, Oct 2026) using
    /ladder, and an old SourceForge raid loot-distribution project; "loot ladder" also names that kind of
    raid loot system. "LootLadder - Bag Manager" would still need its own folder name (WoW identifies addons
    by folder; two with one folder can't both be installed), its own saved settings and slash command.
  - BagLadder: rejected by the user (reads as "bladder").
  - Searched 2026-11-26 (web search, not CurseForge's own search): Packing Order (Claude's pick; rejected by
    the user: "sounds like I'm going to send mail"; "order" in a name reads as shipping or crafting orders;
    Pecking Order, also Claude's, is out for the same reason). Standing
    Order: nothing found, but retail crafting/work orders give "order" a WoW meaning. Rank & File: nothing
    found, but "rank" means guild/PvP ranks in addon names (e.g. Rank Command, a Forever PvP tracker).
    Quartermaster: taken twice ("Quartermaster", "The Quartermaster"). Settris (user's idea, "item setting
    tetris"): no addon, but a released 2023 block-placement puzzle game of that name (Zoo Corporation;
    Steam, consoles, Android); "inventory tetris" means fitting shapes into a grid, which WoW bags don't
    have, and "set" reads as equipment sets in WoW. Disorder (user's idea): nothing found; memorable and
    names the problem it fixes, but says the opposite of what it does at a glance, and the everyday
    meaning is medical; a subtitle ("Disorder - Bag Sorter") would fix the first. Unsearched: Top Shelf,
    Rungs, Loot Rungs.
  - With a ladder name, the words could follow: Order becomes Ladder, "Add to Ladder" in the popup (no
    "row" for players to learn; the user dislikes "row" in player-facing text).

## Later (not high priority)

- **Per-character History.** Instead of profiles (several named setups to switch between): a per-character
  History, or just a per-character pinned entry.
- **Category browser.** Add rows for kinds of items you don't carry yet; today Order only knows what's in
  the bags or already has a row. Liked, but a lot of work.
- **Presets for lazy folk.** A few selectable layouts, e.g. "Junk on top", "Junk on bottom", "Junk in the
  middle". (Replaces the old Reverse layout idea, which isn't needed.)
- **Debug tools' code into the debug addon.** Since 0.20 the Debug group only shows with SedimentSort_Debug
  loaded, but its code (Testing, Tools, Files, the bench in Popup.lua) still ships in the main addon. Moving
  it would make the main addon smaller; nothing a player sees changes.
- **Orange outlines any time.** The not-set outlines outside Order too (today only while Order shows), as a
  switch. Settings.SetHighlight already does the drawing.

## Housekeeping

- Untested in game: Start Fresh turning on the Combined Backpack when it's off (the CVar call Blizzard's bag
  menu makes); the Select Mode: On / Off button; everything in 0.20 (the debug addon needs a full restart the
  first time).
