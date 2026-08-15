return {
	mod_name = {
		en = "Tertium Fixes",
	},
	mod_description = {
		en = "A collection of client-side fixes for stuck menus, missed inputs, incorrect HUD information, lingering audio and effects, long-session cleanup, and other common Darktide problems.",
	},
	cursor_stack_enabled = {
		en = "Repair cursor reference stack",
	},
	cursor_stack_enabled_description = {
		en = "Reconciles cursor depth with the game's reference set after cursor push/pop calls. Helps prevent stuck or invisible cursors.",
	},
	input_device_handoff_enabled = {
		en = "Use newly pressed input devices immediately",
	},
	input_device_handoff_enabled_description = {
		en = "Re-runs the game's latest-device selection after device polling, before input services update. Prevents the first controller or keyboard press on a device switch from being lost.",
	},
	rumble_apply_enabled = {
		en = "Apply controller-rumble setting immediately",
	},
	rumble_apply_enabled_description = {
		en = "Refreshes the Wwise rumble state after the game changes or suppresses controller vibration.",
	},
	veteran_redirect_tooltip_enabled = {
		en = "Correct Redirect Fire talent description",
	},
	veteran_redirect_tooltip_enabled_description = {
		en = "Repairs the two exact Veteran buff-to-talent links that make Redirect Fire show Target Down's description.",
	},
	zealot_prime_target_tooltip_enabled = {
		en = "Correct Prime Target tactical-overlay text",
	},
	zealot_prime_target_tooltip_enabled_description = {
		en = "Links Prime Target's exact timed effect back to its Zealot talent so the tactical overlay resolves the proper name and description.",
	},
	power_overload_hud_enabled = {
		en = "Show the Power Overload ally-buff icon",
	},
	power_overload_hud_enabled_description = {
		en = "Adds presentation metadata to the exact 8-second Power Overload ally buff without changing its gameplay values.",
	},
	chain_smoke_cleanup_enabled = {
		en = "Aggressively stop chain-weapon smoke (prototype)",
	},
	chain_smoke_cleanup_enabled_description = {
		en = "Optional workaround for persistent chain-weapon smoke. Preserves the power-down sound, but deliberately removes the normal particle tail. Disabled by default.",
	},
	servo_skull_scroll_enabled = {
		en = "Prevent Servo-Skull mouse-wheel toggles (prototype)",
	},
	servo_skull_scroll_enabled_description = {
		en = "Opt-in: removes wheel-up/down only from the held Servo-Skull's private wield inputs. Wheel cycling away from the skull is unavailable while it is held.",
	},
	notification_dedupe_enabled = {
		en = "Deduplicate safe notifications",
	},
	notification_dedupe_enabled_description = {
		en = "Suppresses identical, callback-free default and alert notifications repeated inside a short window.",
	},
	notification_dedupe_window_seconds = {
		en = "Notification duplicate window (seconds)",
	},
	notification_dedupe_window_seconds_description = {
		en = "How long a matching safe notification is considered a duplicate.",
	},
	notification_include_mission = {
		en = "Include mission notifications",
	},
	notification_include_mission_description = {
		en = "Also deduplicates identical callback-free mission messages. Disabled by default to preserve repeated objective updates.",
	},
	localization_guard_enabled = {
		en = "Guard invalid localization keys",
	},
	localization_guard_enabled_description = {
		en = "Returns a safe fallback when client code passes nil, empty, or non-string localization keys.",
	},
	localization_fallback_mode = {
		en = "Localization fallback",
	},
	localization_fallback_mode_description = {
		en = "Diagnostic shows a visible placeholder; blank keeps broken UI text unobtrusive.",
	},
	localization_fallback_diagnostic = {
		en = "Diagnostic placeholder",
	},
	localization_fallback_blank = {
		en = "Blank text",
	},
	gc_enabled = {
		en = "Lua heap controller",
	},
	gc_enabled_description = {
		en = "Monitors Darktide's Lua memory and uses cautious, limited cleanup when it remains under heavy pressure. Monitoring and the heap meter can stay enabled even when cleanup is not permitted.",
	},
	gc_cleaning_permitted = {
		en = "Permit automatic and manual cleanup",
	},
	gc_cleaning_permitted_description = {
		en = "Allows this module to tune or invoke the Lua collector. Disable it to retain heap monitoring and the meter without any collector changes or cleanup requests.",
	},
	gc_capacity_fallback_mb = {
		en = "Fallback Lua heap capacity (MB)",
	},
	gc_capacity_fallback_mb_description = {
		en = "Used only when the game launch arguments do not provide --lua-heap-mb-size. Pressure thresholds are calculated as percentages of this capacity.",
	},
	gc_convenient_cleanup_enabled = {
		en = "Clean at safe state transitions",
	},
	gc_convenient_cleanup_enabled_description = {
		en = "Requests a full cleanup after relevant game-state transitions. Mourningstar entry is delayed to let loading allocations settle; other supported entries and exits use a short delay.",
	},
	gc_periodic_cleanup_enabled = {
		en = "Optional 10-minute cleanup",
	},
	gc_periodic_cleanup_enabled_description = {
		en = "Requests a full Lua cleanup every ten minutes. Disabled by default because periodic full collections can produce a visible hitch.",
	},
	gc_notifications_enabled = {
		en = "Heap-pressure notifications",
	},
	gc_notifications_enabled_description = {
		en = "Shows warnings for high heap pressure and emergency cleanup results. Logging and the meter are controlled separately.",
	},
	gc_hud_enabled = {
		en = "Show Lua heap meter",
	},
	gc_hud_enabled_description = {
		en = "Shows current Lua heap use, detected capacity, percentage and pressure band. The meter is forced visible at 85%% until pressure clears.",
	},
	gc_hud_x_percent = {
		en = "Heap meter horizontal position (%%)",
	},
	gc_hud_x_percent_description = {
		en = "Positions the meter from the left edge as a percentage of the active HUD workspace width.",
	},
	gc_hud_y_percent = {
		en = "Heap meter vertical position (%%)",
	},
	gc_hud_y_percent_description = {
		en = "Positions the meter from the top edge as a percentage of the active HUD workspace height.",
	},
	gc_shutdown_diagnostic_enabled = {
		en = "Record abnormal-exit heap context",
	},
	gc_shutdown_diagnostic_enabled_description = {
		en = "Stores only the last broad heap-pressure band and whether the mod recorded a clean unload. A warning on the next launch is diagnostic context, not a crash-cause claim.",
	},
	gc_manual_clean_key = {
		en = "Manual full-cleanup key",
	},
	gc_manual_clean_key_description = {
		en = "Requests an immediate full Lua cleanup with a three-second cooldown. This can cause a brief frame-time spike and remains blocked whenever this feature does not own cleanup.",
	},
	gc_hud_toggle_key = {
		en = "Show or hide heap meter key",
	},
	gc_hud_toggle_key_description = {
		en = "Toggles the heap meter for the current session. A high-pressure warning can force it visible until pressure falls below 80%%.",
	},
	campaign_vox_cleanup_enabled = {
		en = "Stop leaked Campaign Data Transmission audio",
	},
	campaign_vox_cleanup_enabled_description = {
		en = "Stops the stored transmission-hover sound when leaving or destroying the campaign mission list, preventing the static loop from following you into other screens or missions.",
	},
	player_buff_removal_enabled = {
		en = "Remove stale consecutive buff HUD entries",
	},
	player_buff_removal_enabled_description = {
		en = "Cleans consecutive expired buff entries skipped by the game's forward-removal loop, preventing stale icons and needless HUD work.",
	},
	penance_carousel_scroll_enabled = {
		en = "Correct Penances carousel wheel direction",
	},
	penance_carousel_scroll_enabled_description = {
		en = "Makes wheel-down advance the Penances carousel and wheel-up go back. Controller and keyboard navigation are unchanged.",
	},
	path_of_trust_black_screen_enabled = {
		en = "Recover from the final Path of Trust black screen",
	},
	path_of_trust_black_screen_enabled_description = {
		en = "Fades back to the Mourningstar if the final Path of Trust cinematic ends while its full-screen black overlay is still stranded.",
	},
	gas_outline_recovery_enabled = {
		en = "Restore outlines after dying in toxic gas",
	},
	gas_outline_recovery_enabled_description = {
		en = "Restores global outlines when a toxic-gas buff ends on the dead local player, covering all four gas variants without changing gas gameplay.",
	},
	player_fx_lifecycle_enabled = {
		en = "Repair player particle and moving-FX lifecycle",
	},
	player_fx_lifecycle_enabled_description = {
		en = "Supplies the missing world for local first-person looping particles and releases moving sound and particle handles when a player FX extension is destroyed.",
	},
	effect_template_safety_enabled = {
		en = "Guard partially initialized client effects",
	},
	effect_template_safety_enabled_description = {
		en = "Prevents six exact Servo-Skull and arc-chain effects from updating with missing state, cleans their owned particles and audio, and makes later stops harmless.",
	},
	event_listener_cleanup_enabled = {
		en = "Release leaked event listeners",
	},
	event_listener_cleanup_enabled_description = {
		en = "Unregisters exact haptic, Survival-objective, and Expedition-rescue listeners that the matching client destroy paths leave behind.",
	},
	audio_source_cleanup_enabled = {
		en = "Release leaked manual audio sources",
	},
	audio_source_cleanup_enabled_description = {
		en = "Destroys only the exact dialogue, relic, flamer, mutant, and bomber Wwise sources owned by client objects whose normal stop or destroy paths omit them.",
	},
	fx_handler_integrity_enabled = {
		en = "Guard client FX handler state",
	},
	fx_handler_integrity_enabled_description = {
		en = "Adds generation-aware, idempotent cleanup around local effect-handler teardown. Experimental allocation and RPC containment remain separate and disabled by default.",
	},
	fx_handler_local_rewrite_enabled = {
		en = "Experimental local FX allocator (advanced)",
	},
	fx_handler_local_rewrite_enabled_description = {
		en = "Replaces allocation and expiry only for the client-local FX handler. Disabled by default until it has broad live-game soak coverage.",
	},
	fx_handler_rpc_idempotence_enabled = {
		en = "Experimental network FX containment (advanced)",
	},
	fx_handler_rpc_idempotence_enabled_description = {
		en = "Makes malformed or duplicate FX start/stop messages fail closed on the client. Disabled by default because slot-only messages cannot prove ordering after reuse.",
	},
	stimm_field_deleted_extension_guard_enabled = {
		en = "Discard destroyed Stimm Field cache rows",
	},
	stimm_field_deleted_extension_guard_enabled_description = {
		en = "Removes only proximity rows whose cached buff extension is explicitly destroyed before the field's linger pass can call it.",
	},
	hive_scum_stimm_chime_enabled = {
		en = "Play a chime when the Hive Scum stimm is ready",
	},
	hive_scum_stimm_chime_enabled_description = {
		en = "Plays Darktide's stock ability-ready cue once when the local Hive Scum personal stimm regains its charge. Joining, spawning, and equipping a ready stimm stay silent.",
	},
	training_grounds_danger_index_guard_enabled = {
		en = "Repair invalid Psykhanium danger settings",
	},
	training_grounds_danger_index_guard_enabled_description = {
		en = "Validates and clamps only the Training Grounds shooting-range danger index, falling back safely when saved settings are malformed.",
	},
	auto_quarantine_enabled = {
		en = "Auto-quarantine failing modules",
	},
	auto_quarantine_enabled_description = {
		en = "Stops an individual fix after repeated internal errors while leaving the other fixes active.",
	},
	auto_quarantine_threshold = {
		en = "Errors before quarantine",
	},
	auto_quarantine_threshold_description = {
		en = "Number of caught module errors allowed before that module is quarantined.",
	},
	diagnostic_logging = {
		en = "Diagnostic log messages",
	},
	diagnostic_logging_description = {
		en = "Writes useful feature state changes and caught errors to the DMF log.",
	},
	command_status_description = {
		en = "Show Tertium Fixes module state and counters.",
	},
	command_reset_description = {
		en = "Reset a quarantined Tertium Fixes module: /tf_reset [module_id|all].",
	},
	command_gc_description = {
		en = "Show GC status or request a guarded cleanup action: /tf_gc [status|step|clean].",
	},
}
