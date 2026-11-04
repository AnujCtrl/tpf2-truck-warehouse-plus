function data()

return {
	de = {
		["info_name"] = "LKW Warenlager Plus",
		["info_desc"] = ("Das LKW Warenlager von rob (Workshop 2456822185) mit allen Laderampen nutzbar:\n" ..
				"- 21 Haltepunkte: die 2 ursprünglichen an der Südstraße, 13 Laderampen an der Nordseite der Halle und 6 LKW-Stellplätze am Nordtor\n" ..
				"- einstellbares Lager (+0 bis +10000 Fracht)\n" ..
				"- Linien verteilen ihre LKW automatisch auf alle freien Rampen (abschaltbar)\n" ..
				"Ersetzt das Original (gleiche Dateien): bitte das Workshop-Original deaktivieren.\n" ..
				"- Kosten: 120.000, verfügbar ab 2000"),
		["TWP_STORAGE"] = "Lager",
		["TWP_STORAGE_TOOLTIP"] = "Zusätzliche Fracht, die das Warenlager halten kann",
		["TWP_AUTO_BAYS"] = "LKW auf alle Rampen verteilen",
		["TWP_AUTO_BAYS_TOOLTIP"] = "Linien, die hier halten, bekommen automatisch alle anderen Haltepunkte als Ausweich-Haltepunkte. Haltestellen, bei denen schon Ausweich-Haltepunkte gewählt sind, bleiben unverändert.",
		["TWP_YES"] = "Ja",
		["TWP_NO"] = "Nein",
		["TWP_POPUP_TITLE"] = "LKW Warenlager Plus",
		["TWP_POPUP_TEXT"] = "%d Warenlager wurde(n) mit einer älteren Version dieser Mod gebaut und nutzen noch die alten Fahrspuren.\nJetzt neu bauen (%d Haltepunkte)? Linien bleiben verbunden, die Einstellungen bleiben erhalten.",
		["TWP_POPUP_REBUILD"] = "Jetzt neu bauen",
		["TWP_POPUP_LATER"] = "Später",
		["TWP_POPUP_WORKING"] = "Wird neu gebaut ...",
		["TWP_POPUP_DONE"] = "%d von %d Warenlagern neu gebaut.",
	},
	en = {
		["info_name"] = "Truck warehouse Plus",
		["info_desc"] = ("rob's Truck warehouse (Workshop 2456822185) with every loading bay usable:\n" ..
				"- 21 terminals: the 2 original lay-bys on the south road, 13 loading bays on the north side of the hall and 6 truck parking slots inside the north gate\n" ..
				"- adjustable storage (+0 to +10000 cargo)\n" ..
				"- lines spread their trucks over every free bay automatically (can be switched off)\n" ..
				"Replaces the original (same files): disable the Workshop original.\n" ..
				"- Cost: 120,000, available from 2000"),
		["TWP_STORAGE"] = "Storage",
		["TWP_STORAGE_TOOLTIP"] = "Extra cargo the warehouse can hold",
		["TWP_AUTO_BAYS"] = "Spread trucks over all bays",
		["TWP_AUTO_BAYS_TOOLTIP"] = "Lines stopping here automatically get every other terminal as alternative terminals. Stops that already have alternative terminals are left as they are.",
		["TWP_YES"] = "Yes",
		["TWP_NO"] = "No",
		["TWP_POPUP_TITLE"] = "Truck warehouse Plus",
		["TWP_POPUP_TEXT"] = "%d warehouse(s) were built with an older version of this mod and still use the old lanes.\nRebuild them now (%d terminals)? Lines stay attached and the settings are kept.",
		["TWP_POPUP_REBUILD"] = "Rebuild now",
		["TWP_POPUP_LATER"] = "Not now",
		["TWP_POPUP_WORKING"] = "Rebuilding ...",
		["TWP_POPUP_DONE"] = "Rebuilt %d of %d warehouses.",
	},
}
end
