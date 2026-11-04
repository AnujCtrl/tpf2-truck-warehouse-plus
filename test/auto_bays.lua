-- Checks for the automatic bay assignment (auto_bays.lua + the game script).
-- Run from the repo root:  lua5.2 test/auto_bays.lua

package.path = "res/scripts/?.lua;" .. package.path
-- the game's init.lua replaces table.unpack; mirror it so nothing here can depend on it
table.unpack = function(t) return t[1] end

local autoBays = require "truck_warehouse_plus/auto_bays"
local network = require "truck_warehouse_plus/network"

local failures, checks = 0, 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		print("FAIL: " .. msg)
	end
end
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end

-- 1. which terminals become alternatives
check(same(autoBays.alternativesFor(0, 15), { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 1 }), "primary lay-by 0")
check(same(autoBays.alternativesFor(1, 15), { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0 }), "primary lay-by 1")
check(same(autoBays.alternativesFor(7, 15), { 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 0, 1 }), "primary bay 7")
check(same(autoBays.alternativesFor(0, 2), { 1 }), "old 2-terminal warehouse")
check(#autoBays.alternativesFor(0, 1) == 0, "single terminal: nothing")
for p = 0, 14 do
	local alts, seen = autoBays.alternativesFor(p, 15), {}
	check(#alts == 14, "primary " .. p .. ": 14 alternatives")
	for _, t in ipairs(alts) do
		check(t ~= p and t >= 0 and t < 15 and not seen[t], "primary " .. p .. ": bad/duplicate alternative " .. t)
		seen[t] = true
	end
end

-- 2. the param
check(autoBays.enabled(nil), "missing param (old warehouse) = on")
check(autoBays.enabled(0), "0 = on")
check(not autoBays.enabled(1), "1 = off")

-- 3. scan over fake lines
-- group 100 = warehouse (station 0) ; group 200 = plain truck stop ; group 300 = warehouse, switched off
local function warehouseTerminals(group, station)
	if group == 100 and station == 0 then return 15 end
	return nil
end
local function stop(group, terminal, alts) return { stationGroup = group, station = 0, terminal = terminal, alternativeTerminals = alts or {} } end
local lines = {
	[1] = { stops = { stop(200, 0), stop(100, 0) } },          -- needs stop 2
	[2] = { stops = { stop(200, 0), stop(100, 3, { {} }) } },  -- hand-made alternatives: leave
	[3] = { stops = { stop(200, 0), stop(300, 0) } },          -- no warehouse
	[4] = { stops = { stop(100, 5), stop(200, 1), stop(100, 9) } }, -- warehouse twice
}
local calls = 0
local adapter = {
	lines = function() return { 1, 2, 3, 4 } end,
	line = function(id) return lines[id] end,
	warehouseTerminals = function(g, s) calls = calls + 1 return warehouseTerminals(g, s) end,
}
local sent = {}
local todo = autoBays.scan(adapter, sent)
check(#todo == 2, "two lines need work, got " .. #todo)
check(todo[1].lineId == 1 and todo[1].plan[2] and not todo[1].plan[1], "line 1: only the warehouse stop")
check(same(todo[1].plan[2], autoBays.alternativesFor(0, 15)), "line 1 alternatives")
check(todo[2].lineId == 4 and todo[2].plan[1] and todo[2].plan[3] and not todo[2].plan[2], "line 4: both warehouse stops")
check(same(todo[2].plan[3], autoBays.alternativesFor(9, 15)), "line 4 second visit keeps its own primary")
check(calls == 3, "station lookups are memoised per scan, got " .. calls)

-- an unchanged line is not re-sent (e.g. the game rejected the update)
check(#autoBays.scan(adapter, sent) == 0, "nothing re-sent while the line is unchanged")
-- once the user edits the line it is looked at again
lines[1].stops[2].terminal = 4
local again = autoBays.scan(adapter, sent)
check(#again == 1 and again[1].lineId == 1, "an edited line is planned again")

-- 4. the game script against a fake api
local commands = {}
local entities = { [100] = "group", [10] = "station", [50] = "construction", [1] = "line", [2] = "line" }
local fakeLines = {
	[1] = { stops = { stop(200, 0), stop(100, 0) }, vehicleInfo = "vi", waitingTime = 0 },
	[2] = { stops = { stop(100, 2, { { station = 0, terminal = 3 } }) }, vehicleInfo = "vi" },
}
entities[200] = "group"
local params = {}
local fakeTerminals = 15
local fakeStreet = "standard/country_medium_new.lua"
local fakeLanes = 0
_G.api = {
	type = {
		ComponentType = { STATION_GROUP = "SG", CONSTRUCTION = "CON", STATION = "ST", LINE = "LINE", BASE_EDGE_STREET = "BES", TRANSPORT_NETWORK = "TN" },
		Line = { new = function() return { stops = {} } end },
		StationTerminal = { new = function() return {} end },
	},
	engine = {
		entityExists = function(e) return entities[e] ~= nil end,
		getComponent = function(e, t)
			if t == "SG" then return ({ [100] = { stations = { 10 } }, [200] = { stations = { 20 } } })[e] end
			if t == "CON" and e == 50 then return { fileName = "assets/dhl_warenlager.con", params = params, frozenEdges = { 77 } } end
			if t == "BES" and e == 77 then return { streetType = fakeStreet } end
			if t == "TN" and e == 50 then local es = {} for i = 1, fakeLanes do es[i] = {} end return { edges = es } end
			if t == "ST" and e == 10 then local ts = {} for i = 1, fakeTerminals do ts[i] = {} end return { terminals = ts } end
			if t == "LINE" then return fakeLines[e] end
		end,
		system = {
			lineSystem = { getLines = function() return { 1, 2 } end },
			streetConnectorSystem = { getConstructionEntityForStation = function(s) return s == 10 and 50 or -1 end },
		},
	},
	cmd = {
		make = { updateLine = function(id, line) return { id = id, line = line } end },
		sendCommand = function(cmd, cb) commands[#commands + 1] = cmd; cb(nil, true) end,
	},
}
local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end
local script = assert(loadfile("res/config/game_script/truck_warehouse_plus.lua"))
script()
local gs = data()
for _ = 1, 9 do gs.update() end
local afterNine = #commands
for _ = 1, 21 do gs.update() end
print = realPrint
check(afterNine == 0, "no scan before SCAN_EVERY updates")
check(#commands == 1, "exactly one updateLine (line 2 already has alternatives), got " .. #commands)
if commands[1] then
	local l = commands[1].line
	check(commands[1].id == 1, "updated line 1")
	check(l.vehicleInfo == "vi" and #l.stops == 2, "line copied with its vehicle info and stops")
	check(#l.stops[1].alternativeTerminals == 0, "non-warehouse stop untouched")
	local alts = l.stops[2].alternativeTerminals
	check(#alts == 14, "warehouse stop got 14 alternatives, got " .. #alts)
	check(alts[1].terminal == 2 and alts[1].station == 0, "first alternative is bay 1 (terminal 2) of the same station")
end
for _, s in ipairs(printed) do check(not s:find("scan failed"), "script error: " .. s) end

-- switched off on the warehouse: nothing happens
commands, sent = {}, nil
params[autoBays.PARAM] = 1
fakeLines[1] = { stops = { stop(200, 0), stop(100, 0) }, vehicleInfo = "vi" }
script()
gs = data()
print = function() end
for _ = 1, 30 do gs.update() end
print = realPrint
check(#commands == 0, "auto bays off on the warehouse: no update")

-- 5. a warehouse that grew (15 -> 21): "all other terminals" lists are extended, others kept
local function alts(list)
	local out = {}
	for i, t in ipairs(list) do out[i] = { station = 0, terminal = t } end
	return out
end
local function grown(group, station) if group == 100 then return 21 end end
local old15 = autoBays.alternativesFor(4, 15)
local p = autoBays.planLine({ stops = { stop(100, 4, alts(old15)) } }, grown)
check(p and p[1] and #p[1] == 20, "old full list (14) extended to 20 alternatives")
check(p and p[1] and same(p[1], autoBays.alternativesFor(4, 21)), "extended list = bays, parking, lay-bys")
check(autoBays.planLine({ stops = { stop(100, 4, alts({ 3, 5 })) } }, grown) == nil, "hand-picked subset kept")
check(autoBays.planLine({ stops = { stop(100, 4, alts(autoBays.alternativesFor(4, 21))) } }, grown) == nil,
	"already complete list kept (no endless re-sending)")
local other = alts(old15); other[3].station = 1
check(autoBays.planLine({ stops = { stop(100, 4, other) } }, grown) == nil, "list naming another station kept")
check(autoBays.planLine({ stops = { stop(100, 20, alts(old15)) } }, grown) == nil, "primary outside the old range: kept")

-- 6. finding warehouses with an older layout
local upgrade = require "truck_warehouse_plus/upgrade"
local found = upgrade.findOutdated({
	stationConstructions = function() return { [10] = 50, [11] = 51, [12] = 52, [13] = 50 } end,
	construction = function(id)
		return ({ [50] = { fileName = "assets/dhl_warenlager.con" }, [51] = { fileName = "assets/ups_warenlager.con" },
			[52] = { fileName = "station/street/small.con" } })[id]
	end,
	terminalCount = function(s) return ({ [10] = 15, [11] = 21, [12] = 3, [13] = 15 })[s] end,
}, { terminals = 21, street = "one_way.lua" })
check(#found == 1 and found[1].id == 50 and found[1].terminals == 15, "only the 15-terminal warehouse is outdated, once")
-- same terminal count, but still the two-way gate street of 1.3/1.4
local function streetCase(street)
	return upgrade.findOutdated({
		stationConstructions = function() return { [11] = 51 } end,
		construction = function() return { fileName = "assets/ups_warenlager.con" } end,
		terminalCount = function() return 21 end,
		gateStreet = function() return street end,
	}, { terminals = 21, street = "one_way.lua" })
end
check(#streetCase("two_way.lua") == 1, "21 terminals but two-way gates: outdated")
check(#streetCase("one_way.lua") == 0, "21 terminals and one-way gates: current")
check(#streetCase(nil) == 0, "street type unknown: judged by terminals only")
local function laneCase(lanes)
	return upgrade.findOutdated({
		stationConstructions = function() return { [11] = 51 } end,
		construction = function() return { fileName = "assets/ups_warenlager.con" } end,
		terminalCount = function() return 21 end,
		gateStreet = function() return "one_way.lua" end,
		laneCount = function() return lanes end,
	}, { terminals = 21, street = "one_way.lua", lanes = 280 })
end
check(#laneCase(270) == 1, "fewer lanes than the current layout: outdated")
check(#laneCase(280) == 0, "same lanes: current")
check(#laneCase(300) == 0, "more lanes (something the game adds): never a rebuild loop")
check(#laneCase(nil) == 0, "lanes unknown: judged by the rest")
local _, stats = laneCase(270)
check(stats["270"] == 1, "lane counts are reported for the log")
local rp = upgrade.rebuildParams({ seed = 7, twp_storage = 2, nested = { a = 1 } })
check(rp.seed == nil and rp.twp_storage == 2 and rp.nested.a == 1, "rebuild keeps the params, drops the seed")
check(next(upgrade.rebuildParams(nil)) == nil, "rebuild with no params")

-- 7. the popup, driven through a fake GUI
local clicks, texts, upgrades, windows = {}, {}, {}, 0
local function widget(kind)
	local w = { kind = kind }
	return setmetatable(w, { __index = function(_, name)
		return function(self, a)
			if name == "onClick" then clicks[self] = a end
			if name == "setText" then texts[#texts + 1] = a end
		end
	end })
end
api.gui = {
	layout = { BoxLayout = { new = function() return widget("box") end } },
	comp = {
		TextView = { new = function(t) texts[#texts + 1] = t return widget("text") end },
		Button = { new = function() return widget("button") end },
		Window = { new = function() windows = windows + 1 return widget("window") end },
	},
	util = { getGameUI = function() error("no renderer in the fake") end },
}
api.engine.system.streetConnectorSystem.getStation2ConstructionMap = function() return { [10] = 50 } end
-- like the real game: the GUI thread can send script events but has no upgradeConstruction;
-- the engine thread (handleEvent) has it
local events = {}
local guiInterface = { sendScriptEvent = function(id, name, param) events[#events + 1] = { id, name, param } end }
local engineInterface = { upgradeConstruction = function(id, file, prm)
	upgrades[#upgrades + 1] = { id, file, prm }
	fakeLanes = network.laneCount()
end }
_G.game = { interface = guiInterface }
api.res = { streetTypeRep = { getName = function(i) return i end } }
entities[77] = "edge"
-- a 1.5 warehouse: 21 terminals and one-way gate stubs, but without the 1.6 crossovers
fakeTerminals = #network.build().terminals
fakeStreet = network.GATE_STREET
fakeLanes = network.laneCount() - 12
local strings = (function() dofile("strings.lua") return data().en end)()
_G._ = function(s) return strings[s] or s end
params = { twp_storage = 5, seed = 99 }
printed = {}
print = function(s) printed[#printed + 1] = s end
script()
gs = data()
for _ = 1, 29 do gs.guiUpdate() end
local before = windows
gs.guiUpdate()
check(before == 0 and windows == 1, "popup appears once, after the UI has settled")
local buttons = {}
for b in pairs(clicks) do buttons[#buttons + 1] = b end
check(#buttons == 2, "popup has two buttons")
for _, b in ipairs(buttons) do
	clicks[b]() -- "Not now" only closes; "Rebuild now" queues the work
end
check(#events == 0, "nothing sent inside the click handler itself")
gs.guiUpdate()
check(#upgrades == 0, "the GUI thread does not rebuild")
check(#events == 1 and events[1][2] == "rebuild" and events[1][3].ids[1] == 50, "the GUI asks the engine to rebuild warehouse 50")
-- deliver the event on the "engine thread"
_G.game = { interface = engineInterface }
gs.handleEvent("truck_warehouse_plus.lua", events[1] and events[1][1], "rebuild", events[1] and events[1][3])
gs.handleEvent("other", "__someone_else__", "rebuild", { ids = { 50 } })
_G.game = { interface = guiInterface }
check(#upgrades == 1 and upgrades[1][1] == 50 and upgrades[1][2] == "assets/dhl_warenlager.con", "warehouse 50 rebuilt once")
check(upgrades[1] and upgrades[1][3].twp_storage == 5 and upgrades[1][3].seed == nil, "rebuilt with its own settings, no seed")
for _ = 1, 60 do gs.guiUpdate() end
print = realPrint
local sawDone = false
for _, t in ipairs(texts) do if tostring(t):find("Rebuilt 1 of 1") then sawDone = true end end
check(sawDone, "popup reports the result")
for _ = 1, 50 do gs.guiUpdate() end
check(windows == 1, "popup is not shown again in the same session")
for _, s in ipairs(printed) do check(not s:find("failed"), "script error: " .. s) end

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
