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

local function contains(value, fragment)
	return type(value) == "string"
		and string.find(value, fragment, 1, true) ~= nil
end

local settings = {
	auto_quarantine_enabled = true,
	auto_quarantine_threshold = 3,
	diagnostic_logging = false,
}
local registrations = {}
local registration_counts = {}
local applied_hooks = {}
local hook_attempts = {}
local require_calls = 0

local mod = {
	enabled = true,
}

function mod:echo(_, ...)
end

function mod:error(_, ...)
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
	registrations[file_path] = callback
end

local function apply_hook(kind, target, method_name, handler)
	hook_attempts[method_name] = (hook_attempts[method_name] or 0) + 1

	if method_name == "explode" then
		error("intentional hook application failure")
	end

	applied_hooks[#applied_hooks + 1] = {
		handler = handler,
		kind = kind,
		method_name = method_name,
		target = target,
	}
end

function mod:hook_safe(target, method_name, handler)
	apply_hook("safe", target, method_name, handler)
end

function mod:hook(target, method_name, handler)
	apply_hook("normal", target, method_name, handler)
end

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	end

	return nil
end

local original_require = require

require = function (...)
	require_calls = require_calls + 1

	return original_require(...)
end

local runtime = dofile("scripts/mods/TertiumFixes/core.lua")

local function module_with_install(id, install)
	return {
		id = id,
		label = id,
		install = install,
	}
end

local success_callback_calls = 0
local success_callback_value = nil
local success_callback = module_with_install("success_callback", function (self)
	self.runtime:defer_file(self.id, "game/success", function (loaded_value)
		success_callback_calls = success_callback_calls + 1
		success_callback_value = loaded_value
	end)
end)

local success_safe_hook = module_with_install("success_safe_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/success",
		"alpha",
		"safe",
		function ()
		end
	)
end)

local success_normal_hook = module_with_install("success_normal_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/success",
		"beta",
		"normal",
		function ()
		end
	)
end)

local independent_hook = module_with_install("independent_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/independent",
		"gamma",
		"safe",
		function ()
		end
	)
end)

local failing_callback_attempts = 0
local failing_callback = module_with_install("failing_callback", function (self)
	self.runtime:defer_file(self.id, "game/callback_failure", function ()
		failing_callback_attempts = failing_callback_attempts + 1
		error("intentional deferred callback failure")
	end)
end)

local later_callback_calls = 0
local later_callback = module_with_install("later_callback", function (self)
	self.runtime:defer_file(self.id, "game/callback_failure", function ()
		later_callback_calls = later_callback_calls + 1
	end)
end)

local callback_path_hook = module_with_install("callback_path_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/callback_failure",
		"after_callback",
		"safe",
		function ()
		end
	)
end)

local failing_hook = module_with_install("failing_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/hook_failure",
		"explode",
		"safe",
		function ()
		end
	)
end)

local later_hook = module_with_install("later_hook", function (self)
	self.runtime:install_hook(
		self.id,
		"game/hook_failure",
		"after_explode",
		"normal",
		function ()
		end
	)
end)

check(
	runtime:add_module(success_callback)
		and runtime:add_module(success_safe_hook)
		and runtime:add_module(success_normal_hook)
		and runtime:add_module(independent_hook)
		and runtime:add_module(failing_callback)
		and runtime:add_module(later_callback)
		and runtime:add_module(callback_path_hook)
		and runtime:add_module(failing_hook)
		and runtime:add_module(later_hook),
	"deferred-loader test modules register"
)

runtime:install_modules()

check(require_calls == 0, "module installation never calls require")
check(
	registration_counts["game/success"] == 1
		and registration_counts["game/independent"] == 1
		and registration_counts["game/callback_failure"] == 1
		and registration_counts["game/hook_failure"] == 1,
	"one aggregated loader callback is registered for each of four game paths"
)
check(
	type(registrations["game/success"]) == "function"
		and type(registrations["game/independent"]) == "function"
		and type(registrations["game/callback_failure"]) == "function"
		and type(registrations["game/hook_failure"]) == "function",
	"independent deferred callbacks are retained for every game file"
)

local success_class = {
	alpha = function ()
	end,
	beta = function ()
	end,
}

registrations["game/success"](success_class)

check(
	success_callback_calls == 1 and success_callback_value == success_class,
	"successful deferred callback receives the value loaded by the game"
)
check(
	#applied_hooks == 2
		and applied_hooks[1].target == success_class
		and applied_hooks[1].method_name == "alpha"
		and applied_hooks[1].kind == "safe"
		and applied_hooks[2].target == success_class
		and applied_hooks[2].method_name == "beta"
		and applied_hooks[2].kind == "normal",
	"safe and normal hooks apply on a success-only path"
)
check(
	runtime:is_active("success_callback")
		and runtime:is_active("success_safe_hook")
		and runtime:is_active("success_normal_hook")
		and runtime:get_deferred_status("success_callback").state == "applied"
		and runtime:get_deferred_status("success_safe_hook").state == "applied"
		and runtime:get_deferred_status("success_normal_hook").state == "applied",
	"successful consumers stay active and report applied"
)

