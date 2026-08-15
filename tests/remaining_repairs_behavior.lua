local failures = 0
local checks = 0

local function check(condition, message)
	checks = checks + 1

	if condition then
		io.write("PASS " .. message .. "\n")
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local hooks = {}
local deferred = {}
local settings = {}
local active = {}
local hits = {}
local actions = {}
local availability = {}

local runtime = {
	clock = 0,
}

function runtime:install_hook(module_id, path, method_name, hook_kind, callback)
	local record = {
		callback = callback,
		hook_kind = hook_kind,
		path = path,
	}

	hooks[module_id .. ":" .. method_name] = record
	hooks[module_id .. ":" .. path .. ":" .. method_name] = record

	return true
end

function runtime:defer_file(module_id, path, callback)
	deferred[path] = deferred[path] or {}
	deferred[path][#deferred[path] + 1] = {
		callback = callback,
		module_id = module_id,
	}

	return true
end

function runtime:is_active(module_id)
	return active[module_id] ~= false
end

function runtime:mod_is_enabled()
	return true
end

function runtime:get(setting_id)
	return settings[setting_id]
end

function runtime:run(_, callback, ...)
	return pcall(callback, ...)
end

function runtime:record_hit(module_id, count)
	hits[module_id] = (hits[module_id] or 0) + (count or 1)
end

function runtime:record_action(module_id, count)
	actions[module_id] = (actions[module_id] or 0) + (count or 1)
end

function runtime:set_available(module_id, value, reason)
	availability[module_id] = {
		reason = reason,
		value = value,
	}
end

local mod = {
	_tf_runtime = runtime,
}

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	end
end

local function reset_world()
	hooks = {}
	deferred = {}
	settings = {
		localization_fallback_mode = "placeholder",
		servo_skull_scroll_enabled = true,
	}
	active = {}
	hits = {}
	actions = {}
	availability = {}
	runtime.clock = 0
	DEDICATED_SERVER = false
	IS_WINDOWS = true
	IS_XBS = false
	Managers = nil
	World = nil
	HEALTH_ALIVE = nil
end

local function callback(module_id, method_name, path)
	local key = path and module_id .. ":" .. path .. ":" .. method_name
		or module_id .. ":" .. method_name
	local hook = hooks[key]

	return hook and hook.callback
end

local function deliver(path, value)
	local entries = deferred[path] or {}

	for index = 1, #entries do
		entries[index].callback(value)
	end
end

reset_world()
local cursor = dofile("scripts/mods/TertiumFixes/modules/cursor_stack.lua")
cursor:install()
local clip_updates = 0
local input_manager = {
	_cursor_stack_data = {
		allow_cursor_rendering = true,
		stack_depth = 7,
		stack_references = {
			first = true,
			second = true,
			stale = false,
		},
	},
	_show_cursor = false,
}

function input_manager:_update_clip_cursor()
	clip_updates = clip_updates + 1
end

callback("cursor_stack", "push_cursor")(input_manager)

check(
	input_manager._cursor_stack_data.stack_depth == 2
		and input_manager._show_cursor == true
		and clip_updates == 1
		and hits.cursor_stack == 1
		and actions.cursor_stack == 1,
	"cursor repair reconciles depth, visibility, and clipping after a real stack change"
)

reset_world()
local rumble = dofile("scripts/mods/TertiumFixes/modules/rumble_apply.lua")
rumble:install()
local rumble_updates = 0
local rumble_manager = {
	_user_rumble_state = true,
}

function rumble_manager:_update_wwise_rumble()
	rumble_updates = rumble_updates + 1
end

callback("rumble_apply", "_cb_update_rumble_enabled")(rumble_manager, false)
callback("rumble_apply", "stop_suppress_wwise_rumble")(rumble_manager)

check(
	rumble_manager._user_rumble_state == false
		and rumble_updates == 2
		and hits.rumble_apply == 2
		and actions.rumble_apply == 2,
	"rumble repair applies an explicit false value and refreshes suppression changes"
)

reset_world()
local penance = dofile("scripts/mods/TertiumFixes/modules/penance_carousel_scroll.lua")
penance:install()
local axis_seen
local other_seen
local original_service = {
	get = function (_, action_name)
		if action_name == "scroll_axis" then
			return {
				2,
				-3,
				4,
			}
		end

		return "unchanged"
	end,
	null_service = function ()
		return false
	end,
}
local view = {
	_using_cursor_navigation = true,
}

