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

local setting_enabled = true
local mod_enabled = true
local actions = 0

local runtime = {
	defer_file = function (_, _, module_path, handler)
		local ok, loaded_value = pcall(require, module_path)

		if not ok then
			return false
		end

		handler(loaded_value)

		return true
	end,
	is_active = function ()
		return mod_enabled and setting_enabled
	end,
	run = function (_, _, callback, ...)
		local ok, a, b, c, d = pcall(callback, ...)

		return ok, a, b, c, d
	end,
	record_hit = function ()
	end,
	record_action = function (_, _, count)
		actions = actions + (count or 1)
	end,
	set_available = function ()
	end,
	mod_is_enabled = function ()
		return mod_enabled
	end,
	get = function ()
		return setting_enabled
	end,
}

function get_mod(name)
	check(name == "TertiumFixes", "module requests the expected mod")

	return {
		_tf_runtime = runtime,
	}
end

local original_calls = {}
local original_functions = {}
local templates = {}
local template_names = {
	"companion_servo_skull_moving_effect",
	"companion_servo_skull_aim_on_ground_effect",
	"companion_servo_skull_flamer",
	"companion_servo_skull_empowered_effect",
	"companion_servo_skull_charged_shooting",
	"arc_chain_to_position",
}

for i = 1, #template_names do
	local name = template_names[i]

	original_calls[name] = {
		start = 0,
		update = 0,
		stop = 0,
	}
	templates[name] = {
		name = name,
		resources = {},
		start = function ()
			original_calls[name].start = original_calls[name].start + 1
		end,
		update = function ()
			original_calls[name].update = original_calls[name].update + 1
		end,
		stop = function ()
			original_calls[name].stop = original_calls[name].stop + 1
		end,
	}
	original_functions[name] = {
		start = templates[name].start,
		update = templates[name].update,
		stop = templates[name].stop,
	}
end

package.preload["scripts/settings/fx/effect_templates"] = function ()
	return templates
end

local particle_stops = 0
local particle_destroys = 0
local audio_stops = 0
local audio_resource_stops = 0
local source_destroys = 0

World = {
	stop_spawning_particles = function (_, _)
		particle_stops = particle_stops + 1
	end,
	destroy_particles = function (_, _)
		particle_destroys = particle_destroys + 1
	end,
}

WwiseWorld = {
	stop_event = function (_, _)
		audio_stops = audio_stops + 1
	end,
	trigger_resource_event = function (_, _, _)
		audio_resource_stops = audio_resource_stops + 1
	end,
	destroy_manual_source = function (_, _)
		source_destroys = source_destroys + 1
	end,
}

local living_arc_unit = {}
local dead_flamer_unit = {}
local dead_suppressed_start_unit = {}

ALIVE = {
	[living_arc_unit] = true,
	[dead_flamer_unit] = false,
	[dead_suppressed_start_unit] = false,
}
HEALTH_ALIVE = {
	[living_arc_unit] = true,
}

local module = dofile(
	"scripts/mods/TertiumFixes/modules/effect_template_safety.lua"
)

module:install()

local arc = templates.arc_chain_to_position
local arc_data = {
	unit = living_arc_unit,
	target_pos = {},
	link_particle_id = 101,
	effect_lifetime_end_t = 10,
}
local arc_context = {
	world = {},
	is_server = false,
}

local arc_result = arc.update(arc_data, arc_context, 0.016, 10)

check(arc_result == true, "client arc expiry returns terminal update signal")
check(
	original_calls.arc_chain_to_position.update == 0,
	"expired arc never enters the unsafe original update"
)
check(
	arc_data.link_particle_id == nil and particle_stops == 1,
	"expired arc releases and clears its particle exactly once"
)

arc.update(arc_data, arc_context, 0.016, 11)
check(
	particle_stops == 1
		and original_calls.arc_chain_to_position.update == 0,
	"expired arc remains inert when the client handler ignores the signal"
)