registrations["game/success"](success_class)

check(
	success_callback_calls == 1 and #applied_hooks == 2,
	"the same loaded module instance is never patched twice"
)

local independent_class = {
	gamma = function ()
	end,
}

registrations["game/independent"](independent_class)

check(
	#applied_hooks == 3
		and applied_hooks[3].target == independent_class
		and applied_hooks[3].method_name == "gamma"
		and runtime:get_deferred_status("independent_hook").state == "applied",
	"Lua 5.1 closure capture keeps deferred game paths independent"
)

local replacement_success_class = {
	alpha = function ()
	end,
	beta = function ()
	end,
}

registrations["game/success"](replacement_success_class)

check(
	success_callback_calls == 2
		and success_callback_value == replacement_success_class
		and #applied_hooks == 5
		and applied_hooks[4].target == replacement_success_class
		and applied_hooks[5].target == replacement_success_class,
	"a genuinely new module instance is patched once"
)

local callback_failure_target = {
	after_callback = function ()
	end,
}
local callback_barrier_ok = pcall(
	registrations["game/callback_failure"],
	callback_failure_target
)
local callback_status = runtime:get_deferred_status("failing_callback")

check(
	callback_barrier_ok
		and runtime._deferred_paths["game/callback_failure"].state == "restart-required"
		and callback_status.state == "restart-required"
		and callback_status.paths[1]
		and contains(
			callback_status.paths[1].reason,
			"deferred game-file callback failed"
		),
	"an ambiguous callback throw is contained and makes the whole path restart-required"
)
check(
	not runtime:is_active("failing_callback")
		and not runtime:is_active("later_callback")
		and not runtime:is_active("callback_path_hook")
		and not failing_callback.state.available
		and not later_callback.state.available
		and not callback_path_hook.state.available,
	"a callback throw disables every consumer of the ambiguous path"
)
check(
	failing_callback_attempts == 1
		and later_callback_calls == 0
		and (hook_attempts.after_callback or 0) == 0
		and #applied_hooks == 5,
	"operations after a throwing deferred callback are skipped"
)

local callback_failure_replacement = {
	after_callback = function ()
	end,
}

registrations["game/callback_failure"](callback_failure_target)
registrations["game/callback_failure"](callback_failure_replacement)
runtime:reset("failing_callback")
runtime:_register_deferred_paths()

check(
	failing_callback_attempts == 1
		and later_callback_calls == 0
		and (hook_attempts.after_callback or 0) == 0
		and registration_counts["game/callback_failure"] == 1
		and runtime._deferred_paths["game/callback_failure"].state == "restart-required"
		and not failing_callback.state.available
		and not runtime:is_active("failing_callback"),
	"callback-path replay, reset, and re-registration cannot revive an ambiguous patch"
)

local hook_failure_target = {
	explode = function ()
	end,
	after_explode = function ()
	end,
}
local hooks_before_failure = #applied_hooks
local hook_barrier_ok = pcall(
	registrations["game/hook_failure"],
	hook_failure_target
)
local hook_status = runtime:get_deferred_status("failing_hook")

check(
	hook_barrier_ok
		and runtime._deferred_paths["game/hook_failure"].state == "restart-required"
		and hook_status.state == "restart-required"
		and hook_status.paths[1]
		and contains(hook_status.paths[1].reason, "hook failed after game load"),
	"an ambiguous hook throw is contained and makes the whole path restart-required"
)
check(
	not runtime:is_active("failing_hook")
		and not runtime:is_active("later_hook")
		and not failing_hook.state.available
		and not later_hook.state.available,
	"a hook throw disables every consumer of the ambiguous path"
)
check(
	hook_attempts.explode == 1
		and (hook_attempts.after_explode or 0) == 0
		and #applied_hooks == hooks_before_failure,
	"hooks after an ambiguous hook failure are skipped"
)

local hook_failure_replacement = {
	explode = function ()
	end,
	after_explode = function ()
	end,
}

registrations["game/hook_failure"](hook_failure_target)
registrations["game/hook_failure"](hook_failure_replacement)
runtime:reset("failing_hook")
runtime:_register_deferred_paths()

check(
	hook_attempts.explode == 1
		and (hook_attempts.after_explode or 0) == 0
		and #applied_hooks == hooks_before_failure
		and registration_counts["game/hook_failure"] == 1
		and runtime._deferred_paths["game/hook_failure"].state == "restart-required"
		and not failing_hook.state.available
		and not runtime:is_active("failing_hook"),
	"hook-path replay, reset, and re-registration cannot revive an ambiguous patch"
)

check(require_calls == 0, "deferred callbacks never invoke require")

require = original_require

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
