-- Disorder - Item Manager Debug: a separate addon whose only job is to be installed. While it's loaded, the
-- Item Manager's settings show the Debug group (Testing, Tools, Files); without it, players never see any of it
-- (user, 2026-11-26: no Debug mode switch; the tools appear only when the right files are there).
-- The Item Manager checks for it by name (Settings.DebugOn: C_AddOns.IsAddOnLoaded("Disorder_ItemManager_Debug")).
-- The tools' code lives in the main addon for now.
local _ = ... -- nothing to run: being loaded is the point
