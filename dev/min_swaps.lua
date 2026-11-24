-- Proven minimum swaps to reach a target layout, for checking Sediment's placement plans.
-- Not loaded by the game.
--
-- Every misplaced slot p is an edge from what it holds (cur[p]) to what it should hold (want[p]);
-- identical items and empty slots share a node. Any way of matching items to target slots is a
-- decomposition of these edges into cycles, and a cycle of k slots costs k-1 swaps, so
--   minimum swaps = misplaced slots - (most cycles any decomposition can have).
-- Finding the most cycles is a hard problem in general, so this searches exhaustively but gives up
-- (returns nil) past a budget; callers count those as unproven rather than guessing.

local M = {}

local MAX_EDGES = 40
local MAX_STEPS = 200000

-- cur, want: arrays of item signatures ("" = empty) for one zone. Returns minimum swaps, or nil if
-- the search ran past its budget.
function M.MinSwaps(cur, want)
	local count, misplaced = {}, 0 -- count[from][to] = edges left
	for p = 1, #cur do
		if cur[p] ~= want[p] then
			misplaced = misplaced + 1
			count[cur[p]] = count[cur[p]] or {}
			count[cur[p]][want[p]] = (count[cur[p]][want[p]] or 0) + 1
		end
	end
	if misplaced == 0 then
		return 0
	end
	if misplaced > MAX_EDGES then
		return nil
	end

	-- Two-cycles (a->b and b->a) are always worth taking: they can't block a better decomposition.
	local cycles = 0
	for a, outs in pairs(count) do
		for b, n in pairs(outs) do
			if a < b and count[b] and (count[b][a] or 0) > 0 then
				local m = math.min(n, count[b][a])
				outs[b] = n - m
				count[b][a] = count[b][a] - m
				cycles = cycles + m
			end
		end
	end

	local steps, memo = 0, {}
	local function Key()
		local parts = {}
		for a, outs in pairs(count) do
			for b, n in pairs(outs) do
				if n > 0 then
					parts[#parts + 1] = a .. "\1" .. b .. "\1" .. n
				end
			end
		end
		table.sort(parts)
		return table.concat(parts, "\2")
	end

	-- Most cycles in what's left: pick the first remaining edge s->t, try every simple cycle that
	-- uses it (a path from t back to s not repeating nodes), recurse on the rest.
	local function Solve()
		steps = steps + 1
		if steps > MAX_STEPS then
			error("budget")
		end
		local key = Key()
		if key == "" then
			return 0
		end
		if memo[key] then
			return memo[key]
		end
		local s, t
		for _, part in ipairs({ key:match("^([^\2]*)") }) do
			s, t = part:match("^(.-)\1(.-)\1")
		end
		local best = 0
		local used = { [s] = true }
		count[s][t] = count[s][t] - 1
		local function Walk(node)
			if node == s then
				best = math.max(best, 1 + Solve())
				return
			end
			if used[node] then
				return
			end
			used[node] = true
			for nxt, n in pairs(count[node] or {}) do
				if n > 0 then
					count[node][nxt] = n - 1
					Walk(nxt)
					count[node][nxt] = n
				end
			end
			used[node] = nil
		end
		Walk(t)
		count[s][t] = count[s][t] + 1
		memo[key] = best
		return best
	end

	local ok, more = pcall(Solve)
	if not ok then
		return nil
	end
	return misplaced - (cycles + more)
end

return M
