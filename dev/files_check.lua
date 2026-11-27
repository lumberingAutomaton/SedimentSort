-- Checks that ns.FILES (Core.lua) lists exactly the .toc's files in the same order, and that each file
-- marks itself loaded under its own name (ns.loadedFiles["X.lua"]). The login check and Debug > Files rely on
-- both. Run: lua dev/files_check.lua (from the addon folder).
local toc = {}
for line in io.lines("Disorder_ItemManager.toc") do
	if line:match("%.lua%s*$") then
		toc[#toc + 1] = line:match("^%s*(.-)%s*$")
	end
end
local src = assert(io.open("Core.lua")):read("a")
local block = assert(src:match("ns%.FILES = (%b{})"), "no ns.FILES in Core.lua")
local listed = {}
for name in block:gmatch('"([^"]+)"') do
	listed[#listed + 1] = name
end
assert(table.concat(listed, " ") == table.concat(toc, " "),
	"ns.FILES and the .toc differ:\n  ns.FILES: " .. table.concat(listed, " ") .. "\n  .toc:     " .. table.concat(toc, " "))
for _, file in ipairs(toc) do
	local text = assert(io.open(file)):read("a")
	assert(text:find('ns.loadedFiles["' .. file .. '"] = true', 1, true), file .. " doesn't mark itself loaded")
end
print(("files OK (%d, matching the .toc)"):format(#toc))
