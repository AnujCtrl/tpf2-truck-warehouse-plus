-- Headless checks for the truck warehouse network and constructions.
-- Run from the repo root:  lua5.2 test/run.lua
-- Needs the game's res/scripts for the construction tests (constructionutil etc.);
-- set TPF2_DIR if the game is not in the default Steam library.

local GAME = os.getenv("TPF2_DIR") or (os.getenv("HOME") .. "/.local/share/Steam/steamapps/common/Transport Fever 2")
package.path = "res/scripts/?.lua;" .. GAME .. "/res/scripts/?.lua;" .. package.path
_G._ = function(s) return s end

local network = require "truck_warehouse_plus/network"

local failures, checks = 0, 0
local function check(ok, msg)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		print("FAIL: " .. msg)
	end
end

local function key(p) return string.format("%.3f,%.3f,%.3f", p[1], p[2], p[3]) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

-- flatten a transportNetworkProvider into edges with their list's modes
local function edgesOf(tnp)
	local out, nodes = {}, {}
	for _, l in ipairs(tnp.laneLists) do
		for i = 1, #l.nodes, 2 do
			local e = { a = l.nodes[i], b = l.nodes[i + 1], modes = l.transportModes, index = #out }
			out[#out + 1] = e
			nodes[#nodes + 1] = { node = l.nodes[i], edge = e }
			nodes[#nodes + 1] = { node = l.nodes[i + 1], edge = e }
		end
	end
	return out, nodes
end

local function hasMode(e, m)
	for _, x in ipairs(e.modes) do if x == m then return true end end
	return false
end

local function hermite(e, s)
	local p0, t0, p1, t1 = e.a[1], e.a[2], e.b[1], e.b[2]
	local h00 = 2 * s ^ 3 - 3 * s ^ 2 + 1
	local h10 = s ^ 3 - 2 * s ^ 2 + s
	local h01 = -2 * s ^ 3 + 3 * s ^ 2
	local h11 = s ^ 3 - s ^ 2
	local r = {}
	for c = 1, 3 do r[c] = h00 * p0[c] + h10 * t0[c] + h01 * p1[c] + h11 * t1[c] end
	return r
end

local function sameNode(n1, n2)
	for c = 1, 3 do
		if not near(n1[1][c], n2[1][c]) or not near(n1[2][c], n2[2][c]) then return false end
	end
	return true
end

---------------------------------------------------------------------------
local new = network.build()
local edges, nodes = edgesOf(new)

local f = assert(loadfile("test/fixtures/dhl_path.original.mdl"))
f()
local orig = data().metadata.transportNetworkProvider
local oedges, onodes = edgesOf(orig)

-- 1. every original edge survives, unchanged; the straight north road may be cut into
-- collinear pieces that still run exactly from x = -60 to x = -134 at y = 19
local function northRoadIntact()
	local from, seen = {}, 0
	for _, ne in ipairs(edges) do
		if hasMode(ne, "TRUCK") and ne.a[1][2] == 19 and ne.b[1][2] == 19 and ne.a[2][2] == 0 and ne.b[2][2] == 0
			and ne.a[1][1] <= -60 and ne.b[1][1] >= -134 and ne.b[1][1] < ne.a[1][1] then
			from[ne.a[1][1]] = ne
			seen = seen + 1
		end
	end
	local x, pieces = -60, 0
	while from[x] do
		local ne = from[x]
		local len = ne.a[1][1] - ne.b[1][1]
		if not (near(ne.a[2][1], -len) and near(ne.b[2][1], -len)) then return false end
		x, pieces = ne.b[1][1], pieces + 1
	end
	return x == -134 and pieces == seen
end
for i, oe in ipairs(oedges) do
	local found = false
	for _, ne in ipairs(edges) do
		if sameNode(oe.a, ne.a) and sameNode(oe.b, ne.b) and hasMode(ne, oe.modes[1]) then found = true break end
	end
	if not found and key(oe.a[1]) == key({ -60, 19, 0 }) and key(oe.b[1]) == key({ -134, 19, 0 }) then
		found = northRoadIntact()
	end
	check(found, "original edge " .. (i - 1) .. " missing: " .. key(oe.a[1]) .. " -> " .. key(oe.b[1]))
end

-- 2. terminals 1 and 2 are the original ones, by position
local function vehiclePos(tnp, t)
	local _, ns = edgesOf(tnp)
	return key(ns[t.vehicleNode + 1].node[1])
end
local function personSet(tnp, t)
	local es = edgesOf(tnp)
	local s = {}
	for _, i in ipairs(t.personEdges) do s[#s + 1] = key(es[i + 1].a[1]) .. ">" .. key(es[i + 1].b[1]) end
	table.sort(s)
	return table.concat(s, "|")
end
local FIRST_PARK = 3 + network.BAY_COUNT
check(#new.terminals == 2 + network.BAY_COUNT + network.PARK_COUNT, "expected 21 terminals, got " .. #new.terminals)
for t = 1, 2 do
	check(vehiclePos(new, new.terminals[t]) == vehiclePos(orig, orig.terminals[t]), "terminal " .. t .. " vehicle node moved")
	check(personSet(new, new.terminals[t]) == personSet(orig, orig.terminals[t]), "terminal " .. t .. " person edges changed")
end

-- 3. index sanity
for i, t in ipairs(new.terminals) do
	check(t.order == i - 1, "terminal order " .. i)
	local vn = nodes[t.vehicleNode + 1]
	check(vn ~= nil and hasMode(vn.edge, "TRUCK"), "terminal " .. i .. " vehicle node not on a truck lane")
	for _, pe in ipairs(t.personEdges) do
		check(edges[pe + 1] ~= nil and hasMode(edges[pe + 1], "CARGO"), "terminal " .. i .. " person edge " .. pe .. " not cargo")
	end
	for _, pn in ipairs(t.personNodes) do
		check(nodes[pn + 1] ~= nil and hasMode(nodes[pn + 1].edge, "CARGO"), "terminal " .. i .. " person node " .. pn .. " not cargo")
	end
end
for _, l in ipairs(new.laneLists) do check(#l.nodes % 2 == 0, "odd node count in a lane list") end

-- 4. trucks: every terminal reachable from its way in, its way out reachable from it, the two
-- traffic streams (bays / lay-bys + parking) on separate gate lanes all the way through, and
-- no dead ends anywhere (one-way lanes, joined by position)
local out, inn = {}, {}
for _, e in ipairs(edges) do
	if hasMode(e, "TRUCK") then
		local a, b = key(e.a[1]), key(e.b[1])
		out[a] = out[a] or {}; table.insert(out[a], b)
		inn[b] = (inn[b] or 0) + 1
		out[b] = out[b] or {}
		inn[a] = inn[a] or 0
	end
end
local function gate(p) return key({ p[1], p[2], 0 }) end
local IN_N, IN_S = gate(network.GATE_IN_N), gate(network.GATE_IN_S)
local OUT_OUTER, OUT_INNER = gate(network.GATE_OUT_OUTER), gate(network.GATE_OUT_INNER)
check(IN_N == key({ 15.5, -0.65701, 0 }) and OUT_OUTER == key({ 15.5, -60.0858, 0 }), "original gate lanes moved")
-- every gate lane is one of the street's lanes: stub centre +- 2 m
check(near(network.GATE_IN_N[2], -2.65701 + 2, 1e-4) and near(network.GATE_IN_S[2], -2.65701 - 2, 1e-4), "north gate lanes off the street lanes")
check(near(network.GATE_OUT_INNER[2], -58.0858 + 2, 1e-4) and near(network.GATE_OUT_OUTER[2], -58.0858 - 2, 1e-4), "south gate lanes off the street lanes")
local function reach(from)
	local seen, q = { [from] = true }, { from }
	while #q > 0 do
		local n = table.remove(q)
		for _, m in ipairs(out[n] or {}) do
			if not seen[m] then seen[m] = true; q[#q + 1] = m end
		end
	end
	return seen
end
local fromN, fromS = reach(IN_N), reach(IN_S)
check(not fromN[OUT_INNER] and not fromS[OUT_OUTER], "the two ways in must not lead into each other's way out")
for i, t in ipairs(new.terminals) do
	local vp = key(nodes[t.vehicleNode + 1].node[1])
	local after = reach(vp)
	if i >= 3 and i < FIRST_PARK then
		check(fromS[vp] and not fromN[vp], "bay terminal " .. i .. " must be reached from the gate's south lane only")
		check(after[OUT_INNER] and not after[OUT_OUTER], "bay terminal " .. i .. " must leave by the inner lane only")
	else
		check(fromN[vp] and not fromS[vp], "terminal " .. i .. " must be reached from the gate's north lane only")
		check(after[OUT_OUTER] and not after[OUT_INNER], "terminal " .. i .. " must leave by the outer lane only")
	end
end
for n, succ in pairs(out) do
	check(#succ > 0 or n == OUT_OUTER or n == OUT_INNER, "truck dead end at " .. n)
	check((inn[n] or 0) > 0 or n == IN_N or n == IN_S, "truck node nobody drives into: " .. n)
end

-- 5. cargo: every terminal's waiting area is connected to both street sidewalks
local adj = {}
for _, e in ipairs(edges) do
	if hasMode(e, "CARGO") then
		local a, b = key(e.a[1]), key(e.b[1])
		adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
		table.insert(adj[a], b); table.insert(adj[b], a)
	end
end
local function connected(from, to)
	local seen, q = { [from] = true }, { from }
	while #q > 0 do
		local n = table.remove(q)
		if n == to then return true end
		for _, m in ipairs(adj[n] or {}) do
			if not seen[m] then seen[m] = true; q[#q + 1] = m end
		end
	end
	return false
end
for i, t in ipairs(new.terminals) do
	local p = key(edges[t.personEdges[1] + 1].a[1])
	check(connected(p, key({ 7.5, -52.0858, 0 })), "terminal " .. i .. " cargo not connected to the south sidewalk")
	check(connected(p, key({ 7.5, -8.65701, 0 })), "terminal " .. i .. " cargo not connected to the north sidewalk")
end

-- 6. geometry of the new truck lanes (lane centre lines; trucks are ~2.5 m wide)
local HALF = 1.25
local function inRect(p, x0, x1, y0, y1, m)
	return p[1] > x0 - m and p[1] < x1 + m and p[2] > y0 - m and p[2] < y1 + m
end
local origKeys = {}
for _, oe in ipairs(oedges) do origKeys[key(oe.a[1]) .. ">" .. key(oe.b[1])] = true end
for _, e in ipairs(edges) do
	if hasMode(e, "TRUCK") and not origKeys[key(e.a[1]) .. ">" .. key(e.b[1])] and e.a[1][2] ~= 19 then
		for s = 0, 1.0001, 0.02 do
			local p = hermite(e, s)
			check(not inRect(p, -104, -57, 9.9, 12.4, HALF), "lane hits the traffic island at " .. key(p))
			check(not inRect(p, -135, -119, -53, 12, HALF), "lane hits the west annex at " .. key(p))
			check(not (p[1] > -120 and p[1] < -42 and p[2] < network.WALL_Y + 0.4 and p[2] > -53 + HALF), "lane goes into the hall at " .. key(p))
			-- yard fence: north side (-145.6, 22.65) -> (-55.6, 22.65) -> (-34.7, 34.51) -> (1.27, 32.8),
			-- east side x = 1.27 from y = 8.77 up
			local fy
			if p[1] <= -55.6 then fy = 22.6542
			elseif p[1] <= -34.7 then fy = 22.6542 + (p[1] + 55.6) * (34.5142 - 22.6542) / (55.6 - 34.7)
			else fy = 34.5142 + (p[1] + 34.7) * (32.8 - 34.5142) / (34.7 + 1.27215) end
			check(p[2] < fy - HALF, "lane hits the north fence at " .. key(p))
			check(not (p[2] > 8.77 and p[1] > 1.27215 - HALF), "lane hits the east fence at " .. key(p))
			check(not inRect(p, network.BAR.x, network.BAR.x, network.BAR.y0, network.BAR.y1, HALF), "lane runs through the barrier bar at " .. key(p))
			if p[1] >= network.PARK_X0 and p[1] <= network.PARK_X1 and p[2] > 9 then
				-- inside the parking slots: stay in this slot (its painted stripes)
				local k = math.floor((p[2] - (network.PARK_C1 - network.PARK_PITCH / 2)) / network.PARK_PITCH) + 1
				check(k >= 1 and k <= network.PARK_COUNT, "parking lane outside the painted slots at " .. key(p))
				local c = network.parkCenter(k)
				check(math.abs(p[2] - c) <= network.PARK_OFFSET / 2 + 0.01, "parking lane leaves its slot at " .. key(p))
			end
			check(not inRect(p, -48.6, -42.2, -16, -2.6, HALF), "lane hits the striped island east of the bays at " .. key(p))
			check(not inRect(p, -2.2, 5.7, -3.3, -2.0, HALF), "lane hits the gatehouse island at " .. key(p))
			check(not inRect(p, -21.2, -2.8, 2.6, 8.4, HALF), "lane hits the gate's traffic island at " .. key(p))
			-- gate building between the gates: x -23 .. 7.18, y -52.48 (fence) .. -7.8
			check(not (p[1] > -23 and p[1] < 7.2 and p[2] < -7.8 + HALF and p[2] > -52.48 - HALF),
				"lane hits the gate building / fence at " .. key(p))
			local inBayArea = p[2] < network.MOUTH_Y and p[2] > network.WALL_Y - 2
				and p[1] > network.BAY_X0 - network.BAY_DX / 2 and p[1] < network.bayCenter(network.BAY_COUNT) + network.BAY_DX / 2
			if inBayArea then
				-- inside the bays: stay in this bay's own lane (centre .. centre + IN_OFFSET)
				local k = math.floor((p[1] - (network.BAY_X0 - network.BAY_DX / 2)) / network.BAY_DX) + 1
				local xc = network.bayCenter(k)
				check(k >= 1 and k <= network.BAY_COUNT, "bay lane outside the painted bays at " .. key(p))
				check(p[1] >= xc - 0.01 and p[1] <= xc + network.IN_OFFSET + 0.01, "bay lane leaves its bay at " .. key(p))
			end
		end
	end
end
-- new lanes keep a truck's width (2.5 m) from the original loop and its lay-by stops, except
-- where they branch off or merge (they share a node there) and where they cross the lay-bys'
-- in/out curves (those are crossings, by design)
do
	local WIDTH = 2.5
	local ref = {}
	for i, oe in ipairs(oedges) do
		local ix = i - 1
		if hasMode(oe, "TRUCK") and (ix <= 12 or ix == 14 or ix == 15 or ix == 18 or ix == 19) then
			for s = 0, 1.0001, 0.02 do ref[#ref + 1] = hermite(oe, s) end
		end
	end
	local origNode = {}
	for _, oe in ipairs(oedges) do origNode[key(oe.a[1])] = true; origNode[key(oe.b[1])] = true end
	-- cut points of the original north road are merge points too
	for _, ne in ipairs(edges) do
		if hasMode(ne, "TRUCK") and ne.a[1][2] == 19 and ne.b[1][2] == 19 and ne.a[1][1] <= -60 and ne.b[1][1] >= -134 then
			origNode[key(ne.a[1])] = true; origNode[key(ne.b[1])] = true
		end
	end
	for _, e in ipairs(edges) do
		if hasMode(e, "TRUCK") and not origKeys[key(e.a[1]) .. ">" .. key(e.b[1])]
			and not origNode[key(e.a[1])] and not origNode[key(e.b[1])] then
			for s = 0, 1.0001, 0.05 do
				local p = hermite(e, s)
				local best = math.huge
				for _, r in ipairs(ref) do
					local d = (p[1] - r[1]) ^ 2 + (p[2] - r[2]) ^ 2
					if d < best then best = d end
				end
				check(math.sqrt(best) >= WIDTH - 1e-6, string.format("lane %.2f m from the original loop at %s", math.sqrt(best), key(p)))
			end
		end
	end
end

-- the parked leg is long enough for a semi-trailer (front at the stop node)
check(network.STOP_Y - network.HAIRPIN_Y >= 15.9, "parked leg shorter than a 16 m truck")
check(network.PARK_HAIRPIN_X - network.PARK_STOP_X >= 15.9, "parking slot leg shorter than a 16 m truck")
check(network.PARK_FIRST_HAIRPIN_X - network.PARK_FIRST_STOP_X >= 14.0, "first parking slot leg shorter than 14 m")

-- 7. constructions
local consDir = "res/construction/assets/"
local p = io.popen("ls " .. consDir)
local cons = {}
for line in p:lines() do if line:match("_warenlager%.con$") then cons[#cons + 1] = line end end
p:close()
check(#cons == 13, "expected 13 brand constructions, got " .. #cons)
local construction = require "truck_warehouse_plus/construction"
check(construction.TERMINAL_COUNT == #new.terminals, "construction and model disagree on terminal count")
for _, file in ipairs(cons) do
	local ok, err = pcall(function()
		local cf = assert(loadfile(consDir .. file))
		cf()
		local c = data()
		check(c.type == "STREET_STATION_CARGO", file .. " type")
		check(c.params[1].key == "twp_storage", file .. " storage param")
		check(c.params[2] and c.params[2].key == "twp_auto_bays" and c.params[2].defaultIndex == 0, file .. " auto-bays param (default on)")
		for _, case in ipairs({ { params = {}, cap = 2000 }, { params = { twp_storage = 5 }, cap = 10000 }, { params = { twp_storage = 0 }, cap = 0 } }) do
			local r = c.updateFn(case.params)
			check(r.models[1].id == "asset/dhl_path.mdl", file .. " path model must stay at index 0")
			local brand = file:match("^(.-)_warenlager")
			local hasSign = false
			for _, m in ipairs(r.models) do if m.id == "asset/" .. brand .. "_firma.mdl" then hasSign = true end end
			check(hasSign, file .. " lost its company sign")
			check(#r.terminalGroups == #new.terminals, file .. " terminal groups")
			check(#r.stations == 1 and #r.stations[1].terminals == #new.terminals, file .. " station terminals")
			check(r.stations[1].pool.moreCapacity == case.cap, file .. " capacity " .. tostring(r.stations[1].pool.moreCapacity) .. " ~= " .. case.cap)
			-- gate stubs: one-way, north one pointing in, south one pointing out, snapped outside
			local el = r.edgeLists[1]
			check(el.params.type == network.GATE_STREET, file .. " gate street type")
			local ed = el.edges
			check(#ed == 8 and el.snapNodes[1] == 0 and el.snapNodes[2] == 7, file .. " stub layout / snap nodes")
			check(ed[1][1][1] == 20.5 and ed[8][1][1] == 20.5, file .. " snap nodes must be the outer ends")
			for i = 1, 4 do check(ed[i][2][1] < 0 and ed[i][1][2] == -2.65701, file .. " north stub must run inwards") end
			for i = 5, 8 do check(ed[i][2][1] > 0 and ed[i][1][2] == -58.0858, file .. " south stub must run outwards") end
		end
	end)
	check(ok, file .. " failed to build: " .. tostring(err))
end

-- dump for tools/plot.py
os.execute("mkdir -p test/out")
local dump = io.open("test/out/lanes.tsv", "w")
for _, e in ipairs(edges) do
	local pts = {}
	for s = 0, 1.0001, 0.05 do local q = hermite(e, s); pts[#pts + 1] = string.format("%.3f,%.3f", q[1], q[2]) end
	dump:write(e.modes[1], "\t", origKeys[key(e.a[1]) .. ">" .. key(e.b[1])] and "orig" or "new", "\t", table.concat(pts, " "), "\n")
end
for i, t in ipairs(new.terminals) do
	local q = nodes[t.vehicleNode + 1].node[1]
	dump:write("TERMINAL\t", i, "\t", string.format("%.3f,%.3f", q[1], q[2]), "\n")
end
dump:close()

print(string.format("%d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
