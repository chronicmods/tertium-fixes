local source_root = arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT")

if not source_root or source_root == "" then
	print("SKIP effect source checks: set DARKTIDE_SOURCE_ROOT to the extracted game scripts")
	return
end

local checks, failures = 0, 0

local function check(condition, message)
	checks = checks + 1

	if condition then
		print("PASS " .. message)
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local function game_file(path)
	return dofile(source_root .. "/" .. path .. ".lua")
end

local hooks, settings, hook_list = {}, {}, {}
local templates
local runtime = {}

function runtime:install_hook(id, path, method, kind, callback)
	hooks[id] = hooks[id] or {}
	hooks[id][method] = { callback = callback, kind = kind, path = path }
	hook_list[#hook_list + 1] = { id = id, path = path, method = method, kind = kind, callback = callback }
	return true
end

function runtime:defer_file(_, _, callback)
	callback(templates)
	return true
end

function runtime:is_active(id)
	return settings[id] ~= false
end

function runtime:run(_, callback, ...)
	return pcall(callback, ...)
end

function runtime:record_hit() end
function runtime:record_action() end
function runtime:set_available(_, available, reason)
	assert(available, reason)
end
function runtime:get() return true end
function runtime:mod_is_enabled() return true end

local function apply_hooks(module_id, path, target)
	for _, hook in ipairs(hook_list) do
		if hook.id == module_id and hook.path == path then
			local original = assert(target[hook.method])
			if hook.kind == "safe" then
				target[hook.method] = function (...)
					local a, b, c, d = original(...)
					hook.callback(...)
					return a, b, c, d
				end
			else
				target[hook.method] = function (...) return hook.callback(original, ...) end
			end
		end
	end
end

local mod = { _tf_runtime = runtime, warning = function () end }
function get_mod() return mod end

function class(_, parent)
	local result = { super = parent and _G[parent] or {} }
	result.__index = result
	return result
end

function implements() end

table.clear = function (value)
	for key in pairs(value) do value[key] = nil end
end
table.index_of = function (array, needle)
	for index = 1, #array do
		if array[index] == needle then return index end
	end
end
table.swap_delete = function (array, index)
	assert(index, "running effect was not in the list")
	array[index], array[#array] = array[#array], nil
end

local vector_meta = {}
local function vector(x, y, z)
	return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector_meta)
end
vector_meta.__add = function (a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vector_meta.__sub = function (a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
Vector3 = setmetatable({
	zero = vector,
	invalid_vector = vector,
	normalize = function (v) return v end,
	flat = function (v) return v end,
	length = function (v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
	multiply = function (v, n) return vector(v.x * n, v.y * n, v.z * n) end,
	direction_length = function (v) return v, 1 end,
}, { __call = function (_, ...) return vector(...) end })
Vector3Box = function (value)
	return {
		value = value,
		store = function (self, next_value) self.value = next_value end,
		unbox = function (self) return self.value end,
	}
end
Quaternion = {
	look = function (v) return v end,
	forward = function () return vector(0, 1, 0) end,
	identity = function () return {} end,
}
Matrix4x4 = { identity = function () return {} end }
Script = { new_array = function () return {} end }
GameParameters = { destroy_unmanaged_particles = false }
DEDICATED_SERVER = false
ALIVE, HEALTH_ALIVE = {}, {}

local world, wwise_world = {}, {}
local live_session, old_session = {}, {}
local source_count, sound_stops, particle_stops, particle_moves = 0, 0, 0, 0
local destroyed_sources, destroyed_particles = {}, {}
local fields_read = 0
local extensions, players, ids = {}, {}, {}

World = {
	get_data = function (_, key) return key == "wwise_world" and wwise_world end,
	create_particles = function () return 501 end,
	stop_spawning_particles = function (_, id)
		assert(id, "missing particle")
		particle_stops = particle_stops + 1
	end,
	destroy_particles = function (owner_world, id)
		assert(id, "missing particle")
		destroyed_particles[#destroyed_particles + 1] = { world = owner_world, id = id }
	end,
	move_particles = function () particle_moves = particle_moves + 1 end,
	find_particles_variable = function () return 1 end,
	set_particles_variable = function () end,
	link_particles = function () end,
}
WwiseWorld = {
	make_manual_source = function () source_count = source_count + 1; return source_count end,
	make_auto_source = function () return 91 end,
	stop_event = function (_, id) assert(id); sound_stops = sound_stops + 1 end,
	trigger_resource_event = function () return 77 end,
	destroy_manual_source = function (_, id) destroyed_sources[#destroyed_sources + 1] = id end,
	set_source_parameter = function () end,
}
Unit = {
	world = function () return world end,
	node = function () return 1 end,
	world_position = function () return vector(0, 0, 0) end,
	world_rotation = function () return {} end,
}
ScriptUnit = {
	has_extension = function (unit, name) return extensions[unit] and extensions[unit][name] end,
	extension = function (unit, name)
		local extension = extensions[unit] and extensions[unit][name]
		assert(extension, "missing extension: " .. name)
		return extension
	end,
}
Managers = {
	state = {
		extension = { system = function () return {} end },
		player_unit_spawn = { owner = function (_, unit) return players[unit] end },
		game_session = { game_session = function () return live_session end },
		unit_spawner = { game_object_id = function (_, unit) return ids[unit] end },
	},
	time = { time = function () return 1 end },
}
GameSession = {
	game_object_exists = function (session, id) return session == live_session and id ~= nil end,
	game_object_field = function (session, _, name)
		assert(session == live_session, "expired game session")
		fields_read = fields_read + 1
		if name == "fx_impact_position" then return vector(0, 1, 0) end
		if name == "fx_position_valid" then return false end
		return 0.5
	end,
}
Log = { exception = function () error("unexpected empty effect stop") end }

local dependencies = {
	["scripts/utilities/companion_visual_loadout"] = {
		trigger_gear_sound = function () source_count = source_count + 1; return 77 end,
		trigger_looping_gear_sound = function () return 77, "stop_loop" end,
	},
	["scripts/utilities/minion_visual_loadout"] = {
		attachment_unit_and_node_from_node_name = function (item) return item.unit, 1 end,
	},
	["scripts/utilities/companion/companion_servo_skull_ability"] = {},
	["scripts/settings/companion/companion_servo_skull_settings"] = { FLAMETHROWER_TYPES = {} },
	["scripts/settings/ability/special_rules_settings"] = { special_rules = {} },
}

local function settings_file(name)
	dependencies["scripts/settings/companion/" .. name] = {
		inventory_slot = "slot_weapon",
		vfx = { max_range = 12, speed = 6, max_value = 1, charge_up = "charge" },
		sfx = { source_name = "base", sound_alias = "servo_loop" },
	}
end
settings_file("companion_servo_skull_aim_on_ground_effect_settings")
settings_file("companion_servo_skull_flamer_settings")
settings_file("companion_servo_skull_empowered_effect_settings")
settings_file("companion_servo_skull_charged_shooting_effect_settings")

local original_require = require
function require(path)
	return dependencies[path] or original_require(path)
end

local template_files = {
	"companion_servo_skull_moving_effect",
	"companion_servo_skull_aim_on_ground_effect",
	"companion_servo_skull_flamer",
	"companion_servo_skull_empowered_effect",
	"companion_servo_skull_charged_shooting_effect",
	"arc_chain_to_position",
}
templates = {}
local originals = {}
for _, filename in ipairs(template_files) do
	local template = game_file("scripts/settings/fx/effect_templates/" .. filename)
	templates[template.name] = template
	originals[template.name] = {
		start = template.start,
		update = template.update,
		stop = template.stop,
	}
end

local effect_module = dofile("scripts/mods/TertiumFixes/modules/effect_template_safety.lua")
effect_module:install()

local skull = {}
ALIVE[skull], ids[skull] = true, 11
extensions[skull] = { fx_system = { sound_source = function () return 19 end } }
local context = { world = world, wwise_world = wwise_world }

local moving = templates.companion_servo_skull_moving_effect
local stock_missing_movement = pcall(originals[moving.name].start, { unit = skull }, context)
check(not stock_missing_movement and source_count == 1,
	"stock servo sound starts before the missing movement extension raises an error")
source_count = 0
local incomplete = { unit = skull }
local guarded_start = pcall(moving.start, incomplete, context)
check(guarded_start and source_count == 0,
	"servo startup waits for its movement extension before starting audio")
check(pcall(moving.update, incomplete, context, 0.016, 1), "a skipped servo start cannot run its update")
check(pcall(moving.stop, incomplete, context), "a skipped servo start can stop safely")

local deleted_reads = 0
local deleted = setmetatable({ __deleted = true }, {
	__index = function () deleted_reads = deleted_reads + 1; error("accessed deleted extension") end,
})
local moving_data = {
	unit = skull, flying_companion_movement_extension = deleted,
	wwise_world = wwise_world, source_id = 19, playing_id = 77,
}
check(not pcall(originals[moving.name].update, moving_data, context, 0.016, 1),
	"stock servo update reads a deleted movement extension")
deleted_reads = 0
local stops_before = sound_stops
check(pcall(moving.update, moving_data, context, 0.016, 1)
	and deleted_reads == 0 and sound_stops == stops_before + 1,
	"deleted servo movement extensions stop their own loop without member access")

local live_movement = {
	current_velocity = function () return Vector3Box(vector(1, 0, 0)) end,
	angle_between_velocity_and_player_forward = function () return 0 end,
}
extensions[skull].flying_companion_movement_system = live_movement
local healthy = { unit = skull }
check(pcall(moving.start, healthy, context) and healthy.playing_id == 77,
	"a ready servo still starts the stock loop")
check(pcall(moving.update, healthy, context, 0.016, 1), "a ready servo still runs the stock audio update")

local player_unit = {}
ALIVE[player_unit] = true
local aim = templates.companion_servo_skull_aim_on_ground_effect
local aim_data = {
	unit = skull, is_local_unit = true, _player_unit = player_unit, _world = world,
	_position_finder_component = { position_valid = true },
	_action_module_target_finder_component = {},
	_combat_ability_action_component = {}, _grenade_ability_action_component = {},
	_unit_data_extension = {}, _input_extension = {}, _talent_extension = deleted,
	_ability_extension = {}, _companion_spawner_extension = {}, _targeting_effect_id = 88,
}
local before_particles = #destroyed_particles
check(pcall(aim.update, aim_data, context, 0.016, 1)
	and #destroyed_particles == before_particles + 1 and aim_data._targeting_effect_id == nil,
	"servo targeting releases its marker when a cached player extension is deleted")

local attachment = {}
ALIVE[attachment] = true
local flamer = templates.companion_servo_skull_flamer
local stale_flamer = {
	unit = skull, attachment_unit = attachment, attachment_node = 1,
	game_session = old_session, game_object_id = 11,
	stream_effect_id = 101, source_id = 102, playing_id = 103, stop_event_name = "stop_loop",
}
check(not pcall(originals[flamer.name].update, stale_flamer, context, 0.016, 1),
	"stock flamer update reads its expired cached session even while the unit has a current game object")
local before_fields, before_stops = fields_read, particle_stops
check(pcall(flamer.update, stale_flamer, context, 0.016, 1)
	and fields_read == before_fields and particle_stops == before_stops + 1,
	"flamer update checks the cached session before touching its fields")
check(stale_flamer.source_id == nil and destroyed_sources[#destroyed_sources] == 102,
	"invalid flamer cleanup releases its manual source")

local healthy_flamer = {
	unit = skull, attachment_unit = attachment, attachment_node = 1,
	game_session = live_session, game_object_id = 11, stream_effect_id = 301,
}
local before_moves = particle_moves
check(pcall(flamer.update, healthy_flamer, context, 0.016, 1)
	and particle_moves == before_moves + 1,
	"a healthy flamer still moves the original particles")

local invalid_update = pcall(moving.update, nil, context, 0.016, 1)
check(invalid_update, "an absent template data table does not make cleanup raise another error")

local owned_world, replacement_world = {}, {}
local world_data = {
	is_local_unit = true, _player_unit = player_unit,
	_world = owned_world, _targeting_effect_id = 809,
}
aim.update(world_data, { world = replacement_world }, 0.016, 1)
check(destroyed_particles[#destroyed_particles].world == owned_world,
	"targeting cleanup uses the world that created the marker")

settings.effect_template_safety = false
effect_module:on_disabled()
check(pcall(flamer.stop, stale_flamer, context), "disabling during cleanup leaves the final stop safe")
settings.effect_template_safety = true

dependencies["scripts/settings/damage/attack_settings"] = { attack_types = {} }
dependencies["scripts/settings/buff/buff_settings"] = { keywords = {}, proc_events = {} }
dependencies["scripts/settings/buff/buff_templates"] = {}
dependencies["scripts/utilities/attack/explosion"] = {}
dependencies["scripts/settings/damage/explosion_templates"] = {}
dependencies["scripts/utilities/fixed_frame"] = { get_latest_fixed_time = function () return 10 end }
dependencies["scripts/settings/buff/hordes_buffs/hordes_buffs_data"] = {
	hordes_buff_broker_stimm_field_shock_on_interval = { buff_stats = { time = { value = 1 } } },
}
dependencies["scripts/managers/unit_job/job_interface"] = {}
dependencies["scripts/settings/damage/power_level_settings"] = {}
dependencies["scripts/settings/buff/helper_functions/shared_buff_functions"] = {}
dependencies["scripts/settings/talent/talent_settings"] = {
	broker = { combat_ability = { stimm_field = { proximity_radius = 5 } } }, broker_stimm = {},
}
dependencies["scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout"] = {}
local StimmField = game_file("scripts/extension_systems/proximity/side_relation_gameplay_logic/proximity_broker_stimm_field")
local stimm_module = dofile("scripts/mods/TertiumFixes/modules/stimm_field_deleted_extension_guard.lua")
stimm_module:install()
local stock_remove = StimmField._remove_buff_from_unit
local stock_add = StimmField._add_buff_to_unit
for method, hook in pairs(hooks[stimm_module.id]) do
	local original = StimmField[method]
	StimmField[method] = function (...) return hook.callback(original, ...) end
end

local stimm_unit = {}
HEALTH_ALIVE[stimm_unit] = true
local stale_row = { buff_extension = deleted, buff_datas = { { local_id = 77 } } }
local broker = setmetatable({
	_started = true, _units_in_proximity = { [stimm_unit] = stale_row }, _lingering_units = {},
}, StimmField)
check(not pcall(stock_remove, broker, 10, stimm_unit),
	"stock stimm exit without linger reads a deleted buff extension")
deleted_reads = 0
check(pcall(broker._remove_buff_from_unit, broker, 10, stimm_unit)
	and broker._units_in_proximity[stimm_unit] == nil and deleted_reads == 0,
	"stimm exit also handles deleted extensions when linger is not selected")

local reapplied_ids, added_buffs = {}, 0
extensions[stimm_unit] = { buff_system = {
	reapply_externally_controlled_lingering_buff = function (_, id)
		reapplied_ids[#reapplied_ids + 1] = id
		return nil, 999
	end,
	add_externally_controlled_buff = function () added_buffs = added_buffs + 1; return nil, 1000 end,
} }
local function returning_broker()
	return setmetatable({
		_started = true, _units_in_proximity = { [stimm_unit] = { buff_datas = {} } },
		_lingering_units = { [stimm_unit] = {
			buff_extension = deleted,
			buff_datas = { { local_id = 77, template_name = "stimm", reappliable_buff = true } },
		} },
		_units_affected_during_lifetime = {}, _previously_proximate_units = {},
		_buffs_to_add = { "stimm" }, _single_application_buffs = {},
	}, StimmField)
end
local stock_broker = returning_broker()
stock_add(stock_broker, 10, stimm_unit)
check(reapplied_ids[1] == 77,
	"stock stimm re-entry gives an old extension's buff ID to the replacement extension")
reapplied_ids = {}
local guarded_broker = returning_broker()
guarded_broker:_add_buff_to_unit(10, stimm_unit)
check(#reapplied_ids == 0 and added_buffs == 1
	and guarded_broker._units_in_proximity[stimm_unit].buff_extension == extensions[stimm_unit].buff_system,
	"stimm re-entry creates fresh buffs after the previous extension was destroyed")

local live_removals = 0
local live_extension = { remove_externally_controlled_buff = function () live_removals = live_removals + 1 end }
broker._units_in_proximity[stimm_unit] = { buff_extension = live_extension, buff_datas = { { local_id = 88 } } }
broker:_remove_buff_from_unit(11, stimm_unit)
check(live_removals == 1, "healthy stimm exits still use the stock removal")

dependencies["scripts/utilities/component"] = {}
dependencies["scripts/extension_systems/visual_loadout/wieldable_slot_scripts/wieldable_slot_script_interface"] = {}
local slot_script_path = "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/"
local WindStage = game_file(slot_script_path .. "force_weapon_wind_slash_stage_effects")
local Tox = game_file(slot_script_path .. "tox_grenade_effects")
local Overheat = game_file(slot_script_path .. "power_weapon_overheat_effects")
local stock_camera_stage = WindStage.update_first_person_mode
local stock_tox_stop = Tox._stop_vfx_loop
local stock_power_destroy = Overheat.destroy
local transitions = dofile("scripts/mods/TertiumFixes/modules/weapon_effect_transitions.lua")
transitions:install()
local effect_classes = {
	[slot_script_path .. "force_weapon_wind_slash_stage_effects"] = WindStage,
	[slot_script_path .. "tox_grenade_effects"] = Tox,
	[slot_script_path .. "power_weapon_overheat_effects"] = Overheat,
}
for _, hook in ipairs(hook_list) do
	if hook.id == transitions.id then
		local target = assert(effect_classes[hook.path])
		local original = assert(target[hook.method])
		if hook.kind == "safe" then
			target[hook.method] = function (...)
				local a, b, c, d = original(...)
				hook.callback(...)
				return a, b, c, d
			end
		else
			target[hook.method] = function (...) return hook.callback(original, ...) end
		end
	end
end

local source_id = 10
local playing, next_playing_id = {}, 2000
local failed_stop = false
WwiseWorld.trigger_resource_event = function (_, event, source)
	if event == "stop_loop" then
		for _, sound in pairs(playing) do
			if sound.source == source then sound.active = false end
		end
		return
	end
	next_playing_id = next_playing_id + 1
	playing[next_playing_id] = { source = source, active = true }
	return next_playing_id
end
WwiseWorld.stop_event = function (_, id)
	assert(not failed_stop, "native stop failed")
	assert(id, "missing playing ID")
	if playing[id] then playing[id].active = false end
end
local fx = {
	sound_source = function () return source_id end,
	should_play_husk_effect = function () return false end,
}
local visual = {
	resolve_gear_particle = function () return false end,
	resolve_looping_gear_sound = function () return true, "start_loop", true, "stop_loop" end,
}
local function tox_effect()
	return setmetatable({
		_wwise_world = wwise_world, _world = world, _fx_extension = fx,
		_visual_loadout_extension = visual, _sfx_source_name = "cap",
	}, Tox)
end

settings.weapon_effect_transitions = false
local stock_tox = tox_effect()
stock_tox:_start_vfx_loop()
local abandoned_id = stock_tox._sfx_loop_id
source_id = 11
stock_tox_stop(stock_tox, true)
check(playing[abandoned_id].active,
	"stock chem grenade stop leaves its old loop playing when the sound source has moved")
playing[abandoned_id].active = false

settings.weapon_effect_transitions = true
source_id = 10
local tox = tox_effect()
tox:_start_vfx_loop()
tox:update_first_person_mode(false)
local before_move_id = tox._sfx_loop_id
source_id = 11
tox:update({}, 0.016, 1)
local after_move_id = tox._sfx_loop_id
check(not playing[before_move_id].active and playing[after_move_id].active
	and playing[after_move_id].source == 11,
	"chem grenade camera changes restart the loop on the new source after stopping the old playing ID")
tox:update({}, 0.016, 1)
check(tox._sfx_loop_id == after_move_id, "ordinary chem grenade updates do not restart a healthy loop")

source_id = 12
failed_stop = true
tox:update({}, 0.016, 1)
check(tox._sfx_loop_id == after_move_id and playing[after_move_id].active,
	"a failed native stop keeps the chem grenade playing ID for a retry")
failed_stop = false
tox:update({}, 0.016, 1)
check(tox._sfx_loop_id ~= after_move_id and not playing[after_move_id].active,
	"chem grenade audio can recover on the next update after a native stop failure")
local final_tox_id = tox._sfx_loop_id
source_id = 13
tox:unwield()
check(not playing[final_tox_id].active and tox._sfx_loop_id == nil,
	"chem grenade unwield stops the original playing ID even if the source changed again")

local function power_effect()
	return setmetatable({
		_world = world, _wwise_world = wwise_world, _fx_extension = fx,
		_visual_loadout_extension = visual, _special_active_fx_source_name = "special",
		_inventory_slot_component = { overheat_state = "lockout", overheat_current_percentage = 1 },
		_current_stage = "critical",
	}, Overheat)
end
local stock_power = power_effect()
stock_power:_start_lockout_sfx_loop()
local stock_lockout_id = stock_power._looping_lockout_playing_id
stock_power_destroy(stock_power)
check(playing[stock_lockout_id].active, "stock power weapon destroy leaves its lockout audio playing")
playing[stock_lockout_id].active = false

local power = power_effect()
power:_start_lockout_sfx_loop()
local first_lockout_id = power._looping_lockout_playing_id
local unrelated_id = WwiseWorld.trigger_resource_event(wwise_world, "start_other_loop", source_id)
power:update_first_person_mode(false)
check(not playing[first_lockout_id].active and playing[unrelated_id].active,
	"power weapon camera changes stop only the lockout playing ID")
source_id = 14
power:update({}, 0.016, 1)
local moved_lockout_id = power._looping_lockout_playing_id
check(playing[moved_lockout_id].active and playing[moved_lockout_id].source == 14,
	"power weapon update resumes lockout audio on the moved sound source")
power:destroy()
check(not playing[moved_lockout_id].active and power._looping_lockout_playing_id == nil,
	"power weapon destruction releases its lockout loop")
check(pcall(power.destroy, power), "repeated power weapon teardown does not send a nil playing ID")

local tier_cues = 0
local function sword_effect()
	return setmetatable({
		_current_stage = "high", _inventory_slot_component = { num_special_charges = 3 },
		_weapon_special_tweak_data = { thresholds = {
			{ name = "low", threshold = 1 }, { name = "middle", threshold = 2 }, { name = "high", threshold = 3 },
		} },
		_stop_stage_particle_loop = function () end, _stop_stage_sound_loop = function () end,
		_update_stage_interfacing = function () tier_cues = tier_cues + 1 end,
		_update_material_variables = function () end,
		_update_particle_loop = function () end, _update_sound_loop = function () end,
	}, WindStage)
end
local stock_sword = sword_effect()
stock_camera_stage(stock_sword, true)
stock_sword:update()
check(tier_cues == 1,
	"stock force greatsword visibility refresh plays a tier gain cue without gaining charges")
tier_cues = 0
local sword = sword_effect()
sword:update_first_person_mode(true)
sword:update()
check(tier_cues == 0 and sword._current_stage == "high",
	"force greatsword visibility refresh keeps its existing charge tier")
sword._inventory_slot_component.num_special_charges = 2
sword:update()
tier_cues = 0
sword:update_first_person_mode(false)
sword._inventory_slot_component.num_special_charges = 3
sword:update()
check(tier_cues == 1, "real charge tier gains still run the stock cue after a camera change")

local retry_power = power_effect()
retry_power:_start_lockout_sfx_loop()
local retry_id = retry_power._looping_lockout_playing_id
failed_stop = true
retry_power:update_first_person_mode(true)
check(retry_power._looping_lockout_playing_id == retry_id and playing[retry_id].active,
	"a failed power weapon stop retains its playing ID")
failed_stop = false
source_id = 15
retry_power:update({}, 0.016, 1)
check(not playing[retry_id].active and playing[retry_power._looping_lockout_playing_id].source == 15,
	"the next power weapon update retries an interrupted camera stop before starting its replacement")

local handler_path = "scripts/extension_systems/fx/utilities/effect_templates_handler"
local Handler = game_file(handler_path)
local stock_id_check = Handler.has_running_effect_with_global_id
local handler_module = dofile("scripts/mods/TertiumFixes/modules/fx_handler_integrity.lua")
handler_module:install()
apply_hooks(handler_module.id, handler_path, Handler)
local sent_rpcs = 0
Managers.state.game_session.send_rpc_clients = function () sent_rpcs = sent_rpcs + 1 end
NetworkLookup = { effect_templates = { test_effect = 1 } }
local handler = setmetatable({}, Handler)
handler:init(2, true)
handler_module:_mark_local_handler(handler)
local stopped_effects = 0
local template = {
	name = "test_effect",
	start = function (data) data.owned_value = 71 end,
	update = function () return true end,
	stop = function (data) assert(data.owned_value == 71); stopped_effects = stopped_effects + 1 end,
}
local id_a = handler:add_template_effect({}, context, template, skull)
local id_b = handler:add_template_effect({}, context, template, attachment)
local id_c = handler:add_template_effect({}, context, template, skull)
check(id_a == 0 and id_b == 1 and id_c == 2 and stopped_effects == 1,
	"local effect buffer saturation stops the old effect before reusing its slot")
check(stock_id_check(handler, id_a) and not handler:has_running_effect_with_global_id(id_a),
	"the real stock handler confuses a reused slot with its old ID; the guard distinguishes them")
handler:remove_template_effect(context, id_a)
check(handler:has_running_effect_with_global_id(id_c), "a stale stop cannot remove the newer effect from the same slot")
handler:update(context, 0.016, 1)
check(#handler._running_template_effects == 0 and stopped_effects == 3 and sent_rpcs == 0,
	"local lifetime expiry stops real handler slots and sends no client RPC")
check(next(handler._template_effects[1].template_data) == nil,
	"the real handler clears stopped template data before reuse")
local owned_id = handler:add_template_effect({}, context, template, attachment, nil, nil, skull)
handler:remove_effects_on_unit(context, skull)
check(not handler:has_running_effect_with_global_id(owned_id) and stopped_effects == 4,
	"removing a player also removes effects attached elsewhere but owned by that player")

dependencies["scripts/settings/effects/line_effects"] = {}
dependencies["scripts/settings/particles/player_character_looping_particle_aliases"] = {
	screen = { screen_space = true, particle_alias = "screen" },
}
dependencies["scripts/settings/sound/player_character_looping_sound_aliases"] = {}
dependencies["scripts/extension_systems/visual_loadout/utilities/visual_loadout_extract_data"] = { ROOT_ATTACH_NAME = "root" }
NetworkConstants = { particle_index_min = 1, particle_index_max = 256 }
local player_fx_path = "scripts/extension_systems/fx/player_unit_fx_extension"
local PlayerFx = game_file(player_fx_path)
World.create_particles = function (owner_world) assert(owner_world, "missing render world"); return 701 end
local player_fx = setmetatable({
	_world = world, _wwise_world = wwise_world, _is_in_first_person_mode = true,
	_looping_particles = { screen = {} },
	_visual_loadout_extension = { resolve_gear_particle = function () return true, "screen_particle" end },
}, PlayerFx)
check(not pcall(player_fx._spawn_looping_particles, player_fx, "screen"),
	"stock local screen particles pass self._ instead of the render world")
local player_fx_module = dofile("scripts/mods/TertiumFixes/modules/player_fx_lifecycle.lua")
player_fx_module:install()
apply_hooks(player_fx_module.id, player_fx_path, PlayerFx)
check(pcall(player_fx._spawn_looping_particles, player_fx, "screen")
	and player_fx._looping_particles.screen.id == 701,
	"the world repair works through the actual local screen particle call")

local live_sources = {}
WwiseWorld.has_source = function (_, id) return live_sources[id] == true end
WwiseWorld.destroy_manual_source = function (_, id)
	assert(live_sources[id], "manual source already gone")
	live_sources[id] = false
end
WwiseWorld.make_manual_source = function ()
	source_count = source_count + 1
	live_sources[source_count] = true
	return source_count
end
World.are_particles_playing = function () return true end
Managers.event = { unregister = function () end }
local moving_source = WwiseWorld.make_manual_source(wwise_world)
local moving_id = WwiseWorld.trigger_resource_event(wwise_world, "start_loop", moving_source)
local teardown_fx = setmetatable({
	_world = world, _wwise_world = wwise_world, _is_server = true,
	_looping_particles = {}, _looping_sounds = {}, _sources = {}, _vfx_spawners = {},
	_moving_sfx = { size = 1, buffer = { { source_id = moving_source, playing_id = moving_id } } },
	_moving_vfx = { size = 1, buffer = { { effect_id = 900 } } },
}, PlayerFx)
teardown_fx:destroy()
check(not live_sources[moving_source] and not playing[moving_id].active
	and teardown_fx._moving_sfx.size == 0 and teardown_fx._moving_vfx.size == 0,
	"actual player teardown drains moving buffers omitted by the stock destroy loop")

for _, dependency in ipairs({
	"scripts/utilities/breed", "scripts/settings/dialogue/dialogue_breed_settings",
	"scripts/extension_systems/dialogue/dialogue_queries", "scripts/settings/dialogue/dialogue_settings",
	"scripts/utilities/player_voice_grunts", "scripts/utilities/vo",
	"scripts/settings/dialogue/voice_fx_preset_settings", "scripts/settings/dialogue/wwise_vo_routing_settings",
}) do dependencies[dependency] = {} end
Unit.has_node = function () return false end
local dialogue_path = "scripts/extension_systems/dialogue/dialogue_extension"
local Dialogue = game_file(dialogue_path)
local stock_dialogue = setmetatable({ _wwise_world = wwise_world }, Dialogue)
stock_dialogue:extensions_ready(world, skull)
local leaked_source = stock_dialogue._wwise_source_id
stock_dialogue:destroy()
check(live_sources[leaked_source], "stock dialogue teardown leaves its manual source alive")
live_sources[leaked_source] = false
local audio_module = dofile("scripts/mods/TertiumFixes/modules/audio_source_cleanup.lua")
audio_module:install()
apply_hooks(audio_module.id, dialogue_path, Dialogue)
local dialogue = setmetatable({ _wwise_world = wwise_world }, Dialogue)
dialogue:extensions_ready(world, skull)
local original_manual_source = dialogue._wwise_source_id
dialogue:set_wwise_source_id(919)
live_sources[919] = true
dialogue:destroy()
check(not live_sources[original_manual_source] and live_sources[919] and dialogue._wwise_source_id == 919,
	"dialogue cleanup releases only its created manual source after a voice routing replacement")
check(pcall(dialogue.destroy, dialogue) and live_sources[919],
	"repeated dialogue cleanup leaves the replacement engine source alone")

local failed_destroy_power = power_effect()
failed_destroy_power:_start_lockout_sfx_loop()
local failed_destroy_id = failed_destroy_power._looping_lockout_playing_id
failed_stop = true
check(pcall(failed_destroy_power.destroy, failed_destroy_power) and playing[failed_destroy_id].active
	and failed_destroy_power._looping_lockout_playing_id == failed_destroy_id,
	"a native failure during final power weapon destroy is not reported as a released loop")
failed_stop = false
local tracked_tox = tox_effect()
tracked_tox:_start_vfx_loop()
local tracked_tox_id = tracked_tox._sfx_loop_id
settings.weapon_effect_transitions = false
transitions:on_disabled()
check(next(transitions._tox_sources) == nil and next(transitions._pending_lockout_stops) == nil
	and playing[tracked_tox_id].active and playing[failed_destroy_id].active,
	"disable drops saved ownership records and leaves live game sounds alone")
tracked_tox:update()
check(tracked_tox._sfx_loop_id == tracked_tox_id, "disabled weapon hooks leave the current loop unchanged")
settings.weapon_effect_transitions = true
transitions:on_enabled()
check(next(transitions._tox_sources) == nil, "reenabling starts without stale source ownership records")

local replaced_tox = tox_effect()
replaced_tox:_start_vfx_loop()
local replacement_id = WwiseWorld.trigger_resource_event(wwise_world, "start_replacement", source_id)
replaced_tox._sfx_loop_id = replacement_id
source_id = source_id + 1
replaced_tox:update()
check(playing[replacement_id].active and transitions._tox_sources[replaced_tox] == nil,
	"a replaced chem grenade playing ID is not stopped using an old source record")
transitions:on_unload()
check(next(transitions._tox_sources) == nil and next(transitions._pending_lockout_stops) == nil,
	"unload removes all weapon source and pending-stop records")

local original_set_available = runtime.set_available
local dedicated_reason
runtime.set_available = function (_, _, _, reason) dedicated_reason = reason end
DEDICATED_SERVER = true
local dedicated_transitions = dofile("scripts/mods/TertiumFixes/modules/weapon_effect_transitions.lua")
local hooks_before_dedicated = #hook_list
dedicated_transitions:install()
check(#hook_list == hooks_before_dedicated and dedicated_reason == "dedicated server",
	"weapon transition audio hooks are not installed on dedicated servers")
runtime.set_available = original_set_available
DEDICATED_SERVER = false

effect_module:on_unload()
print(string.format("\nEffect source checks: %d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
