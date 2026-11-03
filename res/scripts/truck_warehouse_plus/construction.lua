-- Shared construction for every brand of the truck warehouse. The 13 .con files used
-- to be copies of one another that differed only in the name and the company sign, so
-- they now just call make(). Geometry below is the original 2021 updateFn, unchanged.
--
-- New compared with the original:
--   * terminals come from network.lua (2 original lay-bys + 13 loading bays)
--   * explicit terminalGroups / stations, so the station pool can get extra capacity
--   * a "Storage" parameter for that capacity

local constructionutil = require "constructionutil"
local colliderutil = require "colliderutil"
local network = require "truck_warehouse_plus/network"

local M = {}

M.PATH_MODEL = "asset/dhl_path.mdl"
M.STORAGE = { 0, 500, 1000, 2000, 5000, 10000 } -- extra cargo the station can hold
M.STORAGE_DEFAULT = 4 -- 1-based index into STORAGE (+2000)
M.TERMINAL_COUNT = #network.build().terminals

local function storageParam()
	local labels = {}
	for i, v in ipairs(M.STORAGE) do labels[i] = "+" .. tostring(v) end
	return {
		key = "twp_storage",
		name = _("TWP_STORAGE"),
		tooltip = _("TWP_STORAGE_TOOLTIP"),
		values = labels,
		defaultIndex = M.STORAGE_DEFAULT - 1,
		uiType = "BUTTON",
	}
end

-- params.twp_storage is a 0-based index; old saves don't have it at all
function M.storageFor(params)
	local i = params and params.twp_storage
	if type(i) ~= "number" or M.STORAGE[i + 1] == nil then i = M.STORAGE_DEFAULT - 1 end
	return M.STORAGE[i + 1]
end

local IDENTITY = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }

local function addStation(result, params)
	local pathIndex
	for i, m in ipairs(result.models) do
		if m.id == M.PATH_MODEL then pathIndex = i - 1 break end
	end
	assert(pathIndex ~= nil, "truck warehouse: path model missing from result.models")

	result.terminalGroups = {}
	local stationTerminals = {}
	for t = 0, M.TERMINAL_COUNT - 1 do
		result.terminalGroups[#result.terminalGroups + 1] = { terminals = { { pathIndex, t } } }
		stationTerminals[#stationTerminals + 1] = t
	end
	result.stations = {
		{ terminals = stationTerminals, tag = 0, pool = { moreCapacity = M.storageFor(params) } },
	}
end

local function build(brand, params)
	local result = {}
	local Edges = {}
	result.models = {}

	-- the path model goes first: it carries every lane and terminal
	local ids = {
		M.PATH_MODEL,
		"asset/dhl_street.mdl",
		"asset/dhl_assets.mdl",
		"asset/dhl_aussen.mdl",
		"asset/dhl_innen.mdl",
		"asset/dhl_office.mdl",
		"asset/dhl_pforte_aussen.mdl",
		"asset/dhl_gelaende.mdl",
		"asset/dhl_pforte_innen.mdl",
		"asset/dhl_linien.mdl",
		brand.sign,
		"asset/dhl_glas.mdl",
	}
	for _, id in ipairs(ids) do
		result.models[#result.models + 1] = { id = id, transf = IDENTITY }
	end

	Edges[#Edges + 1] = { { 7.5, -2.65701, 0 }, { 8.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 15.5, -2.65701, 0 }, { 8.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 15.5, -2.65701, 0 }, { 5.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 20.5, -2.65701, 0 }, { 5.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 7.5, -58.0858, 0 }, { 8.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 15.5, -58.0858, 0 }, { 8.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 15.5, -58.0858, 0 }, { 5.0, 0.0, 0.00 } }
	Edges[#Edges + 1] = { { 20.5, -58.0858, 0 }, { 5.0, 0.0, 0.00 } }

	result.edgeLists = {
		{
			type = "STREET",
			params = { type = "standard/country_medium_new.lua" },
			edges = Edges,
			snapNodes = { 3, 7 },
		},
	}

	-- fence between the two gates
	constructionutil.makeFence({
		{ -4, -8.38576, 0 },
		{ 5, -8.38576, 0 },
		{ 7.17938, -10.45, 0 },
		{ 7.17938, -52.48, 0 },
		{ 0.929379, -52.48, 0 },
	}, "station/air/asset/fence_metal.mdl", 3, false, result.models)

	-- fence round the yard
	constructionutil.makeFence({
		{ 5.35, -63.5, 0 },
		{ -147.691, -63.5, 0 },
		{ -147.691, 20.5, 0 },
		{ -145.6, 22.6542, 0 },
		{ -55.6, 22.6542, 0 },
		{ -34.7, 34.5142, 0 },
		{ 1.27215, 32.8, 0 },
		{ 1.27215, 8.77174, 0 },
	}, "station/air/asset/fence_metal.mdl", 3, false, result.models)

	result.colliders = {
		colliderutil.createBox({ -24.6592, -14.5858, 5 }, { 32.43139, 49.7, 5 }),
		colliderutil.createBox({ -102.691, -20.5158, 5 }, { 45.6, 43.77, 5 }),
	}

	local groundFaceKoord = {
		{ 7.62938, -64.1358 },
		{ -147.091, -64.1358 },
		{ -147.091, 22.0542 },
		{ -55.7, 22.0542 },
		{ -35.3, 34 },
		{ 0.747144, 34 },
		{ 0.747144, 2.62174 },
		{ 7.62938, 2.62174 },
	}
	local outsideParkingLot = {
		{ 1.27215, 2.49352, 0.0, 1.0 },
		{ 1.27215, 34.1142, 0.0, 1.0 },
		{ 17.77218, 34.1142, 0.0, 1.0 },
		{ 17.77218, 2.49352, 0.0, 1.0 },
	}
	result.groundFaces = {
		{ face = groundFaceKoord, modes = { { type = "FILL", key = "industry_concrete_01.lua" } } },
		{ face = outsideParkingLot, modes = { { type = "FILL", key = "industry_concrete_01.lua" } } },
		{ face = groundFaceKoord, modes = { { type = "STROKE_OUTER", key = "building_paving.lua" } } },
	}

	result.terrainAlignmentLists = {
		{
			type = "EQUAL",
			faces = {
				{ { 20, -64.2858, -0.00001 }, { -148.291, -64.2858, -0.00001 }, { -148.291, 23.2542, -0.00001 },
					{ -57.0906, 23.2542, -0.00001 }, { -37.0906, 35.1142, -0.00001 }, { 20, 35.1142, -0.00001 } },
			},
			slopeLow = .35,
		},
	}

	addStation(result, params)
	return result
end

-- brand = { name = <translated name>, sign = "asset/<brand>_firma.mdl" }
function M.make(brand)
	return {
		type = "STREET_STATION_CARGO",
		description = {
			name = brand.name,
			description = brand.name,
		},
		availability = {
			yearFrom = 2000,
		},
		buildMode = "MULTI",
		categories = { "misc" },
		order = 10,
		params = { storageParam() },
		updateFn = function(params)
			return build(brand, params)
		end,
	}
end

return M
