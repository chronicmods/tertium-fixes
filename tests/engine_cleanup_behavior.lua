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
local hits = {}
local actions = {}
local availability = {}
local warnings = {}

local function increment(counters, key, amount)
	counters[key] = (counters[key] or 0) + (amount or 1)
end

local runtime = {}

function runtime:install_hook(module_id, path, method, kind, handler)
	hooks[#hooks + 1] = {
		module_id = module_id,
		path = path,
		method = method,
		kind = kind,
		handler = handler,
	}

	return true
end

function runtime:is_active(_)
	return true
end

function runtime:run(_, callback, ...)
	return pcall(callback, ...)
end

function runtime:record_hit(module_id, amount)
	increment(hits, module_id, amount)
end

function runtime:record_action(module_id, amount)
	increment(actions, module_id, amount)
end

function runtime:set_available(module_id, available, reason)
	availability[module_id] = {
		available = available,
		reason = reason,
	}
end

local mod = {
	_tf_runtime = runtime,
}

function mod:warning(format_string, message)
	warnings[#warnings + 1] = string.format(format_string, message)
end

function get_mod(name)
	check(name == "TertiumFixes", "cleanup module requests the expected mod")

	return mod
end

local original_require = require
local require_calls = 0

function require(...)
	require_calls = require_calls + 1

	return original_require(...)
end

local event_module = dofile(
	"scripts/mods/TertiumFixes/modules/event_listener_cleanup.lua"
)
local audio_module = dofile(
	"scripts/mods/TertiumFixes/modules/audio_source_cleanup.lua"
)
local player_fx_module = dofile(
	"scripts/mods/TertiumFixes/modules/player_fx_lifecycle.lua"
)

event_module:install()
audio_module:install()
player_fx_module:install()

check(require_calls == 0, "engine cleanup modules never eagerly require game files")
check(#hooks == 11, "three listener, six audio, and two player-FX hooks install")

local function find_hook(module_id, path, method)
	for i = 1, #hooks do
		local hook = hooks[i]

		if hook.module_id == module_id
			and hook.path == path
			and hook.method == method then
			return hook
		end
	end

	return nil
end

local event_calls = {}

Managers = {
	event = {
		unregister = function (_, owner, event_name)
			event_calls[#event_calls + 1] = {
				owner = owner,
				name = event_name,
			}
		end,
	},
}

local input_hook = find_hook(
	"event_listener_cleanup",
	"scripts/managers/input/input_manager",
	"destroy"
)
local survival_hook = find_hook(
	"event_listener_cleanup",
	"scripts/managers/game_mode/game_modes/game_mode_survival",
	"destroy"
)
local expedition_hook = find_hook(
	"event_listener_cleanup",
	"scripts/utilities/expeditions/expedition_loot_handler",
	"destroy"
)

check(
	input_hook and survival_hook and expedition_hook,
	"all exact event-listener teardown hooks are captured"
)
check(
	input_hook.kind == "safe"
		and survival_hook.kind == "safe"
		and expedition_hook.kind == "safe",
	"listener cleanup runs after stock destroy paths"
)

local input_owner = {}
IS_PLAYSTATION = false
input_hook.handler(input_owner)
check(#event_calls == 0, "PlayStation-only listeners are untouched elsewhere")

IS_PLAYSTATION = true
input_hook.handler(input_owner)
check(
	#event_calls == 4
		and event_calls[1].name
			== "event_update_haptic_trigger_melee_resistance_strength"
		and event_calls[4].name
			== "event_update_haptic_trigger_ranged_vibration_strength",
	"all four omitted haptic listeners are unregistered exactly"
)

local survival_owner = {}
survival_hook.handler(survival_owner)
check(
	#event_calls == 5
		and event_calls[5].owner == survival_owner
		and event_calls[5].name == "hordes_mode_on_mcguffin_picked_up",
	"survival teardown unregisters its omitted objective listener"
)

expedition_hook.handler({
	_is_server = false,
})
check(#event_calls == 5, "client expedition handler never removes a server listener")

local expedition_owner = {
	_is_server = true,
}
expedition_hook.handler(expedition_owner)
check(
	#event_calls == 6
		and event_calls[6].owner == expedition_owner
		and event_calls[6].name == "event_hogtied_player_rescued",
	"server expedition teardown unregisters the rescue listener"
)
check(
	(actions.event_listener_cleanup or 0) == 6,
	"listener telemetry records the six exact unregister operations"
)

local live_sources = {}
local query_fail_for = {}
local destroy_fail_for = {}
local stop_fail_for = {}
local audio_log = {
	queries = 0,
	destroys = 0,
	stops = 0,
	resource_stops = 0,
	world_by_source = {},
}

WwiseWorld = {
	has_source = function (wwise_world, source_id)
		audio_log.queries = audio_log.queries + 1
		audio_log.world_by_source[source_id] = wwise_world

		if query_fail_for[source_id] then
			error("query failure")
		end

		return live_sources[source_id] == true
	end,
	destroy_manual_source = function (wwise_world, source_id)
		if destroy_fail_for[source_id] then
			error("destroy failure")
		end

		audio_log.destroys = audio_log.destroys + 1
		audio_log.world_by_source[source_id] = wwise_world
		live_sources[source_id] = false
	end,
	stop_event = function (_, playing_id)
		if stop_fail_for[playing_id] then
			error("stop failure")
		end

		audio_log.stops = audio_log.stops + 1
	end,
	trigger_resource_event = function (_, _, _)
		audio_log.resource_stops = audio_log.resource_stops + 1
	end,
}

local audio_specs = {
	{
		path = "scripts/extension_systems/dialogue/dialogue_extension",
		owner = {
			_wwise_world = {},
		},
		field = "_wwise_source_id",
	},
	{
		path = "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects",
		owner = {
			_wwise_world = {},
			_source_id = 102,
		},
		field = "_source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/renegade_flamer_mutator_throw",
		owner = {
			source_id = 103,
		},
		context = {
			wwise_world = {},
		},
		field = "source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/cultist_mutant_charge_foley",
		owner = {
			source_id = 104,
		},
		context = {
			wwise_world = {},
		},
		field = "source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/chaos_poxwalker_bomber_foley",
		owner = {
			source_id = 105,
		},
		context = {
			wwise_world = {},
		},
		field = "source_id",
	},
}

local dialogue_track_hook = find_hook(
	"audio_source_cleanup",
	"scripts/extension_systems/dialogue/dialogue_extension",
	"extensions_ready"
)

check(
	dialogue_track_hook ~= nil and dialogue_track_hook.kind == "normal",
	"dialogue manual-source ownership is captured at creation"
)
dialogue_track_hook.handler(function (owner)
	owner._wwise_source_id = 101
end, audio_specs[1].owner)

for i = 1, #audio_specs do
	live_sources[100 + i] = true
	local spec = audio_specs[i]
	local hook = find_hook("audio_source_cleanup", spec.path, "destroy")
		or find_hook("audio_source_cleanup", spec.path, "stop")

	check(hook ~= nil and hook.kind == "safe", "audio hook " .. i .. " is deferred and post-stock")
	hook.handler(spec.owner, spec.context)
	check(
		rawget(spec.owner, spec.field) == nil
			and audio_log.world_by_source[100 + i]
				== (rawget(spec.owner, "_wwise_world") or spec.context.wwise_world),
		"audio hook " .. i .. " releases its own field in its own Wwise world"
	)
end

check(
	audio_log.destroys == 5
		and (actions.audio_source_cleanup or 0) == 5
		and (hits.audio_source_cleanup or 0) == 5,
	"five source-confirmed manual-source leaks are repaired once"
)

local first_audio_hook = find_hook(
	"audio_source_cleanup",
	"scripts/extension_systems/dialogue/dialogue_extension",
	"destroy"
)
local no_source_hits = hits.audio_source_cleanup
first_audio_hook.handler({
	_wwise_world = {},
})
check(
	hits.audio_source_cleanup == no_source_hits,
	"audio teardown with no owned source produces no false telemetry"
)

local untracked_dialogue_owner = {
	_wwise_world = {},
	_wwise_source_id = 190,
}
live_sources[190] = true
dialogue_track_hook.handler(function (_) end, untracked_dialogue_owner)
first_audio_hook.handler(untracked_dialogue_owner)
check(
	untracked_dialogue_owner._wwise_source_id == 190
		and live_sources[190] == true
		and audio_log.destroys == 5
		and hits.audio_source_cleanup == no_source_hits,
	"untracked dialogue auto source remains engine-owned and untouched"
)

local generic_audio_hook = find_hook(
	"audio_source_cleanup",
	"scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects",
	"destroy"
)

local absent_owner = {
	_wwise_world = {},
	_source_id = 199,
}
generic_audio_hook.handler(absent_owner)
check(
	absent_owner._source_id == nil
		and audio_log.destroys == 5
		and hits.audio_source_cleanup == no_source_hits + 1,
	"already-absent source is cleared idempotently without destruction"
)

local query_failure_owner = {
	_wwise_world = {},
	_source_id = 177,
}
query_fail_for[177] = true
generic_audio_hook.handler(query_failure_owner)
generic_audio_hook.handler(query_failure_owner)
check(
	query_failure_owner._source_id == 177,
	"Wwise lookup failure keeps the handle instead of claiming cleanup"
)

local warning_count_after_query = #warnings
check(
	warning_count_after_query == 1,
	"repeated Wwise lookup failure emits one rate-limited warning"
)

local destroy_failure_owner = {
	_wwise_world = {},
	_source_id = 178,
}
live_sources[178] = true
destroy_fail_for[178] = true
generic_audio_hook.handler(destroy_failure_owner)
check(
	destroy_failure_owner._source_id == 178
		and #warnings == warning_count_after_query + 1,
	"Wwise destruction failure is contained, retained, and reported"
)

local particle_destroy_calls = 0
local particle_stop_calls = 0
local particle_query_fail_for = {}
local particle_destroy_fail_for = {}
local live_particles = {
	[401] = true,
}

World = {
	are_particles_playing = function (_, effect_id)
		if particle_query_fail_for[effect_id] then
			error("particle query failure")
		end

		return live_particles[effect_id] == true
	end,
	stop_spawning_particles = function (_, _)
		particle_stop_calls = particle_stop_calls + 1
	end,
	destroy_particles = function (_, effect_id)
		if particle_destroy_fail_for[effect_id] then
			error("particle destroy failure")
		end

		particle_destroy_calls = particle_destroy_calls + 1
		live_particles[effect_id] = false
	end,
}

local particle_hook = find_hook(
	"player_fx_lifecycle",
	"scripts/extension_systems/fx/player_unit_fx_extension",
	"_create_particles_wrapper"
)
local player_destroy_hook = find_hook(
	"player_fx_lifecycle",
	"scripts/extension_systems/fx/player_unit_fx_extension",
	"destroy"
)

check(
	particle_hook and particle_hook.kind == "normal"
		and player_destroy_hook and player_destroy_hook.kind == "normal",
	"player-FX world substitution and pre-destroy cleanup use normal hooks"
)

local extension_world = {}
local received_world
local particle_result = particle_hook.handler(
	function (_, world)
		received_world = world

		return "particle-result"
	end,
	{
		_world = extension_world,
	},
	nil
)

check(
	particle_result == "particle-result" and received_world == extension_world,
	"nil screen-space particle world is replaced with the extension world"
)

live_sources[201] = true
live_sources[202] = false
local moving_sfx = {
	size = 2,
	buffer = {
		{
			playing_id = 301,
			source_id = 201,
			wwise_stop_event = "stop_moving_fx",
		},
		{
			source_id = 202,
		},
	},
}
local moving_vfx = {
	size = 2,
	buffer = {
		{
			effect_id = 401,
		},
		{
			effect_id = 402,
		},
	},
}
local fx_extension = {
	_wwise_world = {},
	_world = {},
	_moving_sfx = moving_sfx,
	_moving_vfx = moving_vfx,
}
local original_saw_drained = false
local stops_before = audio_log.stops
local resource_stops_before = audio_log.resource_stops
local destroys_before = audio_log.destroys

local destroy_result = player_destroy_hook.handler(
	function (owner)
		original_saw_drained = owner._moving_sfx.size == 0
			and owner._moving_vfx.size == 0

		return "destroy-result"
	end,
	fx_extension
)

check(
	destroy_result == "destroy-result" and original_saw_drained,
	"moving resources are drained before stock PlayerUnitFxExtension.destroy"
)
check(
	audio_log.stops == stops_before + 1
		and audio_log.resource_stops == resource_stops_before + 1
		and audio_log.destroys == destroys_before + 1
		and moving_sfx.buffer[1].playing_id == nil
		and moving_sfx.buffer[1].source_id == nil
		and moving_sfx.buffer[2].source_id == nil,
	"moving sound stop, tail event, live source, and stale source are handled"
)
check(
	particle_stop_calls == 1
		and particle_destroy_calls == 1
		and moving_vfx.buffer[1].effect_id == nil
		and moving_vfx.buffer[2].effect_id == nil,
	"moving particles are stopped/destroyed only while live and stale IDs clear"
)

local operations_after_first_destroy = audio_log.stops
	+ audio_log.resource_stops
	+ audio_log.destroys
	+ particle_stop_calls
	+ particle_destroy_calls
player_destroy_hook.handler(function () end, fx_extension)
local operations_after_second_destroy = audio_log.stops
	+ audio_log.resource_stops
	+ audio_log.destroys
	+ particle_stop_calls
	+ particle_destroy_calls

check(
	operations_after_second_destroy == operations_after_first_destroy,
	"repeated player-FX destruction is idempotent"
)

live_sources[211] = true
live_sources[212] = true
live_particles[411] = true
live_particles[412] = true
query_fail_for[211] = true
destroy_fail_for[212] = true
stop_fail_for[313] = true
particle_query_fail_for[411] = true
particle_destroy_fail_for[412] = true

local retry_moving_sfx = {
	size = 3,
	buffer = {
		{
			playing_id = 311,
			source_id = 211,
		},
		{
			source_id = 212,
		},
		{
			playing_id = 313,
		},
	},
}
local retry_moving_vfx = {
	size = 2,
	buffer = {
		{
			effect_id = 411,
		},
		{
			effect_id = 412,
		},
	},
}
local retry_fx_extension = {
	_wwise_world = {},
	_world = {},
	_moving_sfx = retry_moving_sfx,
	_moving_vfx = retry_moving_vfx,
}
local retry_original_calls = 0

local first_retry_result = player_destroy_hook.handler(
	function ()
		retry_original_calls = retry_original_calls + 1

		return "first-retry-result"
	end,
	retry_fx_extension
)

check(
	first_retry_result == "first-retry-result" and retry_original_calls == 1,
	"native cleanup failures remain fail-open to stock player-FX teardown"
)
check(
	retry_moving_sfx.size == 3
		and retry_moving_sfx.buffer[1].playing_id == nil
		and retry_moving_sfx.buffer[1].source_id == 211
		and retry_moving_sfx.buffer[2].source_id == 212
		and retry_moving_sfx.buffer[3].playing_id == 313,
	"failed sound queries, destruction, and stops retain active retry state"
)
check(
	retry_moving_vfx.size == 2
		and retry_moving_vfx.buffer[1].effect_id == 411
		and retry_moving_vfx.buffer[2].effect_id == 412,
	"failed particle queries and destruction retain active retry state"
)

query_fail_for[211] = nil
destroy_fail_for[212] = nil
stop_fail_for[313] = nil
particle_query_fail_for[411] = nil
particle_destroy_fail_for[412] = nil

local second_retry_result = player_destroy_hook.handler(
	function ()
		retry_original_calls = retry_original_calls + 1

		return "second-retry-result"
	end,
	retry_fx_extension
)

check(
	second_retry_result == "second-retry-result"
		and retry_original_calls == 2
		and retry_moving_sfx.size == 0
		and retry_moving_vfx.size == 0,
	"retained player-FX buffers drain after native APIs recover"
)
check(
	retry_moving_sfx.buffer[1].source_id == nil
		and retry_moving_sfx.buffer[2].source_id == nil
		and retry_moving_sfx.buffer[3].playing_id == nil
		and retry_moving_vfx.buffer[1].effect_id == nil
		and retry_moving_vfx.buffer[2].effect_id == nil,
	"successful retry clears every retained native handle"
)
check(next(availability) == nil, "all exact cleanup hook surfaces remain available")

io.write(
	string.format(
		"\n%s: %d checks, %d failures\n",
		failures == 0 and "OK" or "FAILED",
		checks,
		failures
	)
)

if failures > 0 then
	os.exit(1)
end
