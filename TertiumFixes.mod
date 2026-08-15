return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Tertium Fixes` encountered an error loading the Darktide Mod Framework.")

		new_mod("TertiumFixes", {
			mod_script       = "TertiumFixes/scripts/mods/TertiumFixes/TertiumFixes",
			mod_data         = "TertiumFixes/scripts/mods/TertiumFixes/TertiumFixes_data",
			mod_localization = "TertiumFixes/scripts/mods/TertiumFixes/TertiumFixes_localization",
		})
	end,
	packages = {},
}
