local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local TARGET_PATH = "scripts/extension_systems/ability/player_unit_ability_extension"
local ABILITY_TYPE = "pocketable_ability"
local ABILITY_NAME = "broker_ability_syringe"
local READY_SOUND = "wwise/events/ui/play_hud_ability_off_cooldown"

local function _new_charge_state()
	return setmetatable({}, { __mode = "k" })
end

local module = {
	id = "hive_scum_stimm_chime",
	label = "Hive Scum stimm ready chime",
	setting_id = "hive_scum_stimm_chime_enabled",
	_charges_by_extension = _new_charge_state(),
}

function module:_clear_state()
	self._charges_by_extension = _new_charge_state()
end

function module:_observe_charge(extension)
	local charge_state = self._charges_by_extension

	if type(extension) ~= "table"
		or rawget(extension, "_is_local_unit") ~= true then
		if type(extension) == "table" then
			charge_state[extension] = nil
		end

		return false
	end

	local ability_is_equipped = extension.ability_is_equipped
	local remaining_ability_charges = extension.remaining_ability_charges

	if type(ability_is_equipped) ~= "function"
		or type(remaining_ability_charges) ~= "function" then
		charge_state[extension] = nil

		return false
	end

	local ability = ability_is_equipped(extension, ABILITY_TYPE)

	if type(ability) ~= "table"
		or rawget(ability, "name") ~= ABILITY_NAME then
		charge_state[extension] = nil

		return false
	end

	local charges = remaining_ability_charges(extension, ABILITY_TYPE)

	if type(charges) ~= "number" then
		charge_state[extension] = nil

		return false
	end

	local previous_charges = charge_state[extension]

	-- The first valid observation is deliberately silent so joining, spawning,
	-- reconnecting, or equipping a ready stimm cannot create a false alert.
	if previous_charges == nil then
		charge_state[extension] = charges

		return false
	end

	-- Commit the observation before audio playback. A failing audio call must not
	-- replay the same transition every fixed frame or auto-quarantine the module.
	charge_state[extension] = charges

	if previous_charges > 0 or charges <= 0 then
		return false
	end

	runtime:record_hit(self.id)

	local managers = rawget(_G, "Managers")
	local ui = type(managers) == "table" and rawget(managers, "ui")

	if type(ui) ~= "table" or type(ui.play_2d_sound) ~= "function" then
		return false
	end

	ui:play_2d_sound(READY_SOUND)
	runtime:record_action(self.id)

	return true
end

function module:_after_fixed_update(extension)
	if not runtime:is_active(self.id) then
		if type(extension) == "table" then
			self._charges_by_extension[extension] = nil
		end

		return
	end

	runtime:run(self.id, self._observe_charge, self, extension)
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local hook_ok = runtime:install_hook(
		self.id,
		TARGET_PATH,
		"fixed_update",
		"safe",
		function (extension)
			self:_after_fixed_update(extension)
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "PlayerUnitAbilityExtension.fixed_update unavailable")
	end
end

function module:on_game_state_changed()
	self:_clear_state()
end

function module:on_setting_changed(setting_id)
	if setting_id == self.setting_id then
		self:_clear_state()
	end
end

function module:on_enabled()
	self:_clear_state()
end

function module:on_disabled()
	self:_clear_state()
end

function module:on_unload()
	self:_clear_state()
end

function module:reset()
	self:_clear_state()
end

function module:runtime_status()
	return runtime:is_active(self.id) and "listening" or "disabled"
end

function module:describe()
	return "plays one stock ready cue when the local Hive Scum syringe regains its charge"
end

return module
