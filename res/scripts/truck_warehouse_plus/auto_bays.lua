-- Spread a line's trucks over every terminal of a truck warehouse.
--
-- TpF2 assigns one terminal per line stop. Extra terminals are only used when the stop lists
-- them as "alternative terminals" (line window, build 35044+); otherwise every truck queues
-- for the same bay. This module finds warehouse stops whose alternative list is still empty
-- and works out which terminals to add: every other terminal of the station, loading bays
-- first, then the two lay-bys on the south road.
--
-- Pure logic: the game calls go through an adapter (see res/config/game_script/
-- truck_warehouse_plus.lua), so test/auto_bays.lua can drive it with fakes.
--
-- adapter = {
--   lines()                         -> iterable of line ids
--   line(lineId)                    -> line component (stops 1-based; stop.stationGroup,
--                                      stop.station (0-based), stop.terminal (0-based),
--                                      stop.alternativeTerminals)
--   warehouseTerminals(group, idx)  -> terminal count of the station, or nil when it is not a
--                                      truck warehouse or auto bays are switched off there
-- }

local M = {}

M.FIRST_BAY = 2 -- terminals 0 and 1 are the original lay-bys, 2.. are the loading bays
M.PARAM = "twp_auto_bays" -- construction param: 0 = on (default), 1 = off

-- `value` is params[PARAM]; warehouses placed before the param existed have none: on.
function M.enabled(value)
	return value ~= 1
end

local function count(list)
	if list == nil then return 0 end
	return #list
end

-- The alternative terminals for a stop whose own terminal is `primary`, at a station with
-- `terminalCount` terminals. Bays first so trucks prefer the hall over the street lay-bys.
function M.alternativesFor(primary, terminalCount)
	local out = {}
	for t = M.FIRST_BAY, terminalCount - 1 do
		if t ~= primary then out[#out + 1] = t end
	end
	for t = 0, math.min(M.FIRST_BAY, terminalCount) - 1 do
		if t ~= primary then out[#out + 1] = t end
	end
	return out
end

-- Everything that identifies the stops we would touch; a line is only sent again once this
-- changes, so a rejected update is not retried every scan.
local function signature(line)
	local parts = {}
	for i = 1, count(line.stops) do
		local s = line.stops[i]
		parts[#parts + 1] = string.format("%s:%s:%s:%d", tostring(s.stationGroup), tostring(s.station),
			tostring(s.terminal), count(s.alternativeTerminals))
	end
	return table.concat(parts, ";")
end

-- True when `alts` is "every other terminal" of a smaller warehouse (0 .. #alts), on this
-- station: what this script filled in before the warehouse grew, or a player's "all of them".
-- Such a list is extended when the warehouse gains terminals; any other choice is left alone.
local function coversSmallerWarehouse(stop, n)
	local a = count(stop.alternativeTerminals)
	if a == 0 or a + 1 >= n then return false end
	local seen = {}
	for i = 1, a do
		local alt = stop.alternativeTerminals[i]
		local t = alt and alt.terminal
		if type(t) ~= "number" or alt.station ~= stop.station or t == stop.terminal or t < 0 or t > a or seen[t] then
			return false
		end
		seen[t] = true
	end
	return stop.terminal >= 0 and stop.terminal <= a
end

-- Returns { [stopIndex] = { terminal, ... } } for the stops of `line` that need alternatives
-- (none yet, or all of a smaller warehouse), or nil when nothing needs doing.
function M.planLine(line, warehouseTerminals)
	local plan
	for i = 1, count(line.stops) do
		local stop = line.stops[i]
		local n = warehouseTerminals(stop.stationGroup, stop.station)
		if n and n > 1 and (count(stop.alternativeTerminals) == 0 or coversSmallerWarehouse(stop, n)) then
			plan = plan or {}
			plan[i] = M.alternativesFor(stop.terminal, n)
		end
	end
	return plan
end

-- One pass over every line. `sent` maps lineId -> signature of the last update we sent for
-- it (kept by the caller between scans). Returns a list of { lineId, plan }.
function M.scan(adapter, sent)
	local memo = {}
	local function warehouseTerminals(group, station)
		local k = tostring(group) .. "/" .. tostring(station)
		if memo[k] == nil then memo[k] = adapter.warehouseTerminals(group, station) or false end
		return memo[k] or nil
	end

	local todo = {}
	for _, lineId in pairs(adapter.lines()) do
		local line = adapter.line(lineId)
		if line then
			local plan = M.planLine(line, warehouseTerminals)
			if plan then
				local sig = signature(line)
				if sent[lineId] ~= sig then
					sent[lineId] = sig
					todo[#todo + 1] = { lineId = lineId, plan = plan }
				end
			end
		end
	end
	return todo
end

return M
