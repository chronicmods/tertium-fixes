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

local function approximately(actual, expected)
	return type(actual) == "number" and math.abs(actual - expected) < 0.001
end

local function table_size(value)
	local count = 0

	for _ in pairs(value) do
		count = count + 1
	end

	return count
end

local default_settings = {
	gc_capacity_fallback_mb = 1024,
	gc_cleaning_permitted = true,
	gc_convenient_cleanup_enabled = true,
	gc_enabled = true,
	gc_hud_enabled = true,
	gc_hud_x_percent = 5,
	gc_hud_y_percent = 65,
	gc_notifications_enabled = false,
	gc_periodic_cleanup_enabled = false,
	gc_shutdown_diagnostic_enabled = false,
}

local settings = {}
local argv_values = {}
local collector_calls = {}
local heap_kb = 512 * 1024
local collect_after_kb = nil
local collector_pause = 200
local collector_stepmul = 300
local collector_failures = {}
local step_result = false
local performance_elapsed_ms = 0

local runtime = {
	actions = 0,
	hits = 0,
}

function runtime:get(setting_id)
	return settings[setting_id]
end

function runtime:is_active(module_id)
	return module_id == "gc_pressure" and settings.gc_enabled == true
end

function runtime:log()
end

function runtime:mod_is_enabled()
	return true
end

function runtime:record_action(_, count)
	self.actions = self.actions + (count or 1)
end

function runtime:record_hit()
	self.hits = self.hits + 1
end

function runtime:run(_, callback, ...)
	return pcall(callback, ...)
end

function runtime:set_available()
end

local function rendered(message, ...)
	if select("#", ...) == 0 then
		return tostring(message)
	end

	return string.format(message, ...)
end

local mod = {
	_tf_runtime = runtime,
	echoes = {},
	notifications = {},
	stored = {},
	warnings = {},
}

local dmf = {
	save_calls = 0,
}

function dmf.save_unsaved_settings_to_file()
	dmf.save_calls = dmf.save_calls + 1
end

