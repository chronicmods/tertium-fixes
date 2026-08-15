local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local InputDevice
local INPUT_DEVICE_PATH = "scripts/managers/input/input_device"

local module = {
	id = "input_device_handoff",
	label = "Same-frame input-device handoff",
	setting_id = "input_device_handoff_enabled",
}

local function _needs_reconciliation(input_manager)
	if type(input_manager) ~= "table" or type(InputDevice) ~= "table" then
		return false
	end

	local selection = input_manager._selection
	local selection_logic = input_manager.SELECTION_LOGIC
	local used_devices = input_manager._used_input_devices
	local update_selection = input_manager._update_selection

	if type(selection) ~= "table"
		or type(selection_logic) ~= "table"
		or type(used_devices) ~= "table"
		or type(update_selection) ~= "function" then
		return false
	end

	local latest_logic = selection_logic.latest
	local latest_device = InputDevice.last_pressed_device

	if latest_logic == nil
		or selection.logic ~= latest_logic
		or latest_device == nil then
		return false
	end

	local device_count = 0
	local highest_index = 0

	for index, device in pairs(used_devices) do
		if type(index) ~= "number"
			or index < 1
			or index % 1 ~= 0
			or device == nil then
			return false
		end

		device_count = device_count + 1
		highest_index = math.max(highest_index, index)

		if device == latest_device then
			return false
		end
	end

	return device_count == highest_index, update_selection
end

function module:_after_devices_updated(input_manager)
	if not runtime:is_active(self.id) then
		return
	end

	local needs_reconciliation, update_selection = _needs_reconciliation(input_manager)

	if not needs_reconciliation then
		return
	end

	runtime:record_hit(self.id)

	local ok = runtime:run(self.id, update_selection, input_manager)

	if ok then
		runtime:record_action(self.id)
	end
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local device_ok = runtime:defer_file(
		self.id,
		INPUT_DEVICE_PATH,
		function (input_device)
			if type(input_device) ~= "table" then
				runtime:set_available(self.id, false, "InputDevice unavailable after game load")

				return
			end

			InputDevice = input_device
		end
	)

	local hook_ok = runtime:install_hook(
		self.id,
		"scripts/managers/input/input_manager",
		"_update_devices",
		"safe",
		function (input_manager)
			self:_after_devices_updated(input_manager)
		end
	)

	if not device_ok or not hook_ok then
		runtime:set_available(self.id, false, "InputManager device update unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "reconciling" or "disabled"
end

function module:describe()
	return "selects a newly active device before service updates"
end

return module
