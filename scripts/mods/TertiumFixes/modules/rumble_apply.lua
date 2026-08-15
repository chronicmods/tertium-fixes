local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "rumble_apply",
	label = "Controller-rumble state refresh",
	setting_id = "rumble_apply_enabled",
}

local function _apply_wwise_state(input_manager, explicit_value)
	if type(input_manager) ~= "table" then
		return false
	end

	if type(explicit_value) == "boolean" then
		input_manager._user_rumble_state = explicit_value
	end

	if type(input_manager._update_wwise_rumble) ~= "function" then
		return false
	end

	input_manager:_update_wwise_rumble()

	return true
end

function module:_after_state_change(input_manager, explicit_value)
	if not runtime:is_active(self.id) then
		return
	end

	runtime:record_hit(self.id)

	local ok, applied = runtime:run(
		self.id,
		_apply_wwise_state,
		input_manager,
		explicit_value
	)

	if ok and applied then
		runtime:record_action(self.id)
	end
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local class_path = "scripts/managers/input/input_manager"
	local callback_ok = runtime:install_hook(
		self.id,
		class_path,
		"_cb_update_rumble_enabled",
		"safe",
		function (input_manager, value)
			self:_after_state_change(input_manager, value)
		end
	)
	local suppress_ok = runtime:install_hook(
		self.id,
		class_path,
		"start_suppress_wwise_rumble",
		"safe",
		function (input_manager)
			self:_after_state_change(input_manager)
		end
	)
	local unsuppress_ok = runtime:install_hook(
		self.id,
		class_path,
		"stop_suppress_wwise_rumble",
		"safe",
		function (input_manager)
			self:_after_state_change(input_manager)
		end
	)

	if not callback_ok or not suppress_ok or not unsuppress_ok then
		runtime:set_available(self.id, false, "InputManager rumble methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "refreshing" or "disabled"
end

function module:describe()
	return "applies setting and suppression changes to Wwise"
end

return module
