-- Transport network (lanes + terminals) of the truck warehouse.
--
-- The original model had one truck loop around the site, two kerbside lay-bys on the
-- south road (terminals 1 and 2) and a stack of cargo "shelf" lanes in the hall's east
-- extension. The model itself paints 13 loading bays with a dock door each along the
-- north wall of the hall, but none of them were terminals. This file keeps everything
-- the original had and adds one terminal per painted bay (terminals 3..15).
--
-- Indices: TpF2 wants node and edge numbers that are global across all lane lists
-- (edge e owns nodes 2e and 2e+1). Everything below is written against edge handles;
-- build() resolves the numbers at the very end, so adding an edge anywhere never
-- silently breaks a terminal.
--
-- Coordinates are model space (metres), identical to the meshes (identity transforms).
-- Measured from res/models/mesh/dhltest/dhl_linien.msh: bay lines at
-- x = -106.44 + 4.125 * i (i = 0..13), from the wall at y = -19.95 out to y = -2.45.
-- Hall floor (dhl_innen.msh) is at z = 1.0.

local M = {}

M.BAY_COUNT = 13
M.BAY_X0 = -104.375 -- centre of the westernmost bay
M.BAY_DX = 4.125 -- bay pitch
M.WALL_Y = -19.95 -- dock wall (bay lines end here)
M.MOUTH_Y = -2.45 -- open end of the bays
M.AISLE_Y = 4.0 -- one-way westbound aisle between the bays and the traffic island
M.TURN_R = 6.0 -- radius of the 90-degree turns aisle <-> bay
M.IN_OFFSET = 1.5 -- entry leg runs this far east of the bay centre
M.HAIRPIN_Y = -18.0 -- where the in-bay U-turn starts (dips 1.5 m further, to -19.5)
M.HAIRPIN_K = 6.0 -- tangent length of the U-turn (dip = K / 4)
M.STOP_Y = -2.0 -- vehicle node: cab at the bay mouth, trailer back against the door
M.FLOOR_Z = 1.0
M.CORRIDOR_Y = -23.0 -- cargo corridor inside the hall, just behind the doors
M.DOOR_Y = -20.5

-- Hermite tangent length that makes a cubic edge follow a quarter circle of radius r
-- (3 x the usual Bezier handle 0.5523 r).
local function quarter(r)
	return r * 4 * (math.sqrt(2) - 1)
end

function M.bayCenter(k)
	return M.BAY_X0 + (k - 1) * M.BAY_DX
end

---------------------------------------------------------------------------
-- builder

