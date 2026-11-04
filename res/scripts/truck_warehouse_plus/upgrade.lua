-- Finding truck warehouses that were built with an older layout of this mod.
--
-- A warehouse keeps the lanes and terminals it was built with: changing the mod does not
-- rebuild constructions that already exist. The game script offers to rebuild them at the
-- start of a session (game.interface.upgradeConstruction with the warehouse's own params,
-- the same call the Move It mod uses for its "dummy upgrade").
--
-- Fingerprint: the station's terminal count. Every layout change so far changed it
-- (2 -> 15 -> 21); a future change that keeps the count must bump the fingerprint some
-- other way.
--
-- adapter = {
--   stationConstructions() -> pairs of stationId -> constructionId
--   construction(id)       -> { fileName = ..., params = ... } or nil
--   terminalCount(station) -> number or nil
-- }

local M = {}

function M.isWarehouse(fileName)
	return type(fileName) == "string" and fileName:match("_warenlager%.con$") ~= nil
end

-- { { id, fileName, terminals }, ... } for every warehouse whose terminal count is not `expected`
function M.findOutdated(adapter, expected)
	local seen, out = {}, {}
	for stationId, conId in pairs(adapter.stationConstructions()) do
		if not seen[conId] then
			seen[conId] = true
			local con = adapter.construction(conId)
			if con and M.isWarehouse(con.fileName) then
				local n = adapter.terminalCount(stationId)
				if type(n) == "number" and n ~= expected then
					out[#out + 1] = { id = conId, fileName = con.fileName, terminals = n }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

-- The params to rebuild with: the warehouse's own, minus the seed the game adds (Move It
-- clears it too; the game picks a new one).
function M.rebuildParams(params)
	local out = {}
	local function copy(v)
		if type(v) ~= "table" then return v end
		local t = {}
		for k, x in pairs(v) do t[k] = copy(x) end
		return t
	end
	-- a plain table in practice (Move It deep-clones it the same way); pcall in case the game
	-- hands over something pairs() cannot walk, which falls back to the defaults
	if params ~= nil then
		pcall(function()
			for k, v in pairs(params) do out[k] = copy(v) end
		end)
	end
	out.seed = nil
	return out
end

return M
