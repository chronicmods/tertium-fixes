return {
	graphics_group = { en = "Graphics presets" },
	graphics_presets_enabled = { en = "Apply graphics preset" },
	graphics_presets_enabled_description = { en = "Applies the selected rendering settings and saves the previous values. Turn this off to restore settings still owned by the preset. Changing presets may briefly pause rendering." },
	graphics_preset = { en = "Preset" },
	graphics_preset_description = { en = "Ultra Performance removes AO, shadows and fog volumes, including a change to how gas areas look. Performance keeps low fog. Balanced and Quality retain more lighting detail. Resolution, upscaling, FOV, textures and combat particles are kept." },
	graphics_ultra_performance = { en = "Ultra Performance" },
	graphics_performance = { en = "Performance" },
	graphics_balanced = { en = "Balanced" },
	graphics_quality = { en = "Quality" },
	command_graphics_description = { en = "Show graphics preset status, or use /tf_graphics restore to restore the captured settings." },
	input_group = { en = "Inputs" },
	menus_group = { en = "Menus and HUD" },
	effects_group = { en = "Sounds and effects" },
	memory_group = { en = "Lua memory" },
	compatibility_group = { en = "Compatibility and experimental fixes" },
	diagnostics_group = { en = "Troubleshooting" },
	input_retry_enabled = { en = "Keep briefly blocked inputs" },
	input_retry_enabled_description = { en = "Off by default. Turn this on and select the actions you want to retry. A press is kept for up to 0.75 seconds and cleared when the action starts, the situation changes or you cancel it." },
	input_retry_swap_enabled = { en = "Retry weapon swaps" },
	input_retry_swap_enabled_description = { en = "Keeps the slot you selected, including quick swap and scrolling. Stops when that slot is reached or another selection replaces it." },
	input_retry_ability_enabled = { en = "Retry ability activation" },
	input_retry_ability_enabled_description = { en = "Retries a briefly blocked combat-ability press. Normal aiming, release and cancellation still apply." },
	input_retry_special_enabled = { en = "Retry weapon specials" },
	input_retry_special_enabled_description = { en = "Keeps a special-action press during a short input block and clears it as soon as the action starts." },
	input_retry_reload_enabled = { en = "Retry reloads" },
	input_retry_reload_enabled_description = { en = "Keeps a reload press through a short input block. Changing weapon cancels it." },
	input_retry_blitz_enabled = { en = "Retry quick Blitz actions" },
	input_retry_blitz_enabled_description = { en = "Retries quick Blitz presses where the equipped ability supports them. Grenades that must be equipped keep their normal controls." },
	ui_resource_cleanup_enabled = { en = "Clean up menu icons and views" },
	ui_resource_cleanup_enabled_description = { en = "Handles repeated icon and view releases, restores icons after rendering resumes, and releases portraits left by departing Party Finder members." },
	social_roster_portrait_enabled = { en = "Keep equipped frames in the Social menu" },
	social_roster_portrait_enabled_description = { en = "Finishes cleaning up the old frame before loading its replacement, so a late callback cannot replace the equipped frame with the default one." },
	weapon_effect_transitions_enabled = { en = "Fix weapon sounds after inspecting" },
	weapon_effect_transitions_enabled_description = { en = "Stops old chem-grenade and power-weapon loops when the camera changes, and prevents a visibility refresh from replaying the force greatsword charge sound." },
	mod_name = {
		en = "Tertium Fixes",
	},
	mod_description = {
		en = "Client fixes for dropped inputs, stuck menus, stale HUD icons, lingering sounds and effects, and resources left behind during play.",
	},
	cursor_stack_enabled = {
		en = "Repair cursor reference stack",
	},
	cursor_stack_enabled_description = {
		en = "Corrects the cursor count when menus open or close, helping prevent a cursor that gets stuck or disappears.",
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
		en = "Repairs the old missing talent links. The current game already includes the fix, so this stays inactive there.",
	},
	zealot_prime_target_tooltip_enabled = {
		en = "Correct Prime Target tactical-overlay text",
	},
	zealot_prime_target_tooltip_enabled_description = {
		en = "Repairs Prime Target's missing tactical-overlay description on older builds. Darktide 1.13.0 includes the correct link, so this stays inactive there.",
	},
	power_overload_hud_enabled = {
		en = "Show the Power Overload ally-buff icon",
	},
	power_overload_hud_enabled_description = {
		en = "Adds presentation metadata to the exact 8-second Power Overload ally buff without changing its gameplay values.",
	},
	chain_smoke_cleanup_enabled = {
		en = "Remove lingering chain-weapon smoke",
	},
	chain_smoke_cleanup_enabled_description = {
		en = "Optional workaround for persistent chain-weapon smoke. Preserves the power-down sound, but deliberately removes the normal particle tail. Disabled by default.",
	},
	servo_skull_scroll_enabled = {
		en = "Block weapon scrolling while holding the Servo-Skull",
	},
	servo_skull_scroll_enabled_description = {
		en = "Stops the wheel from switching weapons while you hold the Servo-Skull. Off by default; keyboard and controller selection still work.",
	},
	notification_queue_callbacks_enabled = {
		en = "Keep queued notifications working",
	},
	notification_queue_callbacks_enabled_description = {
		en = "Restores the start and completion actions lost when a notification has to wait for space on screen.",
	},
	notification_dedupe_enabled = {
		en = "Hide repeated basic notifications",
	},
	notification_dedupe_enabled_description = {
		en = "Hides identical basic messages sent close together. Timed messages and messages with actions stay visible. Off by default because some repeats are useful.",
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
		en = "Guard localisation values",
	},
	localization_guard_enabled_description = {
		en = "Guards invalid keys and values, and supplies the Social menu's missing initial party count. Normal party updates keep their real counts.",
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
		en = "Monitor Lua memory",
	},
	gc_enabled_description = {
		en = "Shows how much memory the game's Lua scripts use. Extra cleanup is a separate option and is off by default.",
	},
	gc_cleaning_permitted = {
		en = "Allow extra Lua cleanup",
	},
	gc_cleaning_permitted_description = {
		en = "Allows extra collection and changes to Lua collector tuning. Darktide already manages collection; leave this off unless you are testing a memory problem. Full cleanup can cause a brief pause.",
	},
	gc_capacity_fallback_mb = {
		en = "Fallback Lua heap capacity (MB)",
	},
	gc_capacity_fallback_mb_description = {
		en = "Used when the game does not report a Lua heap limit. This is your configured estimate, not measured capacity or total RAM. The meter marks an estimated capacity with ~.",
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
		en = "Shows Lua memory use and its configured limit. A ~ means the limit is estimated. The meter appears at high pressure even when normally hidden.",
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
		en = "Remember memory pressure after an unexpected exit",
	},
	gc_shutdown_diagnostic_enabled_description = {
		en = "Remembers the previous memory-pressure band and whether shutdown finished normally. This can help troubleshooting but does not identify what caused a crash.",
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
		en = "Legacy Path 09 black-screen fallback",
	},
	path_of_trust_black_screen_enabled_description = {
		en = "Narrow fallback for the exact path_of_trust_09 terminal black state. Darktide 1.12.4 fixed a matching general cutscene-fade symptom, but the notes do not identify this exact scene, so the guarded fallback remains.",
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
		en = "Handle effects that did not finish starting",
	},
	effect_template_safety_enabled_description = {
		en = "Stops Servo-Skull and arc-chain effects from using missing or destroyed state, and releases any particles and sounds that did start.",
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
		en = "Clear expired Stimm Field references",
	},
	stimm_field_deleted_extension_guard_enabled_description = {
		en = "Drops a Stimm Field's reference to a destroyed buff connection when a player leaves, returns or remains nearby.",
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
		en = "Stop a fix after repeated errors",
	},
	auto_quarantine_enabled_description = {
		en = "Stops an individual fix after repeated internal errors while leaving the other fixes active.",
	},
	auto_quarantine_threshold = {
		en = "Errors before quarantine",
	},
	auto_quarantine_threshold_description = {
		en = "Number of consecutive errors before a fix is stopped and its changes are cleaned up.",
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