local function newBuilder()
	local b = { lists = {}, order = {} }

	function b.list(name, modes, width)
		local l = { name = name, modes = modes, width = width or 1.0, edges = {} }
		b.lists[name] = l
		b.order[#b.order + 1] = l
		return l
	end

	-- p0, p1: positions; t0, t1: tangents (Hermite, so a straight edge uses p1 - p0)
	function b.edge(list, p0, t0, p1, t1)
		local e = { list = list, p0 = p0, t0 = t0, p1 = p1, t1 = t1 }
		list.edges[#list.edges + 1] = e
		return e
	end

	function b.straight(list, p0, p1)
		local t = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
		return b.edge(list, p0, t, p1, t)
	end

	return b
end

-- resolve handles to the numbers TpF2 expects
local function finalize(b, terminals)
	local edgeIndex = {}
	local laneLists = {}
	local n = 0
	for _, l in ipairs(b.order) do
		local nodes = {}
		for _, e in ipairs(l.edges) do
			edgeIndex[e] = n
			n = n + 1
			nodes[#nodes + 1] = { e.p0, e.t0, l.width }
			nodes[#nodes + 1] = { e.p1, e.t1, l.width }
		end
		laneLists[#laneLists + 1] = { nodes = nodes, transportModes = l.modes }
	end

	local function edgeId(e)
		local i = edgeIndex[e]
		assert(i ~= nil, "terminal references an edge that is not in any lane list")
		return i
	end
	-- node handle = { edge, 0 = start | 1 = end }
	local function nodeId(h)
		return 2 * edgeId(h[1]) + h[2]
	end

	local out = {}
	for i, t in ipairs(terminals) do
		local personEdges = {}
		for _, e in ipairs(t.personEdges) do personEdges[#personEdges + 1] = edgeId(e) end
		local personNodes = {}
		for _, h in ipairs(t.personNodes) do personNodes[#personNodes + 1] = nodeId(h) end
		out[i] = {
			order = i - 1,
			personEdges = personEdges,
			personNodes = personNodes,
			vehicleNode = nodeId(t.vehicleNode),
		}
	end

	return { laneLists = laneLists, terminals = out }
end

---------------------------------------------------------------------------
-- original network (unchanged geometry, from the 2021 dhl_path.mdl by RPGFabi /
-- elektronikfreak); only the west edge of the north road is split in two so the new
-- aisle can join it.

local function originalTruckLanes(b, truck)
	local E = function(x0, y0, tx0, ty0, x1, y1, tx1, ty1)
		return b.edge(truck, { x0, y0, 0 }, { tx0, ty0, 0 }, { x1, y1, 0 }, { tx1, ty1, 0 })
	end
	local r = {}
	-- loop: enters from the north street stub, runs anticlockwise round the site,
	-- leaves through the south street stub
	E(15.5, -0.65701, -10.9, 0, 4.6, 0, -10.9, 0)
	E(4.6, 0, -24.6, 0, -20, 0, -24.6, 0)
	E(-20, 0, -40, 0, -60, 19, -40, 0)
	r.northA = E(-60, 19, -60.375, 0, -120.375, 19, -60.375, 0) -- was one edge to -134
	r.northB = E(-120.375, 19, -13.625, 0, -134, 19, -13.625, 0)
	E(-134, 19, -16, 0, -144, 10, 0, -7)
	E(-144, 10, 0, -60, -144, -50, 0, -60)
	E(-144, -50, 0, -25, -133, -61, 7, 0)
	E(-133, -61, 6, 0, -127, -61, 6, 0)
	E(-127, -61, 28, 0, -99, -61, 28, 0)
	E(-99, -61, 28, 0, -71, -61, 28, 0)
	E(-71, -61, 28, 0, -43, -61, 28, 0)
	E(-43, -61, 47.6, 0, 4.6, -61, 47.6, 0)
	E(4.6, -61, 10.9, 0, 15.5, -60.0858, 10.9, 0)
	-- lay-by 1
	E(-99, -61, 10, 0, -89, -55.5, 10, 0)
	r.stop1 = E(-89, -55.5, 4, 0, -85, -55.5, 4, 0)
	r.stop1b = E(-85, -55.5, 4, 0, -81, -55.5, 4, 0)
	E(-81, -55.5, 10, 0, -71, -61, 10, 0)
	-- lay-by 2
	E(-71, -61, 10, 0, -61, -55.5, 10, 0)
	r.stop2 = E(-61, -55.5, 4, 0, -57, -55.5, 4, 0)
	r.stop2b = E(-57, -55.5, 4, 0, -53, -55.5, 4, 0)
	E(-53, -55.5, 10, 0, -43, -61, 10, 0)
	return r
end

local function originalCargoLanes(b, cargo)
	local r = { shelves = {} }
	-- 6 shelf levels (z = 0, 2, .., 10) x 5 rows (x = -37, -35, .., -29), 20 m each
	for level = 0, 5 do
		for row = 0, 4 do
			local x, z = -37 + 2 * row, 2 * level
			r.shelves[#r.shelves + 1] = b.straight(cargo, { x, -45, z }, { x, -25, z })
		end
	end
	-- cross connections at the north end of every level
	for level = 0, 5 do
		for row = 0, 3 do
			local x, z = -37 + 2 * row, 2 * level
			b.straight(cargo, { x, -25, z }, { x + 2, -25, z })
		end
	end
	-- ladder up the north-east corner
	for level = 0, 4 do
		b.straight(cargo, { -29, -25, 2 * level }, { -29, -25, 2 * level + 2 })
	end
	-- accesses to the two street sidewalks
	b.edge(cargo, { 7.5, -52.0858, 0 }, { -36.5, 7, 0 }, { -29, -45, 0 }, { -36.5, 7, 0 })
	r.hub = b.edge(cargo, { -29, -25, 0 }, { 21.5, 17.5, 0 }, { 7.5, -8.65701, 0 }, { 21.5, 17.5, 0 })
	return r
end

---------------------------------------------------------------------------
-- new: one terminal per painted loading bay

local function dockTruckLanes(b, truck, orig)
	local A, R, q = M.AISLE_Y, M.TURN_R, quarter(M.TURN_R)
	local function P(x, y) return { x, y, 0 } end
	local function T(x, y) return { x, y, 0 } end

	-- aisle x-coordinates: every point where a bay entry leaves or a bay exit joins
	local cuts = {}
	local bays = {}
	for k = 1, M.BAY_COUNT do
		local xc = M.bayCenter(k)
		local xin = xc + M.IN_OFFSET
		bays[k] = { xc = xc, xin = xin, enterAt = xin + R, leaveAt = xc - R }
		cuts[#cuts + 1] = xin + R
		cuts[#cuts + 1] = xc - R
	end
	local aisleStartX = -44.0
	cuts[#cuts + 1] = aisleStartX
	table.sort(cuts, function(a, c) return a > c end) -- east -> west, travel direction

	-- connector from the loop's junction at (-20, 0) into the aisle
	b.edge(truck, P(-20, 0), T(-24, 0), P(aisleStartX, A), T(-24, 0))
	for i = 1, #cuts - 1 do
		if cuts[i] - cuts[i + 1] > 1e-6 then
			b.straight(truck, P(cuts[i], A), P(cuts[i + 1], A))
		end
	end
	local aisleEndX = cuts[#cuts]

	-- aisle -> north road, round the north-east corner of the west annex
	local x0 = aisleEndX
	b.edge(truck, P(x0, A), T(-quarter(4), 0), P(x0 - 4, A + 4), T(0, quarter(4))) -- right turn, r = 4
	b.straight(truck, P(x0 - 4, A + 4), P(x0 - 4, 13))
	assert(math.abs((x0 - 4 - R) - (-120.375)) < 1e-9, "aisle exit must meet the split point of the north road")
	b.edge(truck, P(x0 - 4, 13), T(0, q), P(x0 - 4 - R, 19), T(-q, 0)) -- left turn, r = 6

	for k = 1, M.BAY_COUNT do
		local bay = bays[k]
		local xc, xin = bay.xc, bay.xin
		-- left turn off the aisle into the bay's east half
		b.edge(truck, P(xin + R, A), T(-q, 0), P(xin, A - R), T(0, -q))
		b.straight(truck, P(xin, A - R), P(xin, M.HAIRPIN_Y))
		-- U-turn at the dock door (clockwise: south -> west -> north)
		b.edge(truck, P(xin, M.HAIRPIN_Y), T(0, -M.HAIRPIN_K), P(xc, M.HAIRPIN_Y), T(0, M.HAIRPIN_K))
		-- pull forward to the bay mouth: the trailer ends up backed onto the door
		b.straight(truck, P(xc, M.HAIRPIN_Y), P(xc, M.STOP_Y))
		-- left turn back onto the aisle
		bay.leave = b.edge(truck, P(xc, M.STOP_Y), T(0, q), P(xc - R, A), T(-q, 0))
	end
	return bays
end

local function dockCargoLanes(b, cargo, orig, bays)
	local z, cy = M.FLOOR_Z, M.CORRIDOR_Y
	-- corridor behind the doors, west -> east, then down to the shelf hub
	local xs = {}
	for k = 1, M.BAY_COUNT do xs[k] = bays[k].xc end
	for i = 1, #xs - 1 do
		b.straight(cargo, { xs[i], cy, z }, { xs[i + 1], cy, z })
	end
	b.straight(cargo, { xs[#xs], cy, z }, { -46, cy, z })
	b.straight(cargo, { -46, cy, z }, { -37, -25, 0 }) -- joins shelf row x=-37 at ground level
	for k = 1, M.BAY_COUNT do
		bays[k].dock = b.straight(cargo, { bays[k].xc, cy, z }, { bays[k].xc, M.DOOR_Y, z })
	end
end

---------------------------------------------------------------------------

function M.build()
	local b = newBuilder()
	local truck = b.list("truck", { "TRUCK" })
	local cargo = b.list("cargo", { "CARGO" })

	local ot = originalTruckLanes(b, truck)
	local bays = dockTruckLanes(b, truck, ot)
	local oc = originalCargoLanes(b, cargo)
	dockCargoLanes(b, cargo, oc, bays)

	local terminals = {}
	-- terminals 1 and 2: the original lay-bys, same order as before so existing lines keep them
	local shelvesA, shelvesB = {}, {}
	for i = 1, 15 do shelvesA[i] = oc.shelves[i] end
	for i = 16, 30 do shelvesB[#shelvesB + 1] = oc.shelves[i] end
	terminals[1] = { vehicleNode = { ot.stop1b, 0 }, personEdges = shelvesA, personNodes = { { shelvesA[1], 0 } } }
	-- (the original pointed this terminal's personNodes at a truck lane node, a copy/paste slip)
	terminals[2] = { vehicleNode = { ot.stop2b, 0 }, personEdges = shelvesB, personNodes = { { shelvesB[1], 0 } } }
	-- terminals 3..15: loading bays, west to east
	for k = 1, M.BAY_COUNT do
		local bay = bays[k]
		terminals[#terminals + 1] = {
			vehicleNode = { bay.leave, 0 },
			personEdges = { bay.dock },
			personNodes = { { bay.dock, 0 }, { bay.dock, 1 } },
		}
	end

	return finalize(b, terminals)
end

return M
