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

local deferred, unavailable = {}, {}
local enabled = true
local runtime = {}
function runtime:defer_file(id, _, callback) deferred[id] = callback; return true end
function runtime:is_active(id) return enabled and not unavailable[id] end
function runtime:set_available(id, value, reason) if not value then unavailable[id] = reason end end
function runtime:get() return true end
function runtime:mod_is_enabled() return enabled end
function runtime:record_hit() end
function runtime:record_action() end
function runtime:run(_, callback, ...) return pcall(callback, ...) end
function get_mod() return { _tf_runtime = runtime } end

local gas = dofile("scripts/mods/TertiumFixes/modules/gas_outline_recovery.lua")
local effects = dofile("scripts/mods/TertiumFixes/modules/effect_template_safety.lua")
gas:install()
effects:install()
gas:on_enabled()
effects:on_enabled()
gas:on_setting_changed(gas.setting_id)
effects:on_setting_changed(effects.setting_id)
check(next(unavailable) == nil, "enabling before the game loads its templates does not disable the modules")

local gas_names = { "in_toxic_gas", "in_cultist_grenadier_gas", "in_twin_toxic_gas", "in_buildup_twin_toxic_gas" }
local gas_templates, stock_stops = {}, 0
local stop_functions = {}
for _, name in ipairs(gas_names) do
	local stop = function () stock_stops = stock_stops + 1; return "stock result" end
	stop_functions[name] = stop
	gas_templates[name] = {
		class_name = "interval_buff", start_func = function () end, stop_func = stop,
		player_effects = {
			looping_wwise_start_event = "wwise/events/player/play_player_gas_enter",
			looping_wwise_stop_event = "wwise/events/player/play_player_gas_exit",
		},
	}
end
deferred.gas_outline_recovery(gas_templates)
check(#gas._records == 4 and not unavailable[gas.id], "deferred gas templates are patched after an earlier enable")

local dead_unit, replacement_unit = {}, {}
local current_unit = dead_unit
local visibility_calls = 0
HEALTH_ALIVE = { [replacement_unit] = true }
Managers = {
	player = { local_player = function () return { player_unit = current_unit } end },
	state = { extension = { system = function ()
		return { set_global_visibility = function (_, visible)
			assert(visible == true)
			visibility_calls = visibility_calls + 1
		end }
	end } },
}
local context = { unit = dead_unit, is_local_unit = true, is_player = true }
check(gas_templates.in_toxic_gas.stop_func({}, context) == "stock result" and visibility_calls == 1,
	"gas recovery preserves the stock stop and restores outlines for the dead current player")
current_unit = replacement_unit
gas_templates.in_toxic_gas.stop_func({}, context)
check(visibility_calls == 1, "a late gas stop from the old body cannot reveal the replacement player's outlines")
current_unit = dead_unit
DEDICATED_SERVER = true
gas_templates.in_toxic_gas.stop_func({}, context)
check(visibility_calls == 1, "dedicated server gas cleanup does not touch client outline visibility")
DEDICATED_SERVER = false
context.is_local_unit = false
gas_templates.in_toxic_gas.stop_func({}, context)
check(visibility_calls == 1, "another player's gas stop leaves local outline visibility alone")
context.is_local_unit = true
HEALTH_ALIVE[dead_unit] = true
gas_templates.in_toxic_gas.stop_func({}, context)
check(visibility_calls == 1, "living gas stops remain entirely under the game callback")

local other_mod_stop = function () end
gas_templates.in_twin_toxic_gas.stop_func = other_mod_stop
gas:on_disabled()
check(gas_templates.in_toxic_gas.stop_func == stop_functions.in_toxic_gas
	and gas_templates.in_twin_toxic_gas.stop_func == other_mod_stop,
	"disabling restores owned gas callbacks without replacing a later mod's callback")

local effect_names = {
	"companion_servo_skull_moving_effect", "companion_servo_skull_aim_on_ground_effect",
	"companion_servo_skull_flamer", "companion_servo_skull_empowered_effect",
	"companion_servo_skull_charged_shooting", "arc_chain_to_position",
}
local effect_templates = {}
for _, name in ipairs(effect_names) do
	effect_templates[name] = { name = name, resources = {}, start = function () end, update = function () end, stop = function () end }
end
deferred.effect_template_safety(effect_templates)
check(#effects._records == 18 and not unavailable[effects.id], "deferred effect templates are patched after an earlier enable")

local stops = {}
local owned_audio_world, next_audio_world = {}, {}
WwiseWorld = { stop_event = function (world, id) stops[#stops + 1] = { world = world, id = id } end }
ALIVE = {}
local data = { unit = {}, wwise_world = owned_audio_world, source_id = 7, playing_id = 8 }
effect_templates.companion_servo_skull_moving_effect.update(data, { wwise_world = next_audio_world }, 0.016, 1)
check(#stops == 1 and stops[1].world == owned_audio_world,
	"moving servo sound cleanup uses the world that owns its playing ID")
enabled = false
effects:on_disabled()
effect_templates.companion_servo_skull_moving_effect.stop(data, { wwise_world = next_audio_world })
check(#stops == 1, "late stops after disable cannot stop the same servo audio twice")
check(effects:runtime_status() == "inactive", "disabled effect guards report inactive even while late-stop wrappers remain")
effects:on_unload()
check(#effects._records == 0, "unload releases the effect callback records")

print(string.format("\nEffect lifecycle checks: %d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