function mod:echo(message, ...)
	self.echoes[#self.echoes + 1] = rendered(message, ...)
end

function mod:warning(message, ...)
	self.warnings[#self.warnings + 1] = rendered(message, ...)
end

function mod:notify(message)
	self.notifications[#self.notifications + 1] = tostring(message)
end

function mod:get(key)
	return self.stored[key]
end

function mod:set(key, value)
	self.stored[key] = value
end

local function controller()
	local value = {
		enabled = false,
	}

	function value:is_enabled()
		return self.enabled
	end

	return value
end

local primary_controller_id = string.char(83, 77, 79, 71)
local secondary_controller_id = string.char(77, 101, 109, 76, 101, 97, 107, 70, 105, 120)
local legacy_controller_id = string.char(70, 112, 115, 68, 111, 99, 116, 111, 114)

local external_mods = {
	[primary_controller_id] = controller(),
	[secondary_controller_id] = controller(),
	[legacy_controller_id] = controller(),
}

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	elseif name == "DMF" then
		return dmf
	end

	return external_mods[name]
end

local unpack_values = table.unpack or unpack

Application = {}

function Application.argv()
	return unpack_values(argv_values)
end

function Application.query_performance_counter()
	return "gc-pressure-test-counter"
end

function Application.time_since_query()
	return performance_elapsed_ms
end

function collectgarbage(operation, argument)
	collector_calls[#collector_calls + 1] = {
		argument = argument,
		operation = operation,
	}

	if (collector_failures[operation] or 0) > 0 then
		collector_failures[operation] = collector_failures[operation] - 1

		error("forced " .. tostring(operation) .. " failure")
	end

	if operation == "count" then
		return heap_kb
	elseif operation == "collect" then
		if collect_after_kb ~= nil then
			heap_kb = collect_after_kb
		end

		return true
	elseif operation == "step" then
		return step_result
	elseif operation == "setpause" then
		local previous = collector_pause

		collector_pause = argument

		return previous
	elseif operation == "setstepmul" then
		local previous = collector_stepmul

		collector_stepmul = argument

		return previous
	end

	error("unexpected collectgarbage operation: " .. tostring(operation))
end

local function clear_collector_calls()
	collector_calls = {}
end

local function fail_next_collector_call(operation, count)
	collector_failures[operation] = count or 1
end

local function collector_call_count(operation)
	local count = 0

	for i = 1, #collector_calls do
		if collector_calls[i].operation == operation then
			count = count + 1
		end
	end

	return count
end

local function first_collector_call(operation)
	for i = 1, #collector_calls do
		if collector_calls[i].operation == operation then
			return i
		end
	end

	return nil
end

local function has_only_collector_operation(operation)
	if #collector_calls == 0 then
		return false
	end

	for i = 1, #collector_calls do
		if collector_calls[i].operation ~= operation then
			return false
		end
	end

	return true
end

local function reset_world()
	settings = {}

	for key, value in pairs(default_settings) do
		settings[key] = value
	end

	argv_values = {}
	heap_kb = 512 * 1024
	collect_after_kb = nil
	collector_pause = 200
	collector_stepmul = 300
	collector_failures = {}
	step_result = false
	performance_elapsed_ms = 0
	clear_collector_calls()
	runtime.actions = 0
	runtime.hits = 0
	mod.echoes = {}
	mod.notifications = {}
	mod.stored = {}
	mod.warnings = {}
	dmf.save_calls = 0

	for _, candidate in pairs(external_mods) do
		candidate.enabled = false
	end

	Managers = nil
end

local function load_module()
	local value = dofile("scripts/mods/TertiumFixes/modules/gc_pressure.lua")

	value:install()

	return value
end

-- Heap capacity accepts both documented argv shapes and otherwise uses the
-- bounded fallback setting.
reset_world()
argv_values = {
	"--lua-heap-mb-size=2048",
}
local module = load_module()

check(
	module._heap_capacity_mb == 2048
		and module._capacity_source == "command line"
		and module:meter_snapshot().capacity_mb == 2048,
	"inline Lua heap capacity argv is detected"
)

reset_world()
argv_values = {
	"--unrelated",
	"--lua-heap-mb-size",
	"3072",
}
module = load_module()

check(
	module._heap_capacity_mb == 3072 and module._capacity_source == "command line",
	"split Lua heap capacity argv is detected"
)

reset_world()
settings.gc_capacity_fallback_mb = 1536
argv_values = {
	"--lua-heap-mb-size=70000",
}
module = load_module()

check(
	module._heap_capacity_mb == 1536
		and module._capacity_source == "fallback setting"
		and module:meter_snapshot().capacity_mb == 1536,
	"invalid argv capacity falls back to the configured capacity"
)

-- Every supported external controller owns all collector operations, including
-- monitoring and manual commands.
local conflict_cases = {
	{
		id = primary_controller_id,
		key = "cleanup_owner_primary",
		label = "another Lua cleanup controller",
	},
	{
		id = secondary_controller_id,
		key = "cleanup_owner_secondary",
		label = "another Lua cleanup controller",
	},
	{
		id = legacy_controller_id,
		key = "cleanup_owner_legacy",
		label = "another Lua cleanup controller",
	},
}

for i = 1, #conflict_cases do
	local case = conflict_cases[i]

	reset_world()
	external_mods[case.id].enabled = true
	module = load_module()
	clear_collector_calls()
	module:update(2)
	module:manual_step()
	module:manual_collect()
	module:_sample_heap()

	check(
		module._conflict_id == case.key
			and module._conflict == case.label
			and module._active_controllers[case.key] == true,
		("compatibility fixture %d is detected under its private cleanup-owner key"):format(i)
	)
	check(
		#collector_calls == 0,
		("compatibility fixture %d enforces strict zero collector calls"):format(i)
	)
end

reset_world()
external_mods[primary_controller_id].enabled = true
external_mods[legacy_controller_id].enabled = true
module = load_module()

check(
	module._conflict_id == "cleanup_owner_primary"
		and module._active_controllers.cleanup_owner_primary == true
		and module._active_controllers.cleanup_owner_legacy == true
		and module:runtime_status() == "cleanup-standby"
		and #mod.warnings == 1,
	"cleanup ownership priority is stable and overlap warning is emitted once"
)
check(
	string.find(mod.warnings[1], "Multiple Lua cleanup controllers are active", 1, true) ~= nil
		and string.find(mod.warnings[1], "Enable only one automatic cleanup controller", 1, true) ~= nil,
	"overlap warning reports only generic cleanup-controller guidance"
)

-- A handback discards cached pressure and requires five fresh high samples
-- before collector mutations can resume.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 820 * 1024
external_mods[primary_controller_id].enabled = true
module = load_module()
module._last_heap_mb = 999
module._pressure = true
module._pressure_seconds = 90
module._scheduled.stale = {
	due = 0,
	source = "transition",
}
external_mods[primary_controller_id].enabled = false
clear_collector_calls()
module:update(1)

check(
	collector_call_count("count") == 1
		and collector_call_count("step") == 0
		and collector_call_count("collect") == 0
		and collector_call_count("setpause") == 0
		and module._pressure == false
		and next(module._scheduled) == nil,
	"external-controller handback starts with a fresh non-mutating sample"
)

for _ = 1, 4 do
	module:update(1)
end

check(
	module._pressure == true
		and collector_call_count("count") == 5
		and collector_call_count("step") == 16
		and first_collector_call("count") < first_collector_call("step"),
	"fresh sustained pressure can resume bounded steps after handback"
)

-- Exactly 80% requires five seconds of dwell, uses bounded 32 KB slices, then
-- escalates tuning and restores the collector's exact prior values below 80%.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 800 * 1024
module = load_module()

for sample = 1, 4 do
	module:_sample_heap()
	check(module._pressure == false, "80% pressure dwell sample " .. sample .. " does not engage early")
end

module:_sample_heap()
check(module._pressure == true, "80% pressure engages after five one-second samples")

clear_collector_calls()
module:update(0.05)

local every_step_is_bounded = true

for i = 1, #collector_calls do
	if collector_calls[i].operation == "step" and collector_calls[i].argument ~= 32 then
		every_step_is_bounded = false
	end
end

check(
	collector_call_count("setpause") == 1
		and collector_call_count("setstepmul") == 1
		and collector_pause == 80
		and collector_stepmul == 500,
	"first pressure level acquires 80/500 collector tuning"
)
check(
	collector_call_count("step") == 16 and every_step_is_bounded,
	"incremental work is capped at sixteen 32 KB steps per update"
)

module._pressure_no_drop_seconds = 30
clear_collector_calls()
module:update(0.05)

check(
	module._tuning_level == 2
		and collector_pause == 70
		and collector_stepmul == 650
		and collector_call_count("step") == 16,
	"unchanged pressure escalates to 70/650 tuning after thirty seconds"
)

heap_kb = 790 * 1024
clear_collector_calls()
module:_sample_heap()

check(
	module._pressure == false
		and module._tuning_owned == false
		and collector_pause == 200
		and collector_stepmul == 300
		and collector_call_count("setpause") == 1
		and collector_call_count("setstepmul") == 1,
	"dropping below 80% restores exact prior collector tuning"
)

performance_elapsed_ms = 1
clear_collector_calls()
module:_run_incremental_budget()
check(
	collector_call_count("step") == 1 and collector_calls[1].argument == 32,
	"the one-millisecond time budget stops an incremental slice after its first step"
)

-- The 85% band forces the meter without requiring the user HUD setting.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
settings.gc_hud_enabled = false
settings.gc_hud_x_percent = 12
settings.gc_hud_y_percent = 77
heap_kb = 850 * 1024
module = load_module()
module:_sample_heap()
local meter = module:meter_snapshot()

check(
	module._warned_85 == true
		and module._force_meter == true
		and meter.visible == true
		and meter.severity == "warning",
	"85% pressure forces a warning meter"
)
check(
	approximately(meter.percent, 85)
		and meter.heap_mb == 850
		and meter.capacity_mb == 1000
		and meter.x == 12
		and meter.y == 77
		and string.find(meter.label, "85.0%", 1, true) ~= nil,
	"heap meter snapshot reports configured position and capacity percentage"
)

-- The 90% and 95% emergency collections fire once per pressure cycle and
-- re-arm only after returning below 80%.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 900 * 1024
collect_after_kb = 880 * 1024
module = load_module()
module:_sample_heap()

check(
	collector_call_count("collect") == 1
		and module._cleaned_90 == true
		and module._cleaned_95 == false,
	"90% threshold performs the first emergency collection"
)

heap_kb = 950 * 1024
collect_after_kb = 860 * 1024
module:_sample_heap()

check(
	collector_call_count("collect") == 2
		and module._cleaned_90 == true
		and module._cleaned_95 == true,
	"95% threshold performs the second emergency collection"
)

heap_kb = 980 * 1024
collect_after_kb = 850 * 1024
module:_sample_heap()
check(collector_call_count("collect") == 2, "emergency thresholds collect only once per pressure cycle")

heap_kb = 700 * 1024
collect_after_kb = nil
module:_sample_heap()
heap_kb = 900 * 1024
collect_after_kb = 850 * 1024
module:_sample_heap()

check(
	collector_call_count("collect") == 3 and module._cleaned_90 == true,
	"returning below 80% re-arms emergency cleanup"
)

-- Rapid 30-second growth has its own one-shot cleanup and accounting path.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 350 * 1024
module = load_module()
module:_sample_heap()
module._clock = 30
heap_kb = 500 * 1024
collect_after_kb = 450 * 1024
clear_collector_calls()
module:_sample_heap()

check(
	collector_call_count("collect") == 1
		and module._metrics.rapid_growth_collections == 1
		and module._metrics.full_collections == 1,
	"fifteen-point heap growth in thirty seconds triggers one cleanup"
)

-- Manual full cleaning reports reclaimed memory and applies a three-second
-- cooldown only after a successful collection.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 500 * 1024
collect_after_kb = 400 * 1024
module = load_module()
clear_collector_calls()
local cleaned, result = module:manual_collect()

check(
	cleaned == true
		and approximately(result.before_mb, 500)
		and approximately(result.after_mb, 400)
		and approximately(result.reclaimed_mb, 100)
		and collector_calls[1].operation == "count"
		and collector_calls[2].operation == "collect"
		and collector_calls[3].operation == "count",
	"manual cleanup measures before, collect, and after in order"
)

local calls_after_first_manual = #collector_calls
check(
	module:manual_collect() == false and #collector_calls == calls_after_first_manual,
	"manual cleanup cooldown blocks collector calls"
)

module._clock = 3
heap_kb = 450 * 1024
collect_after_kb = 350 * 1024
check(
	module:manual_collect() == true
		and collector_call_count("collect") == 2
		and module._metrics.manual_collections == 2,
	"manual cleanup is available again after three seconds"
)

-- Switching to monitoring-only restores owned tuning once, drops queued work,
-- and subsequently permits count only.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
module = load_module()
module:_set_tuning(1)
module._scheduled.pending = {
	due = 0,
	source = "transition",
}
settings.gc_cleaning_permitted = false
clear_collector_calls()
module:on_setting_changed("gc_cleaning_permitted")

check(
	collector_pause == 200
		and collector_stepmul == 300
		and collector_call_count("setpause") == 1
		and collector_call_count("setstepmul") == 1
		and next(module._scheduled) == nil,
	"monitor-only switch restores tuning and discards queued cleanups"
)

heap_kb = 980 * 1024
clear_collector_calls()
module:update(1)
meter = module:meter_snapshot()

check(
	has_only_collector_operation("count")
		and module:runtime_status() == "monitor-only"
		and approximately(meter.percent, 98)
		and meter.severity == "emergency",
	"monitor-only mode samples and reports emergency pressure without mutation"
)

clear_collector_calls()
module:manual_step()
module:manual_collect()
check(#collector_calls == 0, "manual commands cannot bypass monitor-only mode")

-- Monitoring-only mode keeps the forced warning meter at 85% even when the
-- normal HUD preference is off. Idle updates must not replace the scheduling
-- table or rebuild the unchanged heap label every frame.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
settings.gc_cleaning_permitted = false
settings.gc_hud_enabled = false
heap_kb = 850 * 1024
module = load_module()
module:update(1)
meter = module:meter_snapshot()

check(
	module._force_meter == true
		and meter.visible == true
		and meter.severity == "warning"
		and approximately(meter.percent, 85),
	"monitor-only high pressure keeps the forced warning meter visible"
)

local scheduled_reference = module._scheduled
local stable_label = meter.label
local original_string_format = string.format
local heap_label_formats = 0

string.format = function (format_string, ...)
	if format_string == "Lua heap %.1f / %.0f MB (%.1f%%)" then
		heap_label_formats = heap_label_formats + 1
	end

	return original_string_format(format_string, ...)
end

local idle_updates_ok, idle_update_error = pcall(function ()
	for _ = 1, 10 do
		module:update(0.05)
	end
end)

string.format = original_string_format

check(idle_updates_ok, "monitor-only idle updates complete: " .. tostring(idle_update_error))
check(
	module._scheduled == scheduled_reference and next(module._scheduled) == nil,
	"monitor-only idle updates retain the empty schedule table"
)
check(
	heap_label_formats == 0 and module:meter_snapshot().label == stable_label,
	"monitor-only idle updates do not reformat an unchanged heap label"
)

-- Turning off convenient cleanup cancels pending work. Execution also checks
-- the live setting so a stale entry cannot run after the option changes.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 500 * 1024
collect_after_kb = 400 * 1024
module = load_module()
module:_queue_collect("gameplay exit", 0, "transition")
settings.gc_convenient_cleanup_enabled = false
module:on_setting_changed("gc_convenient_cleanup_enabled")

check(next(module._scheduled) == nil, "disabling convenient cleanup cancels queued collections")

module._scheduled.stale = {
	due = module._clock,
	source = "transition",
}
clear_collector_calls()
module:update(0.05)

check(
	collector_call_count("collect") == 0 and next(module._scheduled) == nil,
	"a stale queued collection cannot execute while convenient cleanup is disabled"
)

-- The normal HUD preference can be toggled independently of pressure forcing.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
settings.gc_hud_enabled = false
heap_kb = 500 * 1024
module = load_module()
module:_sample_heap()

check(module:meter_snapshot().visible == false, "HUD starts hidden when its setting is disabled")
check(
	module:toggle_hud() == true and module:meter_snapshot().visible == true,
	"HUD toggle shows the heap meter"
)
check(
	module:toggle_hud() == false and module:meter_snapshot().visible == false,
	"HUD toggle hides the heap meter"
)

-- Gameplay entry is deduplicated and both entry and exit cleanups run after the
-- one-second transition delay.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 500 * 1024
collect_after_kb = 400 * 1024
module = load_module()
module:on_game_state_changed("enter", "StateIngame")
module:on_game_state_changed("enter", "StateIngame")

check(table_size(module._scheduled) == 1, "duplicate gameplay entry queues one transition cleanup")
clear_collector_calls()
module:update(0.5)
check(collector_call_count("collect") == 0, "transition cleanup waits for its one-second delay")
module:update(0.5)

check(
	collector_call_count("collect") == 1
		and module._metrics.transition_collections == 1
		and next(module._scheduled) == nil,
	"gameplay entry performs one delayed transition cleanup"
)

heap_kb = 450 * 1024
collect_after_kb = 350 * 1024
module:on_game_state_changed("exit", "StateIngame")
module:update(1)

check(
	collector_call_count("collect") == 2
		and module._metrics.transition_collections == 2
		and module._current_state == nil
		and next(module._scheduled) == nil,
	"gameplay exit performs one delayed transition cleanup"
)

-- Periodic cleaning remains an explicit opt-in and uses the full-collection
-- accounting path when enabled.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
settings.gc_convenient_cleanup_enabled = false
settings.gc_periodic_cleanup_enabled = true
heap_kb = 500 * 1024
collect_after_kb = 400 * 1024
module = load_module()
clear_collector_calls()
module:update(600)

check(
	collector_call_count("collect") == 1 and module._metrics.full_collections == 1,
	"opt-in periodic cleanup runs at ten minutes"
)

-- Lifecycle cleanup restores owned tuning and drops every pressure/ownership
-- cache that could leak into a later enable.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
collector_pause = 210
collector_stepmul = 330
module = load_module()
module:_set_tuning(1)
module._pressure = true
module._current_state = "StateIngame"
module._scheduled.pending = {
	due = 99,
	source = "transition",
}
module._last_heap_mb = 900
module._last_percent = 90
module._growth_samples = {
	{
		percent = 90,
		t = 0,
	},
}
clear_collector_calls()
module:on_disabled()

check(
	collector_pause == 210
		and collector_stepmul == 330
		and module._tuning_owned == false
		and module._tuning_level == 0,
	"disable restores the exact collector tuning owned by the module"
)
check(
	module._current_state == nil
		and module._last_heap_mb == nil
		and module._last_percent == nil
		and module._pressure == false
		and next(module._scheduled) == nil
		and next(module._growth_samples) == nil
		and module._conflict == nil
		and module._conflict_id == nil
		and next(module._active_controllers) == nil,
	"disable clears transition, pressure, sample, and ownership state"
)

-- The module setting itself is a lifecycle boundary: disabling restores exact
-- tuning and clears stale runtime state, while re-enabling starts from the
-- configured HUD preference without collector mutation.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
collector_pause = 215
collector_stepmul = 345
module = load_module()
module:_set_tuning(1)
module._pressure = true
module._force_meter = true
module._warned_85 = true
module._cleaned_90 = true
module._cleaned_95 = true
module._last_heap_mb = 950
module._last_percent = 95
module._hud_user_visible = false
module._current_state = "StateIngame"
module._conflict = "stale controller"
module._conflict_id = "stale"
module._active_controllers.cleanup_owner_primary = "stale"
module._dual_controller_warned = true
module._growth_samples = {
	{
		percent = 95,
		t = 0,
	},
}
module._scheduled.pending = {
	due = 10,
	source = "transition",
}
settings.gc_enabled = false
clear_collector_calls()
module:on_setting_changed("gc_enabled")

check(
	collector_pause == 215
		and collector_stepmul == 345
		and module._tuning_owned == false
		and module._tuning_level == 0
		and collector_call_count("setpause") == 1
		and collector_call_count("setstepmul") == 1,
	"disabling gc_enabled restores the exact collector tuning"
)
check(
	module._pressure == false
		and module._force_meter == false
		and module._warned_85 == false
		and module._cleaned_90 == false
		and module._cleaned_95 == false
		and module._last_heap_mb == nil
		and module._last_percent == nil
		and module._current_state == nil
		and module._conflict == nil
		and module._conflict_id == nil
		and next(module._active_controllers) == nil
		and module._dual_controller_warned == false
		and next(module._growth_samples) == nil
		and next(module._scheduled) == nil,
	"disabling gc_enabled clears stale pressure, samples, and queued work"
)

settings.gc_enabled = true
clear_collector_calls()
module:on_setting_changed("gc_enabled")

check(
	#collector_calls == 0
		and module._pressure == false
		and module._last_heap_mb == nil
		and module._last_percent == nil
		and module._hud_user_visible == true
		and module:meter_snapshot().visible == true,
	"re-enabling gc_enabled starts clean and reapplies the configured HUD preference"
)

-- Enabling shutdown diagnostics during a live session must immediately mark
-- that session unclean and persist it. Heartbeats with an unchanged heap band
-- must not write again, while meaningful band and clean-shutdown transitions do.
reset_world()
argv_values = {
	"--lua-heap-mb-size=1000",
}
heap_kb = 500 * 1024
module = load_module()

check(
	mod.stored.tf_gc_previous_shutdown_clean == nil and dmf.save_calls == 0,
	"disabled shutdown diagnostics do not create or flush a marker"
)

settings.gc_shutdown_diagnostic_enabled = true
module:on_setting_changed("gc_shutdown_diagnostic_enabled")

check(
	mod.stored.tf_gc_previous_shutdown_clean == false
		and mod.stored.tf_gc_last_heap_band == "normal"
		and dmf.save_calls == 1,
	"enabling shutdown diagnostics immediately persists an unclean session marker"
)

module:update(30)
check(dmf.save_calls == 1, "unchanged diagnostic heartbeat does not write settings again")

heap_kb = 850 * 1024
module:update(30)
check(
	mod.stored.tf_gc_last_heap_band == "high" and dmf.save_calls == 2,
	"diagnostic heap-band transition is persisted once"
)

module:update(30)
check(dmf.save_calls == 2, "unchanged high diagnostic band does not write settings again")

settings.gc_shutdown_diagnostic_enabled = false
module:on_setting_changed("gc_shutdown_diagnostic_enabled")
check(
	mod.stored.tf_gc_previous_shutdown_clean == true and dmf.save_calls == 3,
	"disabling shutdown diagnostics persists a clean marker"
)

-- Every restore-capable entry point scans for a newly enabled external owner
-- before it can call the Lua collector.
local restore_path_cases = {
	{
		label = "cleaning-permission setting",
		run = function (value)
			settings.gc_cleaning_permitted = false
			value:on_setting_changed("gc_cleaning_permitted")
		end,
	},
	{
		label = "module reset",
		run = function (value)
			value:reset()
		end,
	},
	{
		label = "module enable",
		run = function (value)
			value:on_enabled()
		end,
	},
}

for i = 1, #restore_path_cases do
	local case = restore_path_cases[i]

	reset_world()
	module = load_module()
	module:_set_tuning(1)
	external_mods[primary_controller_id].enabled = true
	clear_collector_calls()
	case.run(module)

	check(
		#collector_calls == 0
			and module._conflict_id == "cleanup_owner_primary"
			and module._tuning_owned == false,
		case.label .. " scans cleanup ownership before attempting tuning restoration"
	)
end

-- Restoration ownership survives a failed call. A later retry must restore
-- both exact original values before ownership can be released.
reset_world()
collector_pause = 220
collector_stepmul = 360
module = load_module()
module:_set_tuning(1)
clear_collector_calls()
fail_next_collector_call("setpause")
local restored = module:_restore_tuning("forced full restoration failure")

check(
	restored == false
		and module._tuning_owned == true
		and collector_pause == 80
		and collector_stepmul == 360,
	"failed pause restoration retains ownership for the unfinished value"
)

clear_collector_calls()
restored = module:_restore_tuning("retry after full failure")

check(
	restored == true
		and module._tuning_owned == false
		and collector_pause == 220
		and collector_stepmul == 360,
	"failed tuning restoration retries to exact completion"
)

reset_world()
collector_pause = 225
collector_stepmul = 375
module = load_module()
module:_set_tuning(1)
clear_collector_calls()
fail_next_collector_call("setstepmul")
restored = module:_restore_tuning("forced partial restoration failure")

check(
	restored == false
		and module._tuning_owned == true
		and collector_pause == 225
		and collector_stepmul == 500,
	"partial tuning restoration retains ownership for the unfinished value"
)

clear_collector_calls()
restored = module:_restore_tuning("retry after partial failure")

check(
	restored == true
		and module._tuning_owned == false
		and collector_pause == 225
		and collector_stepmul == 375,
	"partial tuning restoration retries the unfinished value to completion"
)

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