callback("penance_carousel_scroll", "_handle_carousel_scroll")(
	function (_, service)
		axis_seen = service:get("scroll_axis")
		other_seen = service:get("other")
	end,
	view,
	original_service,
	0.016
)

check(
	axis_seen[1] == 2
		and axis_seen[2] == 3
		and axis_seen[3] == 4
		and other_seen == "unchanged"
		and hits.penance_carousel_scroll == 1
		and actions.penance_carousel_scroll == 1,
	"Penances repair reverses only the mouse-wheel axis seen by the stock handler"
)

reset_world()
local localization = dofile("scripts/mods/TertiumFixes/modules/localization_guard.lua")
localization:install()
local localize_hook = callback("localization_guard", "localize")
local process_hook = callback("localization_guard", "_process_string")
local localization_manager = {
	_string_cache = {},
}
local function stock_process(_, _, raw_str)
	return raw_str
end
local function stock_localize(manager, key)
	local value = process_hook(stock_process, manager, key, false, {})

	manager._string_cache[key] = value

	return value
end
local invalid_key_result = localize_hook(stock_localize, localization_manager, nil, false, {})
local invalid_value_result = localize_hook(stock_localize, localization_manager, "broken_value", false, {})

check(
	invalid_key_result == "<missing localization key>"
		and invalid_value_result == "<invalid localized value: boolean>"
		and localization_manager._string_cache.broken_value == nil
		and hits.localization_guard == 2
		and actions.localization_guard == 2,
	"localization repair returns visible fallbacks without poisoning the string cache"
)

