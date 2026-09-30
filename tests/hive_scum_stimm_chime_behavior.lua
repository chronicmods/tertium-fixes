local failures = 0
local checks = 0

local function check(condition, message, detail)
	checks = checks + 1

	if condition then
		io.write("PASS " .. message .. "\n")
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message)

		if detail ~= nil then
			io.stderr:write(": " .. tostring(detail))
		end

		io.stderr:write("\n")
	end
end

local hooks = {}
local active = {}
local availability = {}
local hits = {}
local actions = {}
local callback_errors = {}
local hook_install_succeeds = true

local function increment(counters, key, amount)
	counters[key] = (counters[key] or 0) + (amount or 1)
end

local runtime = {}

function runtime:install_hook(module_id, path, method, kind, handler)
	if not hook_install_succeeds then
		return false
	end

	hooks[module_id] = {
		path = path,
		method = method,
		kind = kind,
		handler = handler,
	}

	return true
end

function runtime:is_active(module_id)
	return active[module_id] ~= false
end

function runtime:run(module_id, callback, ...)
	local ok, result = pcall(callback, ...)

	if not ok then
		increment(callback_errors, module_id)
	end

	return ok, result
end

function runtime:set_available(module_id, available, reason)
	availability[module_id] = {
		available = available,
		reason = reason,
	}
end

function runtime:record_hit(module_id, amount)
	increment(hits, module_id, amount)
end

function runtime:record_action(module_id, amount)
	increment(actions, module_id, amount)
end

local mod = {
	_tf_runtime = runtime,
}

function get_mod(name)
	check(name == "TertiumFixes", "chime module requests the expected mod")

	return mod
end

local original_require = require
local require_calls = 0

function require(...)
	require_calls = require_calls + 1

	return original_require(...)
end

DEDICATED_SERVER = nil

local module = dofile(
	"scripts/mods/TertiumFixes/modules/hive_scum_stimm_chime.lua"
)
local module_id = "hive_scum_stimm_chime"

check(type(module) == "table", "chime module loads")
check(module.id == module_id, "chime module exposes its exact id")
check(
	module.setting_id == "hive_scum_stimm_chime_enabled",
	"chime module exposes its master setting"
)
check(require_calls == 0, "chime module performs no eager game require")

local install_ok, install_error = pcall(module.install, module)
local hook = hooks[module_id]

check(install_ok, "chime module installs", install_error)
check(
	hook ~= nil
		and hook.path
			== "scripts/extension_systems/ability/player_unit_ability_extension"
		and hook.method == "fixed_update"
		and hook.kind == "safe"
		and type(hook.handler) == "function",
	"chime module registers the exact deferred post-update hook"
)

local sounds = {}

