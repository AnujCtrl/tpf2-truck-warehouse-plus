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
M.AISLE_Y = 6.5 -- one-way westbound aisle between the bays and the traffic island
M.TURN_R = 6.0 -- radius of the left turn aisle -> bay
M.EXIT_R = 4.0 -- radius of the left turn bay -> exit lane
M.IN_OFFSET = 1.5 -- entry leg runs this far east of the bay centre
M.HAIRPIN_Y = -18.0 -- where the in-bay U-turn starts (dips 1.5 m further, to -19.5)
M.HAIRPIN_K = 6.0 -- tangent length of the U-turn (dip = K / 4)
M.STOP_Y = -2.0 -- vehicle node: cab at the bay mouth, trailer back against the door
M.EXIT_Y = M.STOP_Y + M.EXIT_R -- westbound exit lane along the bay mouths

-- Gates (1.5): both street stubs are one-way two-lane roads, so each gate's two lanes run the
-- same way. North gate = way in, south gate = way out. Lanes sit 2 m either side of the stub's
-- centre line (y = -2.657 north, -58.086 south), where the street's own lanes are.
M.GATE_STREET = "standard/country_medium_one_way_new.lua"
M.GATE_IN_N = { 15.5, -0.65701 } -- original way in: loop (lay-bys) and parking slots
M.GATE_IN_S = { 15.5, -4.65701 } -- second way in: the bays
M.GATE_OUT_OUTER = { 15.5, -60.0858 } -- original way out: lay-bys and parking slots
M.GATE_OUT_INNER = { 15.5, -56.0858 } -- second way out: the bays
-- 1.6: which gate lane a truck ends up in is decided by the player's roads (in game, every truck
-- turning in from the main road landed in the north lane, and the bays' exit lane fed straight
-- back into the entrance). With one stream per lane that sent trucks out and back in again.
-- Crossovers just inside each gate let either lane reach everything; the direct lane stays the
-- shorter route, so trucks only use a crossover when the street left them in the other lane.
M.IN_CROSS_X0, M.IN_CROSS_X1 = -3.0, -16.0 -- north gate: crossovers from x0 (west of the gatehouse) to x1
M.OUT_CROSS = { -24.0, -22.0, -8.0, -6.0 } -- south gate: outer->inner from [1] to [4], inner->outer [2] to [3]

-- The loop is two lanes from where the bays join it to the south gate. The outer lane is the
-- original loop (lay-bys, parking); the inner one runs parallel inside it and carries the bays.
M.WEST_EXIT_X = -110.375 -- where the bays' exit lane turns north
M.INNER_NORTH_Y = 15.5 -- original north road: y = 19
M.INNER_WEST_X = -140.0 -- original west road: x = -144
M.INNER_SOUTH_Y = -58.0 -- original south road: y = -61; lay-by stops at -55.5 (2.5 m: a truck width)
M.PARK_MERGE_X = -64.0 -- where the parking slots' exit joins the north road

-- Truck parking slots inside the north gate (painted in dhl_linien.msh: stripes at
-- y = 14.1 + 3.65 i, x = -17.33 .. 0.67; the first slot is bounded by the gate island).
M.PARK_COUNT = 6
M.PARK_C1 = 12.275 -- centre line of the slot next to the gate island
M.PARK_PITCH = 3.65
M.PARK_X0 = -17.33 -- open (west) end of the slots
M.PARK_X1 = 0.67 -- closed (east) end, against the yard fence at x = 1.27
M.PARK_OFFSET = 1.5 -- in-lane runs this far south of the out-lane (both inside the slot)
M.PARK_HAIRPIN_X = -1.75 -- U-turn start (bulges K/4 = 1.5 m further east)
M.PARK_STOP_X = -17.75 -- vehicle node: cab at the slot mouth
-- a barrier bar (dhl_gelaende, ~2.4 m up) spans x = -2.55, y = 2.5 .. 13.8 across the end of the
-- first slot, so that slot turns before it and its parked leg is 14 m instead of 16
M.BAR = { x = -2.55, y0 = 2.47, y1 = 13.77 }
M.PARK_FIRST_HAIRPIN_X = -5.5
M.PARK_FIRST_STOP_X = -19.5
M.FEEDER_X = -24.0 -- northbound lane past the west end of the gate island
M.COLLECTOR_Y = 21.25 -- westbound lane collecting the slots' exits
M.FLOOR_Z = 1.0
M.CORRIDOR_Y = -23.0 -- cargo corridor inside the hall, just behind the doors
M.DOOR_Y = -20.5