reset_world()
local campaign = dofile("scripts/mods/TertiumFixes/modules/campaign_vox_cleanup.lua")
campaign:install()
local stopped_sounds = {}
Managers = {
	ui = {
		stop_2d_sound = function (_, sound_id)
			stopped_sounds[#stopped_sounds + 1] = sound_id
		end,
	},
}
local content_a = {
	hover_sound_id = 101,
	hover_sound_played = true,
}
local content_b = {
	hover_sound_id = 102,
	hover_sound_played = true,
}
local campaign_list = {
	_mission_grid = {
		{
			{
				debrief_widget = {
					content = content_a,
				},
			},
			{
				debrief_widget = {
					content = content_b,
				},
			},
		},
	},
}
local original_saw_cleared = false

callback("campaign_vox_cleanup", "on_exit")(
	function ()
		original_saw_cleared = content_a.hover_sound_id == nil
			and content_b.hover_sound_id == nil
	end,
	campaign_list
)

check(
	original_saw_cleared
		and #stopped_sounds == 2
		and content_a.hover_sound_played == nil
		and content_b.hover_sound_played == nil
		and hits.campaign_vox_cleanup == 1
		and actions.campaign_vox_cleanup == 2,
	"campaign cleanup stops and clears every owned hover sound before stock teardown"
)

reset_world()
local path_of_trust = dofile("scripts/mods/TertiumFixes/modules/path_of_trust_black_screen.lua")
path_of_trust:install()
local cinematic_manager_path = "scripts/managers/cinematic/cinematic_manager"
local cutscene_fade_path = "scripts/ui/hud/elements/cutscene_fading/hud_element_cutscene_fading"
local cinematic_update = callback("path_of_trust_black_screen", "update", cinematic_manager_path)
local cutscene_fade_update = callback("path_of_trust_black_screen", "update", cutscene_fade_path)

check(
	type(cinematic_update) == "function"
		and type(cutscene_fade_update) == "function"
		and hooks["path_of_trust_black_screen:" .. cinematic_manager_path .. ":update"].hook_kind == "normal"
		and hooks["path_of_trust_black_screen:" .. cutscene_fade_path .. ":update"].hook_kind == "safe",
	"Path of Trust legacy fallback installs only its exact completion and fade-state hooks"
)

runtime.clock = 5
local result_a = {}
local result_b = {}
local result_c = {}
local result_d = {}
local stock_manager_calls = 0
local cinematic_manager = {
	_active_story = {
		cinematic_scene_name = "path_of_trust_09",
	},
	_is_server = false,
	_queued_stories = {},
}
local returned_a, returned_b, returned_c, returned_d = cinematic_update(
	function (manager)
		stock_manager_calls = stock_manager_calls + 1
		manager._active_story = nil

		return result_a, result_b, result_c, result_d
	end,
	cinematic_manager
)

check(
	stock_manager_calls == 1
		and returned_a == result_a
		and returned_b == result_b
		and returned_c == result_c
		and returned_d == result_d
		and hits.path_of_trust_black_screen == 1
		and actions.path_of_trust_black_screen == nil
		and path_of_trust:runtime_status() == "checking final fade",
	"Path of Trust fallback arms only after stock finishes the exact Path09 story with an empty queue"
)

local fade_calls = 0
local fade_player = {}
local fade_color = {}
local fade_duration
local fade_easing
local fade_color_seen
local hud = {
	_fade_color = fade_color,
	_fade_duration = nil,
	_fade_out_data = nil,
	_fading_in = true,
	_player = fade_player,
}

function hud:event_cutscene_fade_out(player, duration, easing, color)
	fade_calls = fade_calls + 1
	fade_duration = duration
	fade_easing = easing
	fade_color_seen = color
	self._fade_duration = duration
	self._fading_in = false
end

cutscene_fade_update(hud)

check(
	fade_calls == 1
		and fade_duration == 0.25
		and fade_easing == nil
		and fade_color_seen == fade_color
		and actions.path_of_trust_black_screen == 1
		and path_of_trust:runtime_status() == "guarding legacy scene"
		and string.find(path_of_trust:describe(), "matching general symptom", 1, true) ~= nil,
	"Path of Trust fallback releases only the terminal fully-black HUD through its stock fade path; exact 1.12.4 Path09 coverage remains uncertain"
)

local function finish_story(manager)
	return cinematic_update(function (stock_manager)
		stock_manager._active_story = nil
	end, manager)
end

path_of_trust:reset()
local hits_before_scoped_noops = hits.path_of_trust_black_screen
finish_story({
	_active_story = {
		cinematic_scene_name = "path_of_trust_08",
	},
	_is_server = false,
	_queued_stories = {},
})
finish_story({
	_active_story = {
		cinematic_scene_name = "path_of_trust_09",
	},
	_is_server = false,
	_queued_stories = {
		{},
	},
})
finish_story({
	_active_story = {
		cinematic_scene_name = "path_of_trust_09",
	},
	_is_server = true,
	_queued_stories = {},
})

check(
	hits.path_of_trust_black_screen == hits_before_scoped_noops
		and actions.path_of_trust_black_screen == 1
		and path_of_trust:runtime_status() == "guarding legacy scene",
	"Path of Trust fallback ignores other scenes, queued cinematics, and server-owned stories"
)

runtime.clock = 20
finish_story({
	_active_story = {
		cinematic_scene_name = "path_of_trust_09",
	},
	_is_server = false,
	_queued_stories = {},
})
local scheduled_hud = {
	_fade_duration = nil,
	_fade_out_data = {
		fade_out_at = 21,
	},
	_fading_in = true,
	_player = {},
	event_cutscene_fade_out = function ()
		fade_calls = fade_calls + 1
	end,
}
cutscene_fade_update(scheduled_hud)
local stayed_armed_for_scheduled_fade = path_of_trust:runtime_status() == "checking final fade"
scheduled_hud._fade_out_data = nil
scheduled_hud._fading_in = false
cutscene_fade_update(scheduled_hud)

check(
	stayed_armed_for_scheduled_fade
		and fade_calls == 1
		and actions.path_of_trust_black_screen == 1
		and path_of_trust:runtime_status() == "guarding legacy scene",
	"Path of Trust fallback leaves scheduled and already-clearing fades to the game"
)

runtime.clock = 30
finish_story({
	_active_story = {
		cinematic_scene_name = "path_of_trust_09",
	},
	_is_server = false,
	_queued_stories = {},
})
runtime.clock = 41
local expired_hud = {
	_fade_duration = nil,
	_fade_out_data = nil,
	_fading_in = true,
	_player = {},
	event_cutscene_fade_out = function ()
		fade_calls = fade_calls + 1
	end,
}
cutscene_fade_update(expired_hud)

check(
	fade_calls == 1
		and actions.path_of_trust_black_screen == 1
		and path_of_trust:runtime_status() == "guarding legacy scene",
	"Path of Trust fallback expires without acting outside its ten-second completion window"
)

reset_world()
DEDICATED_SERVER = true
local dedicated_path_of_trust = dofile("scripts/mods/TertiumFixes/modules/path_of_trust_black_screen.lua")
dedicated_path_of_trust:install()

check(
	next(hooks) == nil
		and availability.path_of_trust_black_screen.value == false
		and availability.path_of_trust_black_screen.reason == "dedicated server",
	"Path of Trust fallback remains unavailable on dedicated servers"
)

reset_world()
local gas = dofile("scripts/mods/TertiumFixes/modules/gas_outline_recovery.lua")
gas:install()
local template_names = {
	"in_toxic_gas",
	"in_cultist_grenadier_gas",
	"in_twin_toxic_gas",
	"in_buildup_twin_toxic_gas",
}
local gas_templates = {}
local original_stops = 0

for index = 1, #template_names do
	gas_templates[template_names[index]] = {
		class_name = "interval_buff",
		player_effects = {
			looping_wwise_start_event = "wwise/events/player/play_player_gas_enter",
			looping_wwise_stop_event = "wwise/events/player/play_player_gas_exit",
		},
		start_func = function ()
		end,
		stop_func = function ()
			original_stops = original_stops + 1
		end,
	}
end

local first_original_stop = gas_templates.in_toxic_gas.stop_func
deliver("scripts/settings/buff/liquid_area_buff_templates", gas_templates)
local visibility_calls = 0
local outline_system = {
	set_global_visibility = function (_, visible)
		if visible == true then
			visibility_calls = visibility_calls + 1
		end
	end,
}
Managers = {
	state = {
		extension = {
			system = function (_, system_name)
				return system_name == "outline_system" and outline_system or nil
			end,
		},
	},
}
local dead_unit = {}
HEALTH_ALIVE = {
	[dead_unit] = false,
}
gas_templates.in_toxic_gas.stop_func({}, {
	is_local_unit = true,
	is_player = true,
	unit = dead_unit,
})

check(
	original_stops == 1
		and visibility_calls == 1
		and hits.gas_outline_recovery == 1
		and actions.gas_outline_recovery == 1,
	"toxic-gas repair preserves stock stop then restores outlines for the dead local player"
)

gas:on_disabled()

check(
	gas_templates.in_toxic_gas.stop_func == first_original_stop,
	"toxic-gas repair restores the exact original stop callback"
)

reset_world()
local servo = dofile("scripts/mods/TertiumFixes/modules/servo_skull_scroll.lua")
servo:install()
local shared_wield_inputs = {
	{
		input = "wield_scroll_up",
	},
	{
		input = "keyboard_weapon_one",
	},
	{
		input = "wield_scroll_down",
	},
	{
		input = "controller_weapon_one",
	},
}
local servo_step = {
	inputs = shared_wield_inputs,
}
local servo_template = {
	action_inputs = {
		wield = {
			input_sequence = {
				servo_step,
			},
		},
	},
	not_scroll_wieldable = true,
}

deliver("scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point", servo_template)
deliver("scripts/settings/player_character/player_character_constants", {
	wield_inputs = shared_wield_inputs,
})

check(
	servo_step.inputs ~= shared_wield_inputs
		and #servo_step.inputs == 2
		and servo_step.inputs[1].input == "keyboard_weapon_one"
		and servo_step.inputs[2].input == "controller_weapon_one"
		and #shared_wield_inputs == 4
		and hits.servo_skull_scroll == 2
		and actions.servo_skull_scroll == 1,
	"Servo-Skull opt-in removes only two wheel inputs from a private clone"
)

servo:on_disabled()

check(servo_step.inputs == shared_wield_inputs, "Servo-Skull opt-in restores the shared input identity")

reset_world()
local chain = dofile("scripts/mods/TertiumFixes/modules/chain_smoke_cleanup.lua")
chain:install()
local order = {}
local current_effect = 42
local effects = {
	_inventory_slot_component = {
		special_active = false,
	},
	_world = {},
}

function effects:_looping_effect_id()
	return current_effect
end

World = {
	are_particles_playing = function (_, effect_id)
		return effect_id == 42
	end,
	destroy_particles = function (_, effect_id)
		order[#order + 1] = "destroy:" .. tostring(effect_id)
	end,
}

callback("chain_smoke_cleanup", "_update_active")(
	function ()
		order[#order + 1] = "stock-end-sound"
		current_effect = nil
	end,
	effects
)

check(
	order[1] == "stock-end-sound"
		and order[2] == "destroy:42"
		and hits.chain_smoke_cleanup == 1
		and actions.chain_smoke_cleanup == 1,
	"chain-smoke opt-in preserves the stock end transition before destroying its released tail"
)

io.write(string.format("remaining_repairs_behavior: %d passed, %d failed\n", checks - failures, failures))

if failures > 0 then
	os.exit(1)
end
