local mod = get_mod("TertiumFixes")

local core_ok, runtime = pcall(
	mod.io_dofile,
	mod,
	"TertiumFixes/scripts/mods/TertiumFixes/core"
)

if not core_ok or type(runtime) ~= "table" then
	mod:error("Core failed to load; Tertium Fixes will remain inert: %s", tostring(runtime))

	return
end

mod._tf_runtime = runtime

local module_paths = {
	"TertiumFixes/scripts/mods/TertiumFixes/modules/cursor_stack",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/input_device_handoff",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/rumble_apply",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/veteran_redirect_tooltip",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/zealot_prime_target_tooltip",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/power_overload_hud",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/chain_smoke_cleanup",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/servo_skull_scroll",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/notification_dedupe",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/localization_guard",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/gc_pressure",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/campaign_vox_cleanup",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/player_buff_removal",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/penance_carousel_scroll",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/path_of_trust_black_screen",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/gas_outline_recovery",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/player_fx_lifecycle",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/effect_template_safety",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/event_listener_cleanup",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/audio_source_cleanup",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/fx_handler_integrity",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/stimm_field_deleted_extension_guard",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/hive_scum_stimm_chime",
	"TertiumFixes/scripts/mods/TertiumFixes/modules/training_grounds_danger_index_guard",
}

for i = 1, #module_paths do
	local module_ok, module = pcall(mod.io_dofile, mod, module_paths[i])

	if module_ok and type(module) == "table" and type(module.id) == "string" then
		runtime:add_module(module)
	else
		mod:error(
			"A Tertium Fixes module failed to load and was skipped: %s (%s)",
			module_paths[i],
			tostring(module)
		)
	end
end

runtime:install_modules()

local hud_registration_ok, hud_registered = pcall(function ()
	if type(mod.register_hud_element) ~= "function" then
		return false
	end

	return mod:register_hud_element({
		class_name = "HudElementTertiumFixesGcMeter",
		filename = "TertiumFixes/scripts/mods/TertiumFixes/hud/hud_element_gc_meter",
		visibility_groups = {
			"alive",
		},
		use_hud_scale = true,
	})
end)

if not hud_registration_ok or hud_registered ~= true then
	mod:warning("The Lua heap meter HUD element could not be registered; heap management remains active.")
end

mod.update = function (dt)
	runtime:update(dt)
end

mod.on_all_mods_loaded = function ()
	runtime:dispatch("on_all_mods_loaded")
end

mod.on_game_state_changed = function (status, state_name)
	runtime:dispatch("on_game_state_changed", status, state_name)
end

mod.on_setting_changed = function (setting_id)
	runtime:setting_changed(setting_id)
end

mod.on_enabled = function ()
	runtime:set_mod_enabled(true)
	runtime:dispatch("on_enabled")
end

mod.on_disabled = function ()
	runtime:set_mod_enabled(false)
	runtime:dispatch("on_disabled")
end

mod.on_unload = function ()
	runtime:set_mod_enabled(false)
	runtime:dispatch("on_unload")
end

mod.tf_gc_manual_clean = function (is_pressed)
	if is_pressed == false then
		return
	end

	local gc_module = runtime:get_module("gc_pressure")

	if gc_module and type(gc_module.manual_collect) == "function" then
		gc_module:manual_collect()
	end
end

mod.tf_gc_toggle_hud = function (is_pressed)
	if is_pressed == false then
		return
	end

	local gc_module = runtime:get_module("gc_pressure")

	if gc_module and type(gc_module.toggle_hud) == "function" then
		gc_module:toggle_hud()
	end
end

mod:command("tf_status", mod:localize("command_status_description"), function ()
	runtime:print_status()
end)

mod:command("tf_reset", mod:localize("command_reset_description"), function (module_id)
	runtime:reset(module_id)
end)

mod:command("tf_gc", mod:localize("command_gc_description"), function (action)
	local gc_module = runtime:get_module("gc_pressure")

	if not gc_module then
		mod:echo("[Tertium Fixes] GC pressure module is unavailable.")

		return
	end

	if action == "clean" and type(gc_module.manual_collect) == "function" then
		gc_module:manual_collect()
	elseif action == "step" and type(gc_module.manual_step) == "function" then
		gc_module:manual_step()
	else
		runtime:print_status("gc_pressure")
	end
end)