setting_enabled = false
module:on_setting_changed("effect_template_safety_enabled")
arc.stop(arc_data, arc_context)

check(
	particle_stops == 1
		and original_calls.arc_chain_to_position.stop == 0,
	"authoritative stop after disable cannot double-stop a cleaned arc"
)

setting_enabled = true
module:on_setting_changed("effect_template_safety_enabled")

local flamer = templates.companion_servo_skull_flamer
local flamer_data = {
	unit = dead_flamer_unit,
	attachment_unit = {},
	attachment_node = "node",
	game_session = {},
	game_object_id = 1,
	stream_effect_id = 201,
	source_id = 202,
	playing_id = 203,
	stop_event_name = "stop_servo_flamer",
}
local particle_only_context = {
	world = {},
}

flamer.update(flamer_data, particle_only_context, 0.016, 1)

check(
	flamer_data.stream_effect_id == nil
		and flamer_data.playing_id == 203
		and particle_stops == 2,
	"partial cleanup clears only the successfully released particle"
)
check(
	original_calls.companion_servo_skull_flamer.update == 0,
	"partial cleanup never enters the unsafe original update"
)

flamer.stop(flamer_data, particle_only_context)
check(
	original_calls.companion_servo_skull_flamer.stop == 0
		and flamer_data.playing_id == 203,
	"failed cleanup retry never falls through to vanilla stop"
)

local complete_context = {
	world = {},
	wwise_world = {},
}

flamer.stop(flamer_data, complete_context)
check(
	original_calls.companion_servo_skull_flamer.stop == 0
		and flamer_data.playing_id == nil
		and flamer_data.source_id == nil
		and flamer_data.stop_event_name == nil,
	"later stop retry completes audio cleanup without vanilla double handling"
)
check(
	audio_resource_stops == 1 and source_destroys == 1,
	"flamer loop and owned manual source are each released once"
)

local suppressed_data = {
	unit = dead_suppressed_start_unit,
}

flamer.start(suppressed_data, complete_context)
check(
	original_calls.companion_servo_skull_flamer.start == 0,
	"invalid flamer start is suppressed before allocating resources"
)

flamer.stop(suppressed_data, complete_context)
check(
	original_calls.companion_servo_skull_flamer.stop == 0,
	"stop after a suppressed start is a harmless no-op"
)

check(
	audio_stops == 0 and particle_destroys == 0,
	"behavior cases do not release unowned audio or particle handles"
)
check(actions >= 4, "successful lifecycle interventions are counted")

local third_party_start = function ()
end

check(#module._records == 17, "install owns exactly seventeen registry wrappers")

templates.companion_servo_skull_moving_effect.start = third_party_start
module:on_unload()

local restored = 0

for i = 1, #template_names do
	local name = template_names[i]

	for _, field in ipairs({ "start", "update", "stop" }) do
		if templates[name][field] == original_functions[name][field] then
			restored = restored + 1
		end
	end
end

check(
	templates.companion_servo_skull_moving_effect.start == third_party_start,
	"unload preserves a later third-party replacement"
)
check(
	restored == 17,
	"unload restores sixteen owned wrappers and leaves the unpatched field original"
)
check(#module._records == 0, "unload releases every wrapper record and old closure root")

templates.companion_servo_skull_moving_effect.start =
	original_functions.companion_servo_skull_moving_effect.start

local reloaded_module = dofile(
	"scripts/mods/TertiumFixes/modules/effect_template_safety.lua"
)

reloaded_module:install()
reloaded_module:on_unload()

local clean_reload = true

for i = 1, #template_names do
	local name = template_names[i]

	for _, field in ipairs({ "start", "update", "stop" }) do
		clean_reload = clean_reload
			and templates[name][field] == original_functions[name][field]
	end
end


check(clean_reload, "same-session reload leaves no stacked registry wrappers")

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
