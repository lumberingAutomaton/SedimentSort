-- Checks the words table (Text.lua): every key the addon uses with L / N / B (ns.L, ns.Noun, ns.Btn) exists,
-- and every key in the table is used somewhere. A missing key wouldn't error in game; it would quietly show
-- the key itself ("ClearAllButton") as the text. Run: lua dev/text_check.lua (from the addon folder).
local ns = {}
assert(loadfile("Text.lua"))("Sediment", ns)

local files = { "Weights.lua", "Bags.lua", "Sound.lua", "Sort.lua", "AutoSort.lua", "Popup.lua", "Settings.lua",
	"Setup.lua", "Sediment.lua" }
local used, problems = {}, {}
for _, file in ipairs(files) do
	local f = assert(io.open(file))
	local n = 0
	for line in f:lines() do
		n = n + 1
		for fn, key in line:gmatch('([%w%.]+)%("([%a]+)"%)') do
			if fn == "L" or fn == "N" or fn == "B" or fn == "ns.L" or fn == "ns.Noun" or fn == "ns.Btn" then
				used[key] = true
				if ns.TEXT[key] == nil then
					problems[#problems + 1] = ("%s:%d: no key %q in Text.lua"):format(file, n, key)
				end
			end
		end
	end
	f:close()
end
for key in pairs(ns.TEXT) do
	if not used[key] then
		problems[#problems + 1] = ("Text.lua: %q isn't used anywhere"):format(key)
	end
end
table.sort(problems)
for _, p in ipairs(problems) do
	print(p)
end
assert(#problems == 0, #problems .. " problem(s)")
print("text OK")
