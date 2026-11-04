-- Finding truck warehouses that were built with an older layout of this mod.
--
-- A warehouse keeps the lanes and terminals it was built with: changing the mod does not
-- rebuild constructions that already exist. The game script offers to rebuild them at the
-- start of a session (game.interface.upgradeConstruction with the warehouse's own params,
-- the same call the Move It mod uses for its "dummy upgrade").
--
-- Fingerprint: the station's terminal count (2 -> 15 -> 21) and the street type of the gate
-- stubs (two-way until 1.4, one-way since 1.5). A future change that keeps both must add
-- something else here.
--
-- adapter = {
--   stationConstructions() -> pairs of stationId -> constructionId
--   construction(id)       -> { fileName = ..., params = ... } or nil
--   terminalCount(station) -> number or nil
--   gateStreet(id)         -> street type file of the construction's stubs, or nil if unknown
-- }

local M = {}

function M.isWarehouse(fileName)
	return type(fileName) == "string" and fileName:match("_warenlager%.con$") ~= nil
end

-- { { id, fileName, terminals }, ... } for every warehouse that does not match
-- expected = { terminals = n, street = "standard/....lua" }
function M.findOutdated(adapter, expected)
	local seen, out = {}, {}
	for stationId, conId in pairs(adapter.stationConstructions()) do
		if not seen[conId] then
			seen[conId] = true
			local con = adapter.construction(conId)
			if con and M.isWarehouse(con.fileName) then
				local n = adapter.terminalCount(stationId)
				local street = adapter.gateStreet and adapter.gateStreet(conId) or nil
				local wrongCount = type(n) == "number" and n ~= expected.terminals
				local wrongStreet = type(street) == "string" and expected.street ~= nil and street ~= expected.street
				if wrongCount or wrongStreet then
					out[#out + 1] = { id = conId, fileName = con.fileName, terminals = n, street = street }
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
