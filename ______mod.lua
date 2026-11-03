function data()
	return {
		info = {
			minorVersion = 1,
			severityAdd = "NONE",
			severityRemove = "NONE",
			name = _("TPF1 --> TPF2 - User mod.lua"),
			description = "",
		},
		runFn = function(settings)
			if (type(eat1963_tpf2_converter) == "table") then
				eat1963_tpf2_converter.transferModels({
					oldSeatsStyle = false,
					animationMaxRotationRange = 5,
					animationToAni = true,
				})
				
				--[[
				eat1963_tpf2_converter.createRepaints( {
					data = {
						masterFile = "vehicle/train/masterModel.mdl", -- dient als Basis
						repaintGroupFile = "vehicle/train/repaint_group.mdl", -- Gruppendatei für Repaintfunktion im Kaufmenü
						repaintFiles = {
							-- Datei wird erstellt
							["vehicle/train/repaintModel_01.mdl"] = {
								{"vehicle/waggon/masterMaterial_01.mtl", "vehicle/waggon/repainMaterial_01_01.mtl"}, -- links Original Material; rechts Repaint-Material
								{"vehicle/waggon/masterMaterial_02.mtl", "vehicle/waggon/repainMaterial_01_02.mtl"}, -- links Original Material; rechts Repaint-Material
								{"vehicle/waggon/masterMaterial_03.mtl", "vehicle/waggon/repainMaterial_01_03.mtl"}, -- links Original Material; rechts Repaint-Material
							},
							-- Datei wird ebenfalls erstellt
							["vehicle/train/repaintModel_02.mdl"] = {
								{"vehicle/waggon/masterMaterial_01.mtl", "vehicle/waggon/repainMaterial_02_01.mtl"}, -- links Original Material; rechts Repaint-Material
								{"vehicle/waggon/masterMaterial_02.mtl", "vehicle/waggon/repainMaterial_02_02.mtl"}, -- links Original Material; rechts Repaint-Material
								{"vehicle/waggon/masterMaterial_03.mtl", "vehicle/waggon/repainMaterial_02_03.mtl"}, -- links Original Material; rechts Repaint-Material
							},
						},
					},
					createMaterialFiles = false, -- sollen Repaint-Materialdateien erstellt werden?
				} )
				]]
			end
		end
 }
end