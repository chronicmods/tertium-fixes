local mod = get_mod("TertiumFixes")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "cursor_stack_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "input_device_handoff_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "rumble_apply_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "veteran_redirect_tooltip_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "zealot_prime_target_tooltip_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "power_overload_hud_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "chain_smoke_cleanup_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "servo_skull_scroll_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "notification_dedupe_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "notification_dedupe_window_seconds",
				type = "numeric",
				default_value = 2,
				range = {
					1,
					10,
				},
			},
			{
				setting_id = "notification_include_mission",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "localization_guard_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "localization_fallback_mode",
				type = "dropdown",
				default_value = "diagnostic",
				options = {
					{
						text = "localization_fallback_diagnostic",
						value = "diagnostic",
					},
					{
						text = "localization_fallback_blank",
						value = "blank",
					},
				},
			},
			{
				setting_id = "gc_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_cleaning_permitted",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_capacity_fallback_mb",
				type = "numeric",
				default_value = 1024,
				range = {
					128,
					65536,
				},
			},
			{
				setting_id = "gc_convenient_cleanup_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_periodic_cleanup_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "gc_notifications_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_hud_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_hud_x_percent",
				type = "numeric",
				default_value = 5,
				range = {
					0,
					100,
				},
			},
			{
				setting_id = "gc_hud_y_percent",
				type = "numeric",
				default_value = 65,
				range = {
					0,
					100,
				},
			},
			{
				setting_id = "gc_shutdown_diagnostic_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gc_manual_clean_key",
				type = "keybind",
				default_value = {
					"f5",
				},
				keybind_global = true,
				keybind_trigger = "pressed",
				keybind_type = "function_call",
				function_name = "tf_gc_manual_clean",
			},
			{
				setting_id = "gc_hud_toggle_key",
				type = "keybind",
				default_value = {
					"f8",
				},
				keybind_global = true,
				keybind_trigger = "pressed",
				keybind_type = "function_call",
				function_name = "tf_gc_toggle_hud",
			},
			{
				setting_id = "campaign_vox_cleanup_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "player_buff_removal_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "penance_carousel_scroll_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "path_of_trust_black_screen_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "gas_outline_recovery_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "player_fx_lifecycle_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "effect_template_safety_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "event_listener_cleanup_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "audio_source_cleanup_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "fx_handler_integrity_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "fx_handler_local_rewrite_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "fx_handler_rpc_idempotence_enabled",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "stimm_field_deleted_extension_guard_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "hive_scum_stimm_chime_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "training_grounds_danger_index_guard_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "auto_quarantine_enabled",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "auto_quarantine_threshold",
				type = "numeric",
				default_value = 3,
				range = {
					1,
					10,
				},
			},
			{
				setting_id = "diagnostic_logging",
				type = "checkbox",
				default_value = true,
			},
		},
	},
}