-- Hermite tangent length that makes a cubic edge follow a quarter circle of radius r
-- (3 x the usual Bezier handle 0.5523 r).
local function quarter(r)
	return r * 4 * (math.sqrt(2) - 1)
end

-- number of lanes (edges) in the layout; the warehouse's transport network has exactly these,
-- as no other model of the construction carries lanes (fence_metal.mdl and the brand signs
-- have none)
function M.laneCount()
	local n = 0
	for _, l in ipairs(M.build().laneLists) do n = n + #l.nodes / 2 end
	return n
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
-- elektronikfreak), edge for edge, except that three straight edges are cut into collinear
-- pieces where new lanes join or leave them (north road, entry road, exit road).

local function originalTruckLanes(b, truck)
	local E = function(x0, y0, tx0, ty0, x1, y1, tx1, ty1)
		return b.edge(truck, { x0, y0, 0 }, { tx0, ty0, 0 }, { x1, y1, 0 }, { tx1, ty1, 0 })
	end
	local r = {}
	-- loop: enters from the north street stub, runs anticlockwise round the site,
	-- leaves through the south street stub
	E(15.5, -0.65701, -10.9, 0, 4.6, 0, -10.9, 0)
	-- (cut where the north gate's crossover leaves it)
	local cx = M.IN_CROSS_X0
	E(4.6, 0, cx - 4.6, 0, cx, 0, cx - 4.6, 0)
	E(cx, 0, -20 - cx, 0, -20, 0, -20 - cx, 0)
	E(-20, 0, -40, 0, -60, 19, -40, 0)
	-- north road: one straight edge in the original, cut where the parking exit joins it
	-- (same line, tangents scaled to each piece)
	local px = M.PARK_MERGE_X
	E(-60, 19, px + 60, 0, px, 19, px + 60, 0)
	E(px, 19, -134 - px, 0, -134, 19, -134 - px, 0)
	E(-134, 19, -16, 0, -144, 10, 0, -7)
	E(-144, 10, 0, -60, -144, -50, 0, -60)
	E(-144, -50, 0, -25, -133, -61, 7, 0)
	E(-133, -61, 6, 0, -127, -61, 6, 0)
	E(-127, -61, 28, 0, -99, -61, 28, 0)
	E(-99, -61, 28, 0, -71, -61, 28, 0)
	E(-71, -61, 28, 0, -43, -61, 28, 0)
	-- (cut where the south gate's crossovers leave and join it)
	local oa, ob = M.OUT_CROSS[1], M.OUT_CROSS[3]
	E(-43, -61, oa + 43, 0, oa, -61, oa + 43, 0)
	E(oa, -61, ob - oa, 0, ob, -61, ob - oa, 0)
	E(ob, -61, 4.6 - ob, 0, 4.6, -61, 4.6 - ob, 0)
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

-- Bay traffic (1.5):
--   in:  north gate, south lane -> along the yard road's south side -> westbound aisle -> left
--        turn into the bay's east half -> U-turn at the door -> stop at the bay mouth facing out
--   out: left turn onto a westbound exit lane along the bay mouths -> north at the west end ->
--        the loop's inner lane -> round the site -> south gate, inner lane
-- The north gate's north lane, the loop's outer lane and the south gate's outer lane belong to
-- the lay-bys and parking slots, so bay traffic never shares a lane with them.
-- (1.0 sent every bay round the single-lane loop, 1.2 every bay out through the north gate,
-- 1.3 split them between the gates; each version jammed a single lane somewhere.)
local function dockTruckLanes(b, truck, orig)
	local A, R, q = M.AISLE_Y, M.TURN_R, quarter(M.TURN_R)
	local XR, XQ, XY = M.EXIT_R, quarter(M.EXIT_R), M.EXIT_Y
	local function P(x, y) return { x, y, 0 } end
	local function T(x, y) return { x, y, 0 } end

	local bays = {}
	for k = 1, M.BAY_COUNT do
		local xc = M.bayCenter(k)
		bays[k] = { xc = xc, xin = xc + M.IN_OFFSET }
	end

	-- way in: the north gate's south lane, straight in past the gatehouse, then up onto the
	-- aisle south of the loop's entry curve (which climbs faster, so they never cross)
	local gx, gy = M.GATE_IN_S[1], M.GATE_IN_S[2]
	local bendX, aisleStartX = -22.0, -44.0
	local c0, c1 = M.IN_CROSS_X0, M.IN_CROSS_X1
	b.straight(truck, P(gx, gy), P(c0, gy))
	b.straight(truck, P(c0, gy), P(c1, gy))
	b.straight(truck, P(c1, gy), P(bendX, gy))
	-- crossovers (an X): south lane -> the north lane's junction at (-20, 0), north lane -> south lane
	b.edge(truck, P(c0, gy), T(-20 - c0, 0), P(-20, 0), T(-20 - c0, 0))
	b.edge(truck, P(c0, 0), T(c1 - c0, 0), P(c1, gy), T(c1 - c0, 0))
	b.edge(truck, P(bendX, gy), T(aisleStartX - bendX, 0), P(aisleStartX, A), T(aisleStartX - bendX, 0))
	-- aisle: cut at every bay entry, ends at the westernmost one
	local x = aisleStartX
	for k = M.BAY_COUNT, 1, -1 do
		local enterAt = bays[k].xin + R
		b.straight(truck, P(x, A), P(enterAt, A))
		x = enterAt
	end

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
		-- left turn onto the westbound exit lane
		bay.leave = b.edge(truck, P(xc, M.STOP_Y), T(0, XQ), P(xc - XR, XY), T(-XQ, 0))
	end

	-- exit lane: west along the bay mouths, joined by every bay ...
	for k = M.BAY_COUNT, 2, -1 do
		b.straight(truck, P(bays[k].xc - XR, XY), P(bays[k - 1].xc - XR, XY))
	end
	-- ... north at the west end, round the north-east corner of the west annex ...
	local x0, q4 = M.WEST_EXIT_X, quarter(4)
	local NY, WX, SY = M.INNER_NORTH_Y, M.INNER_WEST_X, M.INNER_SOUTH_Y
	b.straight(truck, P(bays[1].xc - XR, XY), P(x0, XY))
	b.edge(truck, P(x0, XY), T(-q4, 0), P(x0 - 4, XY + 4), T(0, q4)) -- right turn, r = 4
	b.straight(truck, P(x0 - 4, XY + 4), P(x0 - 4, NY - 4))
	b.edge(truck, P(x0 - 4, NY - 4), T(0, q4), P(x0 - 8, NY), T(-q4, 0)) -- left turn, r = 4
	-- ... and the loop's inner lane: west, south, east to the south gate
	local rNW, rSW = 9.0, 7.75
	b.straight(truck, P(x0 - 8, NY), P(WX + rNW, NY))
	b.edge(truck, P(WX + rNW, NY), T(-quarter(rNW), 0), P(WX, NY - rNW), T(0, -quarter(rNW)))
	b.straight(truck, P(WX, NY - rNW), P(WX, SY + rSW))
	b.edge(truck, P(WX, SY + rSW), T(0, -quarter(rSW)), P(WX + rSW, SY), T(quarter(rSW), 0))
	local ox, oy = M.GATE_OUT_INNER[1], M.GATE_OUT_INNER[2]
	local riseX = -36.0
	local x1, x2, x3, x4 = M.OUT_CROSS[1], M.OUT_CROSS[2], M.OUT_CROSS[3], M.OUT_CROSS[4]
	b.straight(truck, P(WX + rSW, SY), P(riseX, SY))
	b.edge(truck, P(riseX, SY), T(x1 - riseX, 0), P(x1, oy), T(x1 - riseX, 0))
	b.straight(truck, P(x1, oy), P(x2, oy))
	b.straight(truck, P(x2, oy), P(x4, oy))
	b.straight(truck, P(x4, oy), P(ox, oy))
	-- crossovers (an X) to the outer exit lane at y = -61 and back
	b.edge(truck, P(x2, oy), T(x3 - x2, 0), P(x3, -61), T(x3 - x2, 0))
	b.edge(truck, P(x1, -61), T(x4 - x1, 0), P(x4, oy), T(x4 - x1, 0))
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
-- new: one terminal per painted truck parking slot inside the north gate

function M.parkCenter(k)
	return M.PARK_C1 + (k - 1) * M.PARK_PITCH
end

-- in:  north gate -> right turn past the west end of the gate island -> north along the
--      feeder -> right turn into the slot -> U-turn at the fence end -> stop at the slot mouth
-- out: west across the feeder -> onto a westbound collector -> joins the loop's north road
--      -> south gate (going out through the north gate would cross its incoming lane)
local function parkingTruckLanes(b, truck)
	local function P(x, y) return { x, y, 0 } end
	local function T(x, y) return { x, y, 0 } end
	local fx, er = M.FEEDER_X, 3.0
	local slots = {}
	for k = 1, M.PARK_COUNT do
		local c = M.parkCenter(k)
		slots[k] = { c = c, yin = c - M.PARK_OFFSET / 2, yout = c + M.PARK_OFFSET / 2,
			hx = k == 1 and M.PARK_FIRST_HAIRPIN_X or M.PARK_HAIRPIN_X,
			sx = k == 1 and M.PARK_FIRST_STOP_X or M.PARK_STOP_X }
	end

	-- feeder: off the loop's junction at (-20, 0), round the gate island, north past every slot
	local q4 = quarter(4)
	b.edge(truck, P(-20, 0), T(-q4, 0), P(fx, 4), T(0, q4)) -- right turn, r = 4
	local y = 4
	for k = 1, M.PARK_COUNT do
		local at = slots[k].yin - er
		b.straight(truck, P(fx, y), P(fx, at))
		y = at
		-- right turn into the slot, then east along its south half
		local q3 = quarter(er)
		b.edge(truck, P(fx, at), T(0, q3), P(fx + er, slots[k].yin), T(q3, 0))
		local s = slots[k]
		b.straight(truck, P(fx + er, s.yin), P(s.hx, s.yin))
		-- U-turn at the fence end (anticlockwise: east -> north -> west)
		b.edge(truck, P(s.hx, s.yin), T(6, 0), P(s.hx, s.yout), T(-6, 0))
		b.straight(truck, P(s.hx, s.yout), P(s.sx, s.yout))
	end

	-- exits: each slot curves onto the collector; slots nearest the collector join first so
	-- the curves never cross each other
	local order = {}
	for k = 1, M.PARK_COUNT do order[k] = k end
	table.sort(order, function(a, c)
		return math.abs(slots[a].yout - M.COLLECTOR_Y) < math.abs(slots[c].yout - M.COLLECTOR_Y)
	end)
	local cy, mx = M.COLLECTOR_Y, -28.0
	local prev
	for _, k in ipairs(order) do
		local s = slots[k]
		local dx = mx - s.sx
		s.leave = b.edge(truck, P(s.sx, s.yout), T(dx, 0), P(mx, cy), T(dx, 0))
		if prev then b.straight(truck, P(prev, cy), P(mx, cy)) end
		prev = mx
		mx = mx - 4
	end
	local endX = -52.0
	b.straight(truck, P(prev, cy), P(endX, cy))
	local px = M.PARK_MERGE_X
	b.edge(truck, P(endX, cy), T(px - endX, 0), P(px, 19), T(px - endX, 0))
	return slots
end

local function parkingCargoLanes(b, cargo, oc, slots)
	-- cargo waits along each slot; a lane up the slot mouths links them, and runs to the
	-- north-gate sidewalk end of the original cargo network
	local x0, x1 = -16.0, -3.0
	for k = 1, M.PARK_COUNT do
		slots[k].cargo = b.straight(cargo, { x0, slots[k].c, 0 }, { k == 1 and -6.0 or x1, slots[k].c, 0 })
	end
	for k = 1, M.PARK_COUNT - 1 do
		b.straight(cargo, { x0, slots[k].c, 0 }, { x0, slots[k + 1].c, 0 })
	end
	b.straight(cargo, { x0, slots[1].c, 0 }, { 7.5, -8.65701, 0 })
end

---------------------------------------------------------------------------

function M.build()
	local b = newBuilder()
	local truck = b.list("truck", { "TRUCK" })
	local cargo = b.list("cargo", { "CARGO" })

	local ot = originalTruckLanes(b, truck)
	local bays = dockTruckLanes(b, truck, ot)
	local slots = parkingTruckLanes(b, truck)
	local oc = originalCargoLanes(b, cargo)
	dockCargoLanes(b, cargo, oc, bays)
	parkingCargoLanes(b, cargo, oc, slots)

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
	-- terminals 16..21: parking slots, from the gate island outwards (appended, so the
	-- numbers of the terminals above never change)
	for k = 1, M.PARK_COUNT do
		local s = slots[k]
		terminals[#terminals + 1] = {
			vehicleNode = { s.leave, 0 },
			personEdges = { s.cargo },
			personNodes = { { s.cargo, 0 }, { s.cargo, 1 } },
		}
	end

	return finalize(b, terminals)
end

return M
