local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "servo_skull_scroll",
	label = "Servo-Skull scroll isolation",
	setting_id = "servo_skull_scroll_enabled",
	_template = nil,
	_constants = nil,
	_original_inputs = nil,
	_replacement_inputs = nil,
}

local TEMPLATE_PATH = "scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point"
local CONSTANTS_PATH = "scripts/settings/player_character/player_character_constants"

function module:_current_inputs()
	local wield = self._template
		and self._template.action_inputs
		and self._template.action_inputs.wield
	local first_step = wield
		and type(wield.input_sequence) == "table"
		and wield.input_sequence[1]

	return type(first_step) == "table" and first_step.inputs, first_step
end

function module:_restore()
	local current, first_step = self:_current_inputs()

	if first_step and current == self._replacement_inputs then
		first_step.inputs = self._original_inputs
	end

	self._replacement_inputs = nil
end

function module:_apply()
	if self._replacement_inputs then
		return true
	end

	local inputs, first_step = self:_current_inputs()

	if type(inputs) ~= "table"
		or type(first_step) ~= "table"
		or inputs ~= self._original_inputs then
		runtime:set_available(self.id, false, "exact Servo-Skull wield-input table no longer matches")

		return false
	end

	local replacement = {}
	local removed = 0

	for index = 1, #inputs do
		local entry = inputs[index]
		local input_name = type(entry) == "table" and entry.input

		if input_name == "wield_scroll_up" or input_name == "wield_scroll_down" then
			removed = removed + 1
		else
			replacement[#replacement + 1] = entry
		end
	end

	if removed ~= 2 or #replacement ~= #inputs - 2 then
		runtime:set_available(self.id, false, "expected two Servo-Skull scroll inputs were not found")

		return false
	end

	first_step.inputs = replacement
	self._replacement_inputs = replacement
	runtime:record_hit(self.id, removed)
	runtime:record_action(self.id)

	return true
end

function module:_finalize_templates()
	local template = self._template
	local constants = self._constants

	if template == nil or constants == nil then
		return
	end

	local inputs

	inputs = self:_current_inputs()

	if type(constants.wield_inputs) ~= "table"
		or inputs ~= constants.wield_inputs
		or template.not_scroll_wieldable ~= true then
		runtime:set_available(self.id, false, "exact Servo-Skull template/constants link unavailable after game load")

		return
	end

	self._original_inputs = inputs

	if runtime:is_active(self.id) then
		self:_apply()
	end
end

function module:install()
	local template_ok = runtime:defer_file(self.id, TEMPLATE_PATH, function (template)
		if type(template) ~= "table" then
			runtime:set_available(self.id, false, "Servo-Skull template unavailable after game load")

			return
		end

		self._template = template
		self:_finalize_templates()
	end)
	local constants_ok = runtime:defer_file(self.id, CONSTANTS_PATH, function (constants)
		if type(constants) ~= "table" then
			runtime:set_available(self.id, false, "player-character constants unavailable after game load")

			return
		end

		self._constants = constants
		self:_finalize_templates()
	end)

	if not template_ok or not constants_ok then
		runtime:set_available(self.id, false, "Servo-Skull deferred templates unavailable")
	end
end

function module:on_setting_changed(setting_id)
	if setting_id ~= self.setting_id then
		return
	end

	if runtime:mod_is_enabled() and runtime:get(self.setting_id) == true then
		self:_apply()
	else
		self:_restore()
	end
end

function module:on_enabled()
	if runtime:get(self.setting_id) == true then
		self:_apply()
	end
end

function module:on_disabled()
	self:_restore()
end

function module:on_unload()
	self:_restore()
end

function module:runtime_status()
	if self._replacement_inputs then
		return "prototype active"
	end

	return runtime:get(self.setting_id) == true and "ready" or "opt-in disabled"
end

function module:describe()
	return "private clone; shared PlayerCharacterConstants remains untouched"
end

return module
