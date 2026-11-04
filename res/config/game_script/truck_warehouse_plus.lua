--[[
Truck warehouse Plus game script. Two jobs:

1. (engine thread) Spread every line's trucks over all of a warehouse's terminals.

A line stop has one terminal; the other terminals of a station are only used when the stop
lists them as alternative terminals. Every SCAN_EVERY engine updates (~2 s) this script
looks for line stops at a truck warehouse whose alternative list is still empty and fills it
with the warehouse's other terminals (logic in truck_warehouse_plus/auto_bays.lua).

Stops that already have alternative terminals are left alone, except a list that is "every
other terminal" of a smaller warehouse, which is extended when the warehouse grows. To keep a
warehouse out of this entirely, set "Spread trucks over all bays" to No on the warehouse.
No saved state: `sent` only stops a rejected update from being re-sent every scan.

2. At the start of a session, offer to rebuild warehouses that were built with an older layout
of this mod: existing constructions keep the lanes they were built with until they are rebuilt
(logic in truck_warehouse_plus/upgrade.lua). The popup lives on the GUI thread, but
game.interface.upgradeConstruction only exists on the engine thread (in game 2026-11-04:
"attempt to call field 'upgradeConstruction' (a nil value)" from the GUI), so the button sends a
script event and handleEvent does the rebuild.

Entity ids are checked with entityExists before every getComponent: the game writes a
minidump at the moment it throws, even when a pcall catches it.
--]]

local autoBays = require "truck_warehouse_plus/auto_bays"
local upgrade = require "truck_warehouse_plus/upgrade"
local network = require "truck_warehouse_plus/network"

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

---------------------------------------------------------------------------
-- GUI thread: rebuild popup

-- Script events reach every game script, so the id is namespaced.
local EVENT_ID = "__truck_warehouse_plus__"
local POPUP_AFTER_FRAMES = 30 -- let the game UI finish loading first
local guiFrames = 0
local guiChecked = false
local guiWork = nil -- runs on the next guiUpdate, outside the button callback
-- After "Rebuild now" the GUI must not read the warehouses again: in game (1.9) a recount 60
-- frames later read them while the engine was still replacing them and crashed the game inside
-- guiUpdate (a C++ crash, no Lua error to catch). The result goes to the log only.

local function findOutdated()
	return upgrade.findOutdated({
		stationConstructions = function() return api.engine.system.streetConnectorSystem.getStation2ConstructionMap() end,
		construction = function(id)
			if not exists(id) then return nil end
			return api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
		end,
		terminalCount = function(stationId)
			if not exists(stationId) then return nil end
			local st = api.engine.getComponent(stationId, api.type.ComponentType.STATION)
			return st and st.terminals and #st.terminals or nil
		end,
		-- the gate stubs are the construction's frozen street edges (calls as Move It makes them)
		gateStreet = function(conId)
			local con = api.engine.getComponent(conId, api.type.ComponentType.CONSTRUCTION)
			if not con or not con.frozenEdges then return nil end
			for _, e in pairs(con.frozenEdges) do
				if exists(e) then
					local se = api.engine.getComponent(e, api.type.ComponentType.BASE_EDGE_STREET)
					if se then return api.res.streetTypeRep.getName(se.streetType) end
				end
			end
			return nil
		end,
		laneCount = function(conId)
			local tn = api.engine.getComponent(conId, api.type.ComponentType.TRANSPORT_NETWORK)
			return tn and tn.edges and #tn.edges or nil
		end,
	}, { terminals = #network.build().terminals, street = network.GATE_STREET, lanes = network.laneCount() })
end

-- engine thread (handleEvent): rebuild the warehouses the popup listed
local function rebuild(ids)
	local done, total = 0, 0
	for _, id in ipairs(ids) do
		total = total + 1
		if exists(id) then
			local con = api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
			if con and upgrade.isWarehouse(con.fileName) then
				local params = upgrade.rebuildParams(con.params)
				local ok, err = pcall(function() game.interface.upgradeConstruction(id, con.fileName, params) end)
				if ok then
					done = done + 1
				else
					print(LOG .. "rebuilding warehouse " .. tostring(id) .. " failed: " .. tostring(err))
				end
			end
		end
	end
	print(LOG .. "rebuilt " .. done .. " of " .. total .. " warehouses")
end

local function showPopup(outdated)
	local expected = #network.build().terminals
	local layout = api.gui.layout.BoxLayout.new("VERTICAL")
	local text = api.gui.comp.TextView.new(string.format(_("TWP_POPUP_TEXT"), #outdated, expected))
	layout:addItem(text)
	local buttons = api.gui.layout.BoxLayout.new("HORIZONTAL")
	local yes = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("TWP_POPUP_REBUILD")), false)
	local no = api.gui.comp.Button.new(api.gui.comp.TextView.new(_("TWP_POPUP_LATER")), false)
	buttons:addItem(yes)
	buttons:addItem(no)
	layout:addItem(buttons)
	local window = api.gui.comp.Window.new(_("TWP_POPUP_TITLE"), layout)
	window:addHideOnCloseHandler()
	pcall(function()
		local r = api.gui.util.getGameUI():getMainRendererComponent():getContentRect()
		window:setPosition(math.floor(r.w / 2 - 220), math.floor(r.h / 3))
	end)
	window:setVisible(true, false)

	yes:onClick(function()
		guiWork = function()
			local ids = {}
			for i, w in ipairs(outdated) do ids[i] = w.id end
			game.interface.sendScriptEvent(EVENT_ID, "rebuild", { ids = ids })
			window:close()
		end
	end)
	no:onClick(function() window:close() end)
end

local function guiCheck()
	guiFrames = guiFrames + 1
	if guiWork then
		local work = guiWork
		guiWork = nil
		local ok, err = pcall(work)
		if not ok then print(LOG .. "rebuild failed: " .. tostring(err)) end
	end
	if guiChecked then return end
	if guiFrames < POPUP_AFTER_FRAMES then return end
	guiChecked = true
	local ok, outdated, laneStats = pcall(findOutdated)
	if ok then
		local parts = {}
		for lanes, n in pairs(laneStats or {}) do parts[#parts + 1] = lanes .. " lanes x" .. n end
		table.sort(parts)
		print(LOG .. "warehouses: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
			.. " (current layout: " .. network.laneCount() .. ")")
	end
	if not ok then
		print(LOG .. "layout check failed: " .. tostring(outdated))
	elseif #outdated > 0 then
		print(LOG .. #outdated .. " warehouse(s) built with an older layout (now " .. #network.build().terminals
			.. " terminals, " .. network.laneCount() .. " lanes); first: " .. tostring(outdated[1].terminals)
			.. " terminals, " .. tostring(outdated[1].lanes) .. " lanes, " .. tostring(outdated[1].street))
		local shown, err = pcall(showPopup, outdated)
		if not shown then print(LOG .. "popup failed: " .. tostring(err)) end
	end
end

function data()
	return {
		guiUpdate = guiCheck,
		handleEvent = function(_, id, name, param)
			if id ~= EVENT_ID or name ~= "rebuild" then return end
			local ok, err = pcall(function() rebuild(type(param) == "table" and param.ids or {}) end)
			if not ok then print(LOG .. "rebuild failed: " .. tostring(err)) end
		end,
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
