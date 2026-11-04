-- Finding truck warehouses that were built with an older layout of this mod.
--
-- A warehouse keeps the lanes and terminals it was built with: changing the mod does not
-- rebuild constructions that already exist. The game script offers to rebuild them at the
-- start of a session (game.interface.upgradeConstruction with the warehouse's own params,
-- the same call the Move It mod uses for its "dummy upgrade").
--
-- Fingerprint: the station's terminal count (2 -> 15 -> 21), the street type of the gate
-- stubs (two-way until 1.4, one-way since 1.5) and the number of lanes in its transport
-- network. Lanes only count when there are fewer than the current layout has: every older
-- layout has fewer, and lanes the game might add on its own must not trigger a rebuild loop.
--
-- adapter = {
--   stationConstructions() -> pairs of stationId -> constructionId
--   construction(id)       -> { fileName = ..., params = ... } or nil
--   terminalCount(station) -> number or nil
--   gateStreet(id)         -> street type file of the construction's stubs, or nil if unknown
--   laneCount(id)          -> number of lanes in the construction's transport network, or nil
-- }

local M = {}

function M.isWarehouse(fileName)
	return type(fileName) == "string" and fileName:match("_warenlager%.con$") ~= nil
end

-- { { id, fileName, terminals }, ... } for every warehouse that does not match, plus
-- { [laneCount] = warehouses } over all warehouses (logged, to confirm the lane fingerprint)
-- expected = { terminals = n, street = "standard/....lua", lanes = n }
function M.findOutdated(adapter, expected)
	local seen, out, laneStats = {}, {}, {}
	for stationId, conId in pairs(adapter.stationConstructions()) do
		if not seen[conId] then
			seen[conId] = true
			local con = adapter.construction(conId)
			if con and M.isWarehouse(con.fileName) then
				local n = adapter.terminalCount(stationId)
				local street = adapter.gateStreet and adapter.gateStreet(conId) or nil
				local wrongCount = type(n) == "number" and n ~= expected.terminals
				local wrongStreet = type(street) == "string" and expected.street ~= nil and street ~= expected.street
				local lanes = adapter.laneCount and adapter.laneCount(conId) or nil
				local lk = tostring(lanes)
				laneStats[lk] = (laneStats[lk] or 0) + 1
				local fewerLanes = type(lanes) == "number" and expected.lanes ~= nil and lanes < expected.lanes
				if wrongCount or wrongStreet or fewerLanes then
					out[#out + 1] = { id = conId, fileName = con.fileName, terminals = n, street = street, lanes = lanes }
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out, laneStats
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