Managers = {
	ui = {
		play_2d_sound = function (_, event_name)
			sounds[#sounds + 1] = event_name
		end,
	},
}

local ability_type_calls = {}
local ability = {
	name = "broker_ability_syringe",
}
local extension_methods = {}

function extension_methods:ability_is_equipped(ability_type)
	ability_type_calls[#ability_type_calls + 1] = {
		method = "equipped",
		ability_type = ability_type,
	}

	return self.ability
end

function extension_methods:remaining_ability_charges(ability_type)
	ability_type_calls[#ability_type_calls + 1] = {
		method = "charges",
		ability_type = ability_type,
	}

	return self.charges
end


local function new_extension(is_local, equipped_ability, charges)
	return setmetatable({
		_is_local_unit = is_local,
		ability = equipped_ability,
		charges = charges,
	}, {
		__index = extension_methods,
	})
end

local extension = new_extension(true, ability, 1)
local handler = hook and hook.handler

handler(extension, "unit", 0.016, 100, 1)
check(#sounds == 0, "first ready observation is silent")
check(
	(hits[module_id] or 0) == 0 and (actions[module_id] or 0) == 0,
	"silent baseline records no transition"
)
check(
	#ability_type_calls == 2
		and ability_type_calls[1].ability_type == "pocketable_ability"
		and ability_type_calls[2].ability_type == "pocketable_ability",
	"chime reads only the pocketable ability type"
)

extension.charges = 0
handler(extension)
handler(extension)
check(#sounds == 0, "spent and repeatedly empty stimm stays silent")

extension.charges = 1
handler(extension)
check(
	#sounds == 1
		and sounds[1] == "wwise/events/ui/play_hud_ability_off_cooldown",
	"empty-to-ready transition plays the exact stock ability-ready cue"
)
check(
	(hits[module_id] or 0) == 1 and (actions[module_id] or 0) == 1,
	"successful ready transition records one hit and action"
)

handler(extension)
handler(extension)
check(#sounds == 1, "repeated ready updates do not replay the cue")

extension.charges = 0
handler(extension)
extension.charges = 1
handler(extension)
check(
	#sounds == 2
		and (hits[module_id] or 0) == 2
		and (actions[module_id] or 0) == 2,
	"a later genuine recharge produces exactly one later cue"
)

local empty_on_first_sample = new_extension(true, ability, 0)

handler(empty_on_first_sample)
empty_on_first_sample.charges = 1
handler(empty_on_first_sample)
check(#sounds == 3, "a stimm first observed empty chimes when it later becomes ready")

local field_ability = {
	name = "broker_ability_stimm_field",
}
local wrong_ability = {
	name = "psyker_ability_shout",
}
local field_extension = new_extension(true, field_ability, 0)
local wrong_extension = new_extension(true, wrong_ability, 0)

handler(field_extension)
field_extension.charges = 1
handler(field_extension)
handler(wrong_extension)
wrong_extension.charges = 1
handler(wrong_extension)
check(#sounds == 3, "stimm field and unrelated abilities never trigger the cue")

local switched_extension = new_extension(true, wrong_ability, 0)

handler(switched_extension)
switched_extension.ability = ability
switched_extension.charges = 1
handler(switched_extension)
check(#sounds == 3, "switching to an already-ready Hive Scum stimm baselines silently")
switched_extension.charges = 0
handler(switched_extension)
switched_extension.charges = 1
handler(switched_extension)
check(#sounds == 4, "a switched-in Hive Scum stimm chimes after its next recharge")

local remote_extension = new_extension(false, ability, 0)

handler(remote_extension)
remote_extension.charges = 1
handler(remote_extension)
check(#sounds == 4, "remote players never trigger the local chime")

local disabled_extension = new_extension(true, ability, 0)

handler(disabled_extension)
active[module_id] = false
disabled_extension.charges = 1
handler(disabled_extension)
active[module_id] = true
handler(disabled_extension)
check(#sounds == 4, "disabled and re-enabled module baselines silently")
disabled_extension.charges = 0
handler(disabled_extension)
disabled_extension.charges = 1
handler(disabled_extension)
check(#sounds == 5, "re-enabled module observes the next real recharge")

local no_ui_extension = new_extension(true, ability, 0)

handler(no_ui_extension)
Managers = nil
no_ui_extension.charges = 1
handler(no_ui_extension)
check(
	#sounds == 5
		and (hits[module_id] or 0) == 6
		and (actions[module_id] or 0) == 5,
	"missing UI fails closed while recording the observed recharge"
)

Managers = {
	ui = {
		play_2d_sound = function (_, event_name)
			sounds[#sounds + 1] = event_name
		end,
	},
}
handler(no_ui_extension)
check(#sounds == 5, "restoring UI cannot replay an already-consumed transition")

local throwing_extension = new_extension(true, ability, 0)

handler(throwing_extension)
Managers.ui.play_2d_sound = function ()
	error("simulated audio failure")
end
throwing_extension.charges = 1
local throwing_ok = pcall(handler, throwing_extension)
local errors_after_throw = callback_errors[module_id] or 0

check(
	throwing_ok and errors_after_throw == 1,
	"runtime containment catches an audio playback failure"
)
handler(throwing_extension)
check(
	(callback_errors[module_id] or 0) == errors_after_throw,
	"failed playback is not retried every fixed frame"
)

Managers.ui.play_2d_sound = function (_, event_name)
	sounds[#sounds + 1] = event_name
end

local malformed_extension = new_extension(true, ability, 0)

malformed_extension.ability_is_equipped = function ()
	error("simulated ability API failure")
end
local malformed_ok = pcall(handler, malformed_extension)
check(
	malformed_ok and (callback_errors[module_id] or 0) == errors_after_throw + 1,
	"runtime containment catches a malformed ability extension"
)

local invalid_cases = {
	false,
	{},
	new_extension(true, nil, 1),
	new_extension(true, ability, "one"),
}
local invalid_ok = true

for _, value in ipairs(invalid_cases) do
	invalid_ok = pcall(handler, value) and invalid_ok
end

check(invalid_ok and #sounds == 5, "missing and invalid extension state fails closed")

local lifecycle_extension = new_extension(true, ability, 0)

handler(lifecycle_extension)
local state_before_game_change = module._charges_by_extension
module:on_game_state_changed("exit", "StateIngame")
check(
	module._charges_by_extension ~= state_before_game_change,
	"game-state change replaces the weak charge-state table"
)
lifecycle_extension.charges = 1
handler(lifecycle_extension)
check(#sounds == 5, "mission transition resets to a silent ready baseline")

lifecycle_extension.charges = 0
handler(lifecycle_extension)
module:on_setting_changed("unrelated_setting")
lifecycle_extension.charges = 1
handler(lifecycle_extension)
check(#sounds == 6, "unrelated setting changes preserve an armed recharge")

lifecycle_extension.charges = 0
handler(lifecycle_extension)
module:on_setting_changed(module.setting_id)
lifecycle_extension.charges = 1
handler(lifecycle_extension)
check(#sounds == 6, "own setting change clears pending transition state")

local state_before_enabled = module._charges_by_extension
module:on_enabled()
local state_before_disabled = module._charges_by_extension
module:on_disabled()
local state_before_unload = module._charges_by_extension
module:on_unload()
local state_before_reset = module._charges_by_extension
module:reset()

check(
	state_before_enabled ~= state_before_disabled
		and state_before_disabled ~= state_before_unload
		and state_before_unload ~= state_before_reset
		and state_before_reset ~= module._charges_by_extension,
	"enable, disable, unload, and reset each clear observation state"
)
check(module:runtime_status() == "listening", "active runtime status reports listening")
active[module_id] = false
check(module:runtime_status() == "disabled", "inactive runtime status reports disabled")
active[module_id] = true
check(
	string.find(module:describe(), "Hive Scum", 1, true) ~= nil,
	"module description identifies the exact archetype"
)

local predicted = new_extension(true, ability, 1)
predicted._unit_data_extension = { is_resimulating = false }
handler(predicted)
local sounds_before_resim = #sounds
predicted._unit_data_extension.is_resimulating = true
predicted.charges = 0
handler(predicted)
predicted.charges = 1
handler(predicted)
predicted._unit_data_extension.is_resimulating = false
handler(predicted)
check(#sounds == sounds_before_resim,
	"replaying an old empty-to-ready transition during prediction does not repeat the chime")
predicted.charges = 0
handler(predicted)
predicted._unit_data_extension.is_resimulating = true
predicted.charges = 1
handler(predicted)
predicted._unit_data_extension.is_resimulating = false
handler(predicted)
check(#sounds == sounds_before_resim + 1,
	"a newly ready stimm chimes once after prediction has finished")

local temporarily_disabled = new_extension(true, ability, 1)
temporarily_disabled.enabled = true
temporarily_disabled.ability_enabled = function (self) return self.enabled end
handler(temporarily_disabled)
local sounds_before_enable = #sounds
temporarily_disabled.enabled = false
temporarily_disabled.charges = 0
handler(temporarily_disabled)
temporarily_disabled.enabled = true
temporarily_disabled.charges = 1
handler(temporarily_disabled)
check(#sounds == sounds_before_enable,
	"reenabling an existing full charge does not look like a recharge")

local invalid_numbers = { 0 / 0, math.huge, -1 }
for _, value in ipairs(invalid_numbers) do
	local invalid_charge = new_extension(true, ability, value)
	handler(invalid_charge)
	invalid_charge.charges = 1
	handler(invalid_charge)
end
check(#sounds == sounds_before_enable, "invalid charge numbers cannot arm a false ready cue")

local deleted_reads = 0
local deleted_extension = setmetatable({ _is_local_unit = true, __deleted = true }, {
	__index = function () deleted_reads = deleted_reads + 1; error("deleted object") end,
})
handler(deleted_extension)
check(deleted_reads == 0, "deleted ability extensions are skipped without reading their methods")

DEDICATED_SERVER = true
local dedicated_module = dofile(
	"scripts/mods/TertiumFixes/modules/hive_scum_stimm_chime.lua"
)
local hooks_before_dedicated = hooks[module_id]
dedicated_module:install()
check(
	hooks[module_id] == hooks_before_dedicated
		and availability[module_id] ~= nil
		and availability[module_id].available == false
		and availability[module_id].reason == "dedicated server",
	"dedicated server marks the chime unavailable without installing a hook"
)

DEDICATED_SERVER = nil
availability[module_id] = nil
hook_install_succeeds = false
local unavailable_module = dofile(
	"scripts/mods/TertiumFixes/modules/hive_scum_stimm_chime.lua"
)
unavailable_module:install()
check(
	availability[module_id] ~= nil
		and availability[module_id].available == false
		and availability[module_id].reason
			== "PlayerUnitAbilityExtension.fixed_update unavailable",
	"failed hook registration marks the chime unavailable"
)

require = original_require
Managers = nil
DEDICATED_SERVER = nil

print(string.format("RESULT: %d passed, %d failed", checks - failures, failures))

if failures > 0 then
	os.exit(1)
end
