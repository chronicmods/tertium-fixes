-- Standalone Lua 5.1/Fengari behavior contract for the packaged hardened core.
-- Usage from the TertiumFixes package root:
--   fengari tests/runtime_hardening_behavior.lua
--   fengari tests/runtime_hardening_behavior.lua path/to/core.lua

local core_path = arg and arg[1]
	 or "scripts/mods/TertiumFixes/core.lua"
local checks = 0
local failures = 0

local function check(condition, message)
	checks = checks + 1

	if condition then
		io.write("PASS " .. message .. "\n")
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local function contains(value, fragment)
	return type(value) == "string"
		and string.find(value, fragment, 1, true) ~= nil
end

local original_require = require
local require_calls = 0

require = function (...)
	require_calls = require_calls + 1

	return original_require(...)
end

local function new_harness(options)
	options = options or {}

	local registrations = {}
	local registration_counts = {}
	local hook_attempts = {}
	local applied_hooks = {}
	local settings = {
		auto_quarantine_enabled = true,
		auto_quarantine_threshold = options.threshold or 99,
		diagnostic_logging = false,
	}
	local mod = {
		echoes = {},
		enabled = true,
		errors = {},
	}

	local function capture(target, message, ...)
		local ok_format, formatted = pcall(string.format, message, ...)

		target[#target + 1] = ok_format and formatted or tostring(message)
	end

	function mod:echo(message, ...)
		capture(self.echoes, message, ...)
	end

	function mod:error(message, ...)
		capture(self.errors, message, ...)
	end

	function mod:get(setting_id)
		return settings[setting_id]
	end

	function mod:info(_, ...)
	end

	function mod:is_enabled()
		return self.enabled
	end

	function mod:warning(_, ...)
	end

	function mod:hook_require(file_path, callback)
		registration_counts[file_path] = (registration_counts[file_path] or 0) + 1

		if options.registration_error_before
			and options.registration_error_before[file_path] then
			error("registration failed before callback storage", 0)
		end

		registrations[file_path] = callback

		if options.synchronous_values
			and options.synchronous_values[file_path] ~= nil then
			callback(options.synchronous_values[file_path])
		end

		if options.registration_error_after
			and options.registration_error_after[file_path] then
			error("registration failed after callback storage", 0)
		end
	end

	function mod:hook(target, method_name, handler)
		hook_attempts[method_name] = (hook_attempts[method_name] or 0) + 1

		if options.hook_fail_method == method_name then
			error("intentional hook application failure: " .. method_name, 0)
		end

		if options.hook_warning_method == method_name then
			self:warning("(hook): Attempting to rehook active hook [%s].", method_name)

			return nil
		end

		if options.hook_error_method == method_name then
			self:error("(hook): rejected method [%s].", method_name)

			return nil
		end

		if options.hook_false_method == method_name then
			return false
		end

		applied_hooks[#applied_hooks + 1] = {
			handler = handler,
			method_name = method_name,
			target = target,
		}
	end

	function mod:hook_safe(target, method_name, handler)
		return self:hook(target, method_name, handler)
	end

	get_mod = function (name)
		if name == "TertiumFixes" then
			return mod
		end

		return nil
	end

	local runtime = assert(dofile(core_path))

	return {
		applied_hooks = applied_hooks,
		hook_attempts = hook_attempts,
		mod = mod,
		registration_counts = registration_counts,
		registrations = registrations,
		runtime = runtime,
		settings = settings,
	}
end

local function add_module(runtime, module_id)
	local module = {
		id = module_id,
		label = module_id,
	}

	check(runtime:add_module(module), module_id .. " registers")

	return module
end

do
	local harness = new_harness()
	local runtime = harness.runtime
	local module = add_module(runtime, "officially_fixed")

	module._fixed_upstream = true
	runtime:set_available("officially_fixed", false, "fixed upstream")
	runtime:print_status("officially_fixed")

	check(
		contains(harness.mod.echoes[#harness.mod.echoes], "(fixed upstream)"),
		"status output distinguishes an upstream fix from a missing repair"
	)
end

-- DMF returns nil on successful registration, so nil alone must stay green.
-- Its non-throwing rejection paths synchronously log through this mod's
-- warning/error methods; those diagnostics must turn the path terminal and the
-- temporary logger shadows must never leak.
do
	local harness = new_harness({ hook_warning_method = "duplicate" })
	local runtime = harness.runtime
	local duplicate = add_module(runtime, "duplicate_hook")
	local later = add_module(runtime, "later_after_duplicate")
	local original_error = harness.mod.error
	local original_warning = harness.mod.warning

	runtime:install_hook(
		"duplicate_hook",
		"game/hook_warning",
		"duplicate",
		"safe",
		function ()
		end
	)
	runtime:install_hook(
		"later_after_duplicate",
		"game/hook_warning",
		"later",
		"safe",
		function ()
		end
	)
	runtime:_register_deferred_paths()
	harness.registrations["game/hook_warning"]({
		duplicate = function ()
		end,
		later = function ()
		end,
	})

	check(
		runtime._deferred_paths["game/hook_warning"].state == "restart-required"
			and duplicate.state.available == false
			and later.state.available == false
			and harness.hook_attempts.duplicate == 1
			and harness.hook_attempts.later == nil
			and #harness.applied_hooks == 0,
		"a DMF duplicate warning cannot become a false applied status"
	)
	check(
		harness.mod.error == original_error
			and harness.mod.warning == original_warning,
		"DMF logger methods are restored after a warning rejection"
	)
end

do
	local harness = new_harness({ hook_error_method = "reject" })
	local runtime = harness.runtime
	local rejected = add_module(runtime, "error_rejected_hook")
	local original_error = harness.mod.error
	local original_warning = harness.mod.warning

	runtime:install_hook(
		"error_rejected_hook",
		"game/hook_error",
		"reject",
		"normal",
		function ()
		end
	)
	runtime:_register_deferred_paths()
	harness.registrations["game/hook_error"]({
		reject = function ()
		end,
	})

	check(
		runtime._deferred_paths["game/hook_error"].state == "restart-required"
			and rejected.state.available == false
			and contains(
				rejected.state.latest_error.message,
				"DMF rejected hook registration: error"
			),
		"a DMF error diagnostic cannot become a false applied status"
	)
	check(
		harness.mod.error == original_error
			and harness.mod.warning == original_warning,
		"DMF logger methods are restored after an error rejection"
	)
end

do
	local harness = new_harness({ hook_false_method = "future_false" })
	local runtime = harness.runtime
	local rejected = add_module(runtime, "false_rejected_hook")
	local original_error = harness.mod.error
	local original_warning = harness.mod.warning

	runtime:install_hook(
		"false_rejected_hook",
		"game/hook_false",
		"future_false",
		"safe",
		function ()
		end
	)
	runtime:_register_deferred_paths()
	harness.registrations["game/hook_false"]({
		future_false = function ()
		end,
	})

	check(
		runtime._deferred_paths["game/hook_false"].state == "restart-required"
			and rejected.state.available == false
			and contains(rejected.state.latest_error.message, "returned false"),
		"an explicit future hook-API false result is rejected"
	)
	check(
		harness.mod.error == original_error
			and harness.mod.warning == original_warning,
		"DMF logger methods are restored after an explicit false result"
	)
end

-- Lifetime telemetry is preserved, while quarantine is based on a resettable
-- consecutive-failure streak.
do
	local harness = new_harness({ threshold = 3 })
	local runtime = harness.runtime
	local module = add_module(runtime, "counter")
	local function fail(phase, message)
		return runtime:run_phase("counter", phase, function ()
			error(message, 0)
		end)
	end
	local function succeed(phase)
		return runtime:run_phase("counter", phase, function ()
			return "ok"
		end)
	end

	fail("isolated-1", "first failure")
	succeed("success-1")
	fail("isolated-2", "second failure")
	succeed("success-2")
	fail("isolated-3", "third failure")
	succeed("success-3")

	check(
		module.state.errors == 3
			and module.state.consecutive_errors == 0
			and not module.state.quarantined,
		"isolated failures remain lifetime telemetry and do not quarantine"
	)
	check(
		module.state.first_error
			and module.state.first_error.phase == "isolated-1"
			and module.state.first_error.message == "first failure"
			and module.state.latest_error.phase == "isolated-3",
		"first error is immutable and latest error advances"
	)
	check(
		module.state.first_error.sequence < module.state.latest_error.sequence
			and type(module.state.first_error.traceback) == "string",
		"structured errors retain ordering and traceback"
	)

	fail("streak-1", "streak one")
	fail("streak-2", "streak two")
	fail("streak-3", "streak three")

	check(
		module.state.errors == 6
			and module.state.consecutive_errors == 3
			and module.state.quarantined,
		"three consecutive failures quarantine independently of lifetime count"
	)
	check(
		module.state.latest_error.phase == "streak-3"
			and contains(module.state.reason, "3 consecutive")
			and contains(module.state.reason, "6 lifetime"),
		"quarantine reason reports streak and lifetime counts"
	)

	succeed("post-quarantine-success")
	check(
		module.state.consecutive_errors == 0 and module.state.quarantined,
		"success resets the streak but does not silently unlatch quarantine"
	)
	check(
		module.state.errors == 6 and module.state.latest_error.phase == "streak-3",
		"success does not erase lifetime or latest-error diagnostics"
	)

	runtime:reset("counter")
	check(
		module.state.errors == 0
			and module.state.consecutive_errors == 0
			and module.state.first_error == nil
			and module.state.latest_error == nil
			and not module.state.quarantined,
		"explicit reset clears error telemetry and quarantine"
	)
end

-- The normal deferred lifecycle is visible and duplicate-safe.
do
	local harness = new_harness()
	local runtime = harness.runtime
	add_module(runtime, "normal")
	local callback_calls = 0
	local applying_observed = false

	runtime:defer_file("normal", "game/normal", function ()
		callback_calls = callback_calls + 1
		applying_observed = runtime._deferred_paths["game/normal"].state == "applying"
	end)
	runtime:install_hook(
		"normal",
		"game/normal",
		"method",
		"safe",
		function ()
		end
	)

	check(
		runtime._deferred_paths["game/normal"].state == "pending",
		"deferred path begins pending"
	)
	runtime:_register_deferred_paths()
	check(
		runtime._deferred_paths["game/normal"].state == "registered"
			and runtime:get_deferred_status("normal").state == "registered",
		"successful hook_require registration becomes registered"
	)

	local first_target = { method = function () end }
	local second_target = { method = function () end }

	harness.registrations["game/normal"](first_target)
	check(
		applying_observed
			and runtime._deferred_paths["game/normal"].state == "applied"
			and runtime:get_deferred_status("normal").state == "applied",
		"callback observes applying and successful work becomes applied"
	)
	check(
		callback_calls == 1 and #harness.applied_hooks == 1,
		"first target receives each deferred operation once"
	)

	harness.registrations["game/normal"](first_target)
	check(
		callback_calls == 1 and #harness.applied_hooks == 1,
		"same target cannot be patched twice"
	)
	harness.registrations["game/normal"](second_target)
	check(
		callback_calls == 2 and #harness.applied_hooks == 2,
		"new target is accepted while path has never failed"
	)
end

-- hook_require may synchronously deliver a value that was already loaded.
do
	local target = { method = function () end }
	local harness = new_harness({
		synchronous_values = { ["game/synchronous"] = target },
	})
	local runtime = harness.runtime
	add_module(runtime, "synchronous")
	local observed_state = nil

	runtime:defer_file("synchronous", "game/synchronous", function ()
		observed_state = runtime._deferred_paths["game/synchronous"].state
	end)
	runtime:_register_deferred_paths()

	check(
		observed_state == "applying"
			and runtime._deferred_paths["game/synchronous"].state == "applied"
			and harness.registration_counts["game/synchronous"] == 1,
		"registered state is published before synchronous callback delivery"
	)
end

-- Clean compatibility failures are terminal but do not block already-valid
-- independent operations from applying once.
do
	local harness = new_harness()
	local runtime = harness.runtime
	local good = add_module(runtime, "good_hook")
	local missing = add_module(runtime, "missing_hook")
	local missing_second = add_module(runtime, "missing_hook_second")

	runtime:install_hook("good_hook", "game/preflight", "good", "safe", function () end)
	runtime:install_hook("missing_hook", "game/preflight", "missing", "safe", function () end)
	runtime:install_hook(
		"missing_hook_second",
		"game/preflight",
		"missing_second",
		"safe",
		function () end
	)
	runtime:_register_deferred_paths()
	harness.registrations["game/preflight"]({ good = function () end })

	local path_entry = runtime._deferred_paths["game/preflight"]
	check(
		path_entry.state == "failed"
			and #harness.applied_hooks == 1
			and good.state.available
			and not missing.state.available
			and not missing_second.state.available,
		"known missing method yields terminal failed while valid hook applies once"
	)
	check(
		path_entry.first_error
			and path_entry.latest_error
			and path_entry.first_error.method_name == "missing"
			and path_entry.latest_error.phase == "deferred-preflight"
			and path_entry.latest_error.method_name == "missing_second"
			and path_entry.first_error.sequence < path_entry.latest_error.sequence,
		"clean failures retain immutable first and advancing latest path diagnostics"
	)

	harness.registrations["game/preflight"]({
		good = function () end,
		missing = function () end,
		missing_second = function () end,
	})
	runtime:reset("missing_hook")
	runtime:_register_deferred_paths()
	check(
		#harness.applied_hooks == 1
			and harness.registration_counts["game/preflight"] == 1
			and path_entry.state == "failed"
			and not missing.state.available,
		"failed path is not replayed, re-registered, or revived by reset"
	)
end

-- A callback that may have partially mutated state is restart-required. The
-- outer DMF callback always returns normally, protecting the game's require.
do
	local harness = new_harness()
	local runtime = harness.runtime
	local failing = add_module(runtime, "failing_callback")
	local later = add_module(runtime, "later_callback")
	local attempts = 0
	local later_calls = 0

	runtime:defer_file("failing_callback", "game/callback_failure", function ()
		attempts = attempts + 1
		error("callback exploded", 0)
	end)
	runtime:defer_file("later_callback", "game/callback_failure", function ()
		later_calls = later_calls + 1
	end)
	runtime:_register_deferred_paths()

	local ok_delivery = pcall(
		harness.registrations["game/callback_failure"],
		{}
	)
	local path_entry = runtime._deferred_paths["game/callback_failure"]

	check(ok_delivery, "failed deferred callback never escapes the loader callback")
	check(
		path_entry.state == "restart-required"
			and attempts == 1
			and later_calls == 0
			and not failing.state.available
			and not later.state.available,
		"ambiguous callback failure disables every uninstalled path consumer"
	)
	check(
		failing.state.first_error
			and failing.state.first_error.phase == "deferred-apply"
			and failing.state.first_error.file_path == "game/callback_failure"
			and failing.state.first_error.operation_kind == "callback",
		"callback failure preserves structured module context"
	)

	pcall(harness.registrations["game/callback_failure"], {})
	runtime:reset("failing_callback")
	runtime:_register_deferred_paths()
	check(
		attempts == 1
			and harness.registration_counts["game/callback_failure"] == 1
			and path_entry.state == "restart-required"
			and not failing.state.available,
		"restart-required callback path cannot retry in-process"
	)
end

-- A hook API throw is also ambiguous and terminal.
do
	local harness = new_harness({ hook_fail_method = "explode" })
	local runtime = harness.runtime
	local module = add_module(runtime, "failing_hook")

	runtime:install_hook(
		"failing_hook",
		"game/hook_failure",
		"explode",
		"safe",
		function ()
		end
	)
	runtime:_register_deferred_paths()
	local ok_delivery = pcall(
		harness.registrations["game/hook_failure"],
		{ explode = function () end }
	)
	local path_entry = runtime._deferred_paths["game/hook_failure"]

	check(
		ok_delivery
			and path_entry.state == "restart-required"
			and harness.hook_attempts.explode == 1
			and module.state.latest_error.method_name == "explode",
		"hook application throw is swallowed, structured, and restart-required"
	)
	pcall(
		harness.registrations["game/hook_failure"],
		{ explode = function () end }
	)
	check(
		harness.hook_attempts.explode == 1,
		"hook application failure is never replayed on another target"
	)
end

-- Even an unexpected bug in the dispatcher itself cannot poison wrapped
-- require; the fallback marks every consumer restart-required best-effort.
do
	local harness = new_harness()
	local runtime = harness.runtime
	local module = add_module(runtime, "barrier")

	runtime:defer_file("barrier", "game/barrier", function () end)
	runtime:_register_deferred_paths()
	runtime._apply_deferred_path = function ()
		error("dispatcher itself escaped", 0)
	end

	local ok_delivery = pcall(harness.registrations["game/barrier"], {})
	local path_entry = runtime._deferred_paths["game/barrier"]

	check(
		ok_delivery
			and path_entry.state == "restart-required"
			and not module.state.available,
		"outer no-throw barrier contains an internal dispatcher escape"
	)
	check(
		module.state.latest_error
			and module.state.latest_error.phase == "deferred-loader-barrier"
			and contains(module.state.latest_error.message, "dispatcher itself escaped"),
		"outer barrier records first/latest structured failure detail"
	)
end

-- A hook_require throw can mean registration was partly completed, so it is
-- attempted exactly once and always requires restart.
do
	local harness = new_harness({
		registration_error_before = { ["game/register_failure"] = true },
	})
	local runtime = harness.runtime
	local module = add_module(runtime, "register_failure")

	runtime:defer_file("register_failure", "game/register_failure", function () end)
	runtime:_register_deferred_paths()
	runtime:_register_deferred_paths()
	runtime:reset("register_failure")
	runtime:_register_deferred_paths()

	check(
		harness.registration_counts["game/register_failure"] == 1
			and runtime._deferred_paths["game/register_failure"].state == "restart-required"
			and not module.state.available,
		"registration failure is attempted once and cannot be reset in-process"
	)
end

-- If synchronous application succeeded but hook_require then throws, the
-- registration result is ambiguous and the stronger terminal state wins.
do
	local target = {}
	local harness = new_harness({
		registration_error_after = { ["game/after_sync"] = true },
		synchronous_values = { ["game/after_sync"] = target },
	})
	local runtime = harness.runtime
	local module = add_module(runtime, "after_sync")
	local calls = 0

	runtime:defer_file("after_sync", "game/after_sync", function ()
		calls = calls + 1
	end)
	runtime:_register_deferred_paths()

	check(
		calls == 1
			and runtime._deferred_paths["game/after_sync"].state == "restart-required"
			and harness.registration_counts["game/after_sync"] == 1
			and not module.state.available,
		"post-callback registration throw overrides applied with restart-required"
	)
end

-- Distinct locals inside the registration loop preserve Lua 5.1 closure
-- behavior for multiple deferred paths.
do
	local harness = new_harness()
	local runtime = harness.runtime
	add_module(runtime, "closure")
	local first_calls = 0
	local second_calls = 0

	runtime:defer_file("closure", "game/first", function ()
		first_calls = first_calls + 1
	end)
	runtime:defer_file("closure", "game/second", function ()
		second_calls = second_calls + 1
	end)
	runtime:_register_deferred_paths()
	harness.registrations["game/first"]({})
	harness.registrations["game/second"]({})

	check(
		first_calls == 1
			and second_calls == 1
			and runtime._deferred_paths["game/first"].state == "applied"
			and runtime._deferred_paths["game/second"].state == "applied",
		"Lua 5.1 closure capture keeps deferred paths independent"
	)
end

-- Both the engine/LuaJIT path and a Lua 5.1 xpcall must preserve nil values.
do
	local harness = new_harness()
	local runtime = harness.runtime
	add_module(runtime, "return_values")
	local native_xpcall = xpcall
	local seen_callback
	local seen_handler
	local callback_count = 0
	local function values(...)
		callback_count = callback_count + 1
		return select("#", ...), ...
	end
	local function pack(...)
		return { n = select("#", ...), ... }
	end

	xpcall = function (callback, handler, ...)
		seen_callback = callback
		seen_handler = handler
		return native_xpcall(callback, handler, ...)
	end

	local result = pack(runtime:run("return_values", values, "a", nil, false, "d", nil, "f", nil))
	local error_handler = seen_handler

	check(
		result.n == 9 and result[1] == true and result[2] == 7
			and result[3] == "a" and result[4] == nil and result[5] == false
			and result[6] == "d" and result[7] == nil and result[8] == "f" and result[9] == nil,
		"run preserves every return value, including trailing nils beyond four results"
	)
	check(seen_callback == values, "argument-capable xpcall receives the callback directly")

	runtime:run("return_values", values, nil)
	check(seen_handler == error_handler and callback_count == 2, "success calls reuse the error handler and invoke the callback once")

	xpcall = function (callback, handler)
		return native_xpcall(callback, handler)
	end
	result = pack(runtime:run("return_values", values, "legacy", nil, false, nil))

	check(
		result.n == 6 and result[2] == 4 and result[3] == "legacy"
			and result[4] == nil and result[5] == false and result[6] == nil,
		"Lua 5.1 fallback preserves arguments and returns when xpcall drops extra arguments"
	)
	xpcall = native_xpcall
end

do
	local harness = new_harness({ threshold = 1 })
	local runtime = harness.runtime
	local module = add_module(runtime, "owned_state")
	local owned = true
	local cleanups = 0
	local enables = 0

	module.on_disabled = function ()
		owned = false
		cleanups = cleanups + 1
	end
	module.on_enabled = function ()
		owned = true
		enables = enables + 1
	end
	runtime:record_error(module.id, "hook failed")

	check(
		module.state.quarantined and not owned and cleanups == 1 and module.state.consecutive_errors == 1,
		"quarantine releases owned state without erasing the failure streak"
	)
	runtime:reset(module.id)
	check(owned and enables == 1 and runtime:is_active(module.id), "reset reapplies state released by quarantine")

	runtime:set_available(module.id, false, "changed game API")
	check(not owned and cleanups == 2, "losing availability also releases owned state")
end

do
	local harness = new_harness({ threshold = 1 })
	local runtime = harness.runtime
	local module = add_module(runtime, "failed_cleanup")
	local cleanups = 0

	module.on_disabled = function ()
		cleanups = cleanups + 1
		error("cleanup failed", 0)
	end
	local ok = pcall(runtime.record_error, runtime, module.id, "initial failure")

	check(
		ok and cleanups == 1 and module.state.errors == 2
			and module.state.latest_error.phase == "quarantine-cleanup",
		"failed quarantine cleanup is recorded once without recursion or escaping"
	)
	module.reset = function () error("reset failed", 0) end
	harness.settings.auto_quarantine_threshold = 99
	runtime:invalidate_setting("auto_quarantine_threshold")
	runtime:reset(module.id)
	check(module.state.quarantined and not runtime:is_active(module.id), "a failed reset cannot reactivate a quarantined module")
end

do
	local harness = new_harness()
	local runtime = harness.runtime
	local module = add_module(runtime, "bad_error_object")
	local err = setmetatable({}, {
		__tostring = function () error("cannot print", 0) end,
		__index = function () error("cannot index", 0) end,
	})
	local ok, success = pcall(runtime.run, runtime, module.id, function () error(err, 0) end)

	check(
		ok and not success and contains(module.state.last_error, "unprintable table error"),
		"an error object with broken metamethods still produces a contained diagnostic"
	)
end

for _, event in ipairs({ "on_disabled", "on_unload" }) do
	local harness = new_harness({ threshold = 1 })
	local runtime = harness.runtime
	local module = add_module(runtime, "failed_" .. event)
	local callbacks = 0
	module.on_disabled = function ()
		callbacks = callbacks + 1
		error("cleanup failed", 0)
	end
	module.on_unload = module.on_disabled
	runtime:dispatch(event)

	check(callbacks == 1 and module.state.quarantined, event .. " cannot re-enter partially completed cleanup when its error triggers quarantine")
end

do
	local harness = new_harness({ threshold = 1 })
	local runtime = harness.runtime
	local module = add_module(runtime, "deferred_cleanup")
	local cleanups = 0
	module.on_disabled = function () cleanups = cleanups + 1 end
	runtime:defer_file(module.id, "game/deferred_cleanup", function () end)
	runtime:_fail_deferred_operation("game/deferred_cleanup", module.id, "missing method", {})
	check(cleanups == 1 and module.state.quarantined and not module.state.available, "a deferred error cannot repeat quarantine cleanup when it also marks the module unavailable")
	local count, last
	module.on_unload = function (_, ...)
		count = select("#", ...)
		last = select(3, ...)
	end
	runtime:dispatch("on_unload", "first", nil, "last")
	check(count == 3 and last == "last", "guarded cleanup preserves lifecycle callback arguments")
end

check(require_calls == 0, "core never calls require during install, failure, or reset")

require = original_require

io.write(string.format(
	"\n%s: %d checks, %d failures\n",
	failures == 0 and "OK" or "FAILED",
	checks,
	failures
))

if failures > 0 then
	os.exit(1)
end
