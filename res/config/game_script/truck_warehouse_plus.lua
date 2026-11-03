--[[
Truck warehouse Plus: spread every line's trucks over all loading bays.

A line stop has one terminal; the other terminals of a station are only used when the stop
lists them as alternative terminals. Every SCAN_EVERY engine updates (~2 s) this script
looks for line stops at a truck warehouse whose alternative list is still empty and fills it
with the warehouse's other terminals (logic in truck_warehouse_plus/auto_bays.lua).

Stops that already have alternative terminals are never touched, so a hand-made choice in
the line window stays. To keep a warehouse out of this entirely, set "Spread trucks over all
bays" to No on the warehouse.

Runs on the engine thread only (update). No saved state: `sent` only stops a rejected update
from being re-sent every scan during this session.

Entity ids are checked with entityExists before every getComponent: the game writes a
minidump at the moment it throws, even when a pcall catches it.
--]]

local autoBays = require "truck_warehouse_plus/auto_bays"

local SCAN_EVERY = 10
local LOG = "truck_warehouse_plus: "

local tick = 0
local sent = {}
local errorsLogged = 0

local function exists(e)
	return type(e) == "number" and e >= 0 and api.engine.entityExists(e)
end

local function warehouseTerminals(group, stationIdx)
	if not exists(group) or type(stationIdx) ~= "number" then return nil end
	local sg = api.engine.getComponent(group, api.type.ComponentType.STATION_GROUP)
	if not sg or not sg.stations or stationIdx < 0 or stationIdx >= #sg.stations then return nil end
	local stationId = sg.stations[stationIdx + 1]
	if not exists(stationId) then return nil end

	local conId = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(stationId)
	if not exists(conId) then return nil end
	local con = api.engine.getComponent(conId, api.type.ComponentType.CONSTRUCTION)
	if not con or type(con.fileName) ~= "string" or not con.fileName:match("_warenlager%.con$") then return nil end
	local _, setting = pcall(function() return con.params[autoBays.PARAM] end)
	if not autoBays.enabled(setting) then return nil end

	local station = api.engine.getComponent(stationId, api.type.ComponentType.STATION)
	if not station or not station.terminals then return nil end
	return #station.terminals
end

local adapter = {
	lines = function() return api.engine.system.lineSystem.getLines() end,
	line = function(lineId)
		if not exists(lineId) then return nil end
		return api.engine.getComponent(lineId, api.type.ComponentType.LINE)
	end,
	warehouseTerminals = warehouseTerminals,
}

-- Same copy pattern as the line editor of the bus line tool: a fresh Line with the original's
-- vehicle info and its own stop objects, so every other stop setting is kept as it was.
local function apply(lineId, plan)
	local original = adapter.line(lineId)
	if not original then return end
	local line = api.type.Line.new()
	line.vehicleInfo = original.vehicleInfo
	pcall(function() line.waitingTime = original.waitingTime end)

	local added = 0
	for i = 1, #original.stops do
		local stop = original.stops[i]
		local alternatives = plan[i]
		if alternatives then
			for k, terminal in ipairs(alternatives) do
				local alt = api.type.StationTerminal.new()
				alt.station = stop.station
				alt.terminal = terminal
				stop.alternativeTerminals[k] = alt
			end
			added = added + #stop.alternativeTerminals
		end
		line.stops[i] = stop
	end

	api.cmd.sendCommand(api.cmd.make.updateLine(lineId, line), function(_, success)
		print(LOG .. "line " .. tostring(lineId) .. ": " .. tostring(added)
			.. " alternative terminals " .. (success and "added" or "REJECTED by the game"))
	end)
end

local function scan()
	for _, job in ipairs(autoBays.scan(adapter, sent)) do
		apply(job.lineId, job.plan)
	end
end

function data()
	return {
		update = function()
			tick = tick + 1
			if tick < SCAN_EVERY then return end
			tick = 0
			local ok, err = pcall(scan)
			if not ok and errorsLogged < 5 then
				errorsLogged = errorsLogged + 1
				print(LOG .. "scan failed: " .. tostring(err))
			end
		end,
	}
end
