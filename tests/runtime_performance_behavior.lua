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
	return math.abs(actual - expected) < 0.000001
end

local settings = {
	active_feature = true,
	auto_quarantine_enabled = true,
	auto_quarantine_threshold = 1,
	cache_probe = 41,
	diagnostic_logging = false,
	disabled_feature = false,
	interval_feature = true,
	toggle_feature = true,
}

local get_calls = {}
local requested_mod_names = {}

local mod = {
	echoes = {},
	enabled = true,
	errors = {},
	infos = {},
	is_enabled_calls = 0,
	warnings = {},
}

local function capture(target, message, ...)
	local ok, formatted = pcall(string.format, message, ...)

	target[#target + 1] = ok and formatted or tostring(message)
end

function mod:echo(message, ...)
	capture(self.echoes, message, ...)
end

function mod:error(message, ...)
	capture(self.errors, message, ...)
end

function mod:get(setting_id)
	get_calls[setting_id] = (get_calls[setting_id] or 0) + 1

	return settings[setting_id]
end

function mod:info(message, ...)
	capture(self.infos, message, ...)
end

function mod:is_enabled()
	self.is_enabled_calls = self.is_enabled_calls + 1

	return self.enabled
end

function mod:warning(message, ...)
	capture(self.warnings, message, ...)
end

function get_mod(name)
	requested_mod_names[#requested_mod_names + 1] = name

	if name == "TertiumFixes" then
		return mod
	end

	return nil
end

local runtime = dofile("scripts/mods/TertiumFixes/core.lua")

check(
	requested_mod_names[1] == "TertiumFixes"
		and mod.is_enabled_calls == 1
		and runtime:mod_is_enabled(),
	"runtime initializes from the expected enabled mod"
)

local first_probe = runtime:get("cache_probe")
local second_probe = runtime:get("cache_probe")

check(
	first_probe == 41
		and second_probe == 41
		and get_calls.cache_probe == 1,
	"settings are cached between invalidations"
)

runtime:invalidate_setting("cache_probe")

check(
	runtime:get("cache_probe") == 41 and get_calls.cache_probe == 2,
	"explicit invalidation refreshes a cached setting"
)

local update_calls = {
	active = 0,
	disabled = 0,
	interval = {},
	toggle = 0,
}
local setting_events = {}

local active_updater = {
	id = "active_updater",
	label = "Active updater",
	setting_id = "active_feature",
	update = function (_, _)
		update_calls.active = update_calls.active + 1
	end,
}

local disabled_updater = {
	id = "disabled_updater",
	label = "Disabled updater",
	setting_id = "disabled_feature",
	update = function (_, _)
		update_calls.disabled = update_calls.disabled + 1
	end,
}

local passive_module = {
	id = "passive_module",
	label = "Passive module",
}

local interval_updater = {
	id = "interval_updater",
	label = "Interval updater",
	setting_id = "interval_feature",
	update_interval = 0.5,
	update = function (_, dt)
		update_calls.interval[#update_calls.interval + 1] = dt
	end,
}

local toggle_updater = {
	id = "toggle_updater",
	label = "Toggle updater",
	setting_id = "toggle_feature",
	on_setting_changed = function (_, setting_id)
		setting_events[#setting_events + 1] = setting_id
	end,
	update = function (_, _)
		update_calls.toggle = update_calls.toggle + 1
	end,
}

check(
	runtime:add_module(active_updater)
		and runtime:add_module(disabled_updater)
		and runtime:add_module(passive_module)
		and runtime:add_module(interval_updater)
		and runtime:add_module(toggle_updater),
	"test modules register successfully"
)

runtime:_refresh_all_module_activation()
runtime:is_active("disabled_updater")
runtime:is_active("disabled_updater")

check(
	get_calls.disabled_feature == 1
		and not runtime:is_active("disabled_updater"),
	"disabled module activation is cached without repeated setting reads"
)

local function scheduled(module_id)
	for i = 1, #runtime._update_modules do
		if runtime._update_modules[i].id == module_id then
			return true
		end
	end

	return false
end

check(
	#runtime._update_modules == 3
		and scheduled("active_updater")
		and scheduled("interval_updater")
		and scheduled("toggle_updater")
		and not scheduled("disabled_updater")
		and not scheduled("passive_module"),
	"only active modules with update callbacks enter the scheduler"
)

runtime:update(0)

check(
	update_calls.active == 1
		and update_calls.toggle == 1
		and update_calls.disabled == 0
		and #update_calls.interval == 0,
	"an update tick invokes active immediate updaters only"
)

runtime:update(0.2)
runtime:update(0.2)

check(
	#update_calls.interval == 0,
	"interval updater does not run before its schedule is due"
)

runtime:update(0.2)

check(
	#update_calls.interval == 1
		and approximately(update_calls.interval[1], 0.6),
	"interval updater receives accumulated elapsed time"
)

local interval_calls_before_long_tick = #update_calls.interval

runtime:update(1.3)

check(
	#update_calls.interval == interval_calls_before_long_tick + 1
		and approximately(update_calls.interval[2], 1.3),
	"long tick runs once without counting the previous remainder twice"
)

local toggle_reads_before_change = get_calls.toggle_feature

settings.toggle_feature = false
runtime:setting_changed("toggle_feature")

check(
	get_calls.toggle_feature == toggle_reads_before_change + 1
		and not runtime:is_active("toggle_updater"),
	"setting_changed invalidates and refreshes module activation"
)
check(
	#setting_events == 1 and setting_events[1] == "toggle_feature",
	"setting_changed dispatches after activation refresh"
)

local toggle_calls_after_disable = update_calls.toggle

runtime:update(0)

check(
	update_calls.toggle == toggle_calls_after_disable
		and not scheduled("toggle_updater"),
	"setting-disabled updater is removed from scheduled work"
)

local total_updates_before_mod_disable = update_calls.active
	+ update_calls.disabled
	+ #update_calls.interval
	+ update_calls.toggle

mod.enabled = false
runtime:set_mod_enabled(false)

check(
	#runtime._update_modules == 0,
	"whole-mod disable empties active updater work"
)

runtime:update(1)

local total_updates_after_mod_disable = update_calls.active
	+ update_calls.disabled
	+ #update_calls.interval
	+ update_calls.toggle

check(
	total_updates_after_mod_disable == total_updates_before_mod_disable,
	"whole-mod disable makes update ticks inert"
)

settings.active_feature = false
settings.toggle_feature = true

local active_reads_before_enable = get_calls.active_feature
local disabled_reads_before_enable = get_calls.disabled_feature
local interval_reads_before_enable = get_calls.interval_feature
local toggle_reads_before_enable = get_calls.toggle_feature

mod.enabled = true
runtime:set_mod_enabled(true)

check(
	get_calls.active_feature == active_reads_before_enable + 1
		and get_calls.disabled_feature == disabled_reads_before_enable + 1
		and get_calls.interval_feature == interval_reads_before_enable + 1
		and get_calls.toggle_feature == toggle_reads_before_enable + 1,
	"whole-mod re-enable refreshes all module settings"
)
check(
	not runtime:is_active("active_updater")
		and runtime:is_active("interval_updater")
		and runtime:is_active("toggle_updater")
		and #runtime._update_modules == 2,
	"whole-mod re-enable rebuilds updater work from refreshed settings"
)

local toggle_calls_before_quarantine = update_calls.toggle

runtime:record_error("toggle_updater", "test quarantine")

check(
	toggle_updater.state.quarantined
		and not runtime:is_active("toggle_updater")
		and not scheduled("toggle_updater"),
	"quarantine removes an updater from scheduled work"
)

runtime:update(0)

check(
	update_calls.toggle == toggle_calls_before_quarantine,
	"quarantined updater remains inert on later ticks"
)

-- A quarantine during update must not shift another updater out of this tick.
local following_calls = 0
local failing_updater = {
	id = "fails_during_update",
	update = function () error("update failed", 0) end,
}
local following_updater = {
	id = "follows_failed_update",
	update = function () following_calls = following_calls + 1 end,
}

runtime:add_module(failing_updater)
runtime:add_module(following_updater)
runtime:update(0.1)

check(
	failing_updater.state.quarantined and following_calls == 1,
	"quarantine during a tick does not skip the following updater"
)

local elapsed_sum = 0
local interval_calls = 0
local clock_probe = {
	id = "elapsed_time_probe",
	update_interval = 0.05,
	update = function (_, dt)
		elapsed_sum = elapsed_sum + dt
		interval_calls = interval_calls + 1
	end,
}

runtime:add_module(clock_probe)

for _ = 1, 600 do
	runtime:update(0.016)
end

check(
	interval_calls >= 191 and interval_calls <= 192
		and approximately(elapsed_sum + clock_probe.state.update_elapsed, 9.6),
	"interval callbacks account for real elapsed time across frame remainders"
)

local clock_before_nan = runtime.clock
runtime:update(0 / 0)

check(
	runtime.clock == clock_before_nan and clock_probe.state.update_elapsed == clock_probe.state.update_elapsed,
	"an invalid frame delta cannot poison the runtime or interval clock"
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
