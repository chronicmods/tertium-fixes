local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "cursor_stack",
	label = "Cursor stack repair",
	setting_id = "cursor_stack_enabled",
}

local function _repair_cursor_stack(self)
	local cursor_stack_data = self and self._cursor_stack_data

	if type(cursor_stack_data) ~= "table" then
		return false
	end

	local stack_references = cursor_stack_data.stack_references

	if type(stack_references) ~= "table" then
		return false
	end

	local actual_depth = 0

	for _, present in pairs(stack_references) do
		if present then
			actual_depth = actual_depth + 1
		end
	end

	local previous_depth = tonumber(cursor_stack_data.stack_depth) or 0
	local allow_cursor_rendering = cursor_stack_data.allow_cursor_rendering == true
	local cursor_should_be_visible = actual_depth > 0 and allow_cursor_rendering
	local is_windows = rawget(_G, "IS_WINDOWS") == true
	local is_xbs = rawget(_G, "IS_XBS") == true
	local changed = previous_depth ~= actual_depth

	cursor_stack_data.stack_depth = actual_depth

	if is_windows then
		changed = changed or self._show_cursor ~= cursor_should_be_visible
		self._show_cursor = cursor_should_be_visible
	elseif is_xbs then
		changed = changed or self._software_cursor_active ~= cursor_should_be_visible
		self._software_cursor_active = cursor_should_be_visible
	end

	if changed and is_windows and type(self._update_clip_cursor) == "function" then
		self:_update_clip_cursor()
	end

	return changed
end

function module:_after_cursor_change(input_manager)
	if not runtime:is_active(self.id) then
		return
	end

	runtime:record_hit(self.id)

	local ok, changed = runtime:run(self.id, _repair_cursor_stack, input_manager)

	if ok and changed then
		runtime:record_action(self.id)
	end
end

function module:install()
	local class_path = "scripts/managers/input/input_manager"

	local push_ok = runtime:install_hook(self.id, class_path, "push_cursor", "safe", function (input_manager)
		self:_after_cursor_change(input_manager)
	end)

	local pop_ok = runtime:install_hook(self.id, class_path, "pop_cursor", "safe", function (input_manager)
		self:_after_cursor_change(input_manager)
	end)

	if not push_ok or not pop_ok then
		runtime:set_available(self.id, false, "InputManager cursor methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "reconciles truthy references after push/pop"
end

return module
