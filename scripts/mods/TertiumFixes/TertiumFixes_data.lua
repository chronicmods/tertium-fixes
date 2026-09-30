local mod = get_mod("TertiumFixes")

local function toggle(id, default)
	return { setting_id = id, type = "checkbox", default_value = default }
end

local function number(id, default, low, high)
	return { setting_id = id, type = "numeric", default_value = default, range = { low, high } }
end

local function group(id, widgets)
	return { setting_id = id, type = "group", sub_widgets = widgets }
end

local function keybind(id, key, action)
	return {
		setting_id = id, type = "keybind", default_value = { key },
		keybind_global = true, keybind_trigger = "pressed",
		keybind_type = "function_call", function_name = action,
	}
end

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			group("graphics_group", {
				toggle("graphics_presets_enabled", false),
				{
					setting_id = "graphics_preset", type = "dropdown", default_value = "performance",
					options = {
						{ text = "graphics_ultra_performance", value = "ultra_performance" },
						{ text = "graphics_performance", value = "performance" },
						{ text = "graphics_balanced", value = "balanced" },
						{ text = "graphics_quality", value = "quality" },
					},
				},
			}),
			group("input_group", {
				toggle("input_retry_enabled", true),
				toggle("input_retry_swap_enabled", true),
				toggle("input_retry_ability_enabled", true),
				toggle("input_retry_special_enabled", true),
				toggle("input_retry_reload_enabled", true),
				toggle("input_retry_blitz_enabled", true),
				toggle("input_device_handoff_enabled", true),
				toggle("rumble_apply_enabled", true),
				toggle("servo_skull_scroll_enabled", false),
			}),
			group("menus_group", {
				toggle("cursor_stack_enabled", true),
				toggle("ui_resource_cleanup_enabled", true),
				toggle("social_roster_portrait_enabled", true),
				toggle("penance_carousel_scroll_enabled", true),
				toggle("notification_queue_callbacks_enabled", true),
				toggle("notification_dedupe_enabled", false),
				number("notification_dedupe_window_seconds", 2, 1, 10),
				toggle("notification_include_mission", false),
				toggle("localization_guard_enabled", true),
				{
					setting_id = "localization_fallback_mode", type = "dropdown", default_value = "diagnostic",
					options = {
						{ text = "localization_fallback_diagnostic", value = "diagnostic" },
						{ text = "localization_fallback_blank", value = "blank" },
					},
				},
				toggle("training_grounds_danger_index_guard_enabled", true),
			}),
			group("effects_group", {
				toggle("weapon_effect_transitions_enabled", true),
				toggle("player_fx_lifecycle_enabled", true),
				toggle("effect_template_safety_enabled", true),
				toggle("audio_source_cleanup_enabled", true),
				toggle("event_listener_cleanup_enabled", true),
				toggle("gas_outline_recovery_enabled", true),
				toggle("campaign_vox_cleanup_enabled", true),
				toggle("player_buff_removal_enabled", true),
				toggle("stimm_field_deleted_extension_guard_enabled", true),
				toggle("power_overload_hud_enabled", true),
				toggle("hive_scum_stimm_chime_enabled", true),
				toggle("chain_smoke_cleanup_enabled", false),
			}),
			group("memory_group", {
				toggle("gc_enabled", true),
				toggle("gc_cleaning_permitted", false),
				number("gc_capacity_fallback_mb", 1024, 128, 65536),
				toggle("gc_convenient_cleanup_enabled", true),
				toggle("gc_periodic_cleanup_enabled", false),
				toggle("gc_notifications_enabled", true),
				toggle("gc_hud_enabled", true),
				number("gc_hud_x_percent", 5, 0, 100),
				number("gc_hud_y_percent", 65, 0, 100),
				toggle("gc_shutdown_diagnostic_enabled", true),
				keybind("gc_manual_clean_key", "f5", "tf_gc_manual_clean"),
				keybind("gc_hud_toggle_key", "f8", "tf_gc_toggle_hud"),
			}),
			group("compatibility_group", {
				toggle("veteran_redirect_tooltip_enabled", true),
				toggle("zealot_prime_target_tooltip_enabled", true),
				toggle("path_of_trust_black_screen_enabled", true),
				toggle("fx_handler_integrity_enabled", true),
				toggle("fx_handler_local_rewrite_enabled", false),
				toggle("fx_handler_rpc_idempotence_enabled", false),
			}),
			group("diagnostics_group", {
				toggle("auto_quarantine_enabled", true),
				number("auto_quarantine_threshold", 3, 1, 10),
				toggle("diagnostic_logging", true),
			}),
		},
	},
}
