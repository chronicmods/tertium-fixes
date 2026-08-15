local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local SETTINGS_PATH = "scripts/settings/difficulty/danger_settings"
local SELECTOR_PATH = "scripts/ui/view_elements/view_element_mission_board_difficulty_selector/view_element_mission_board_difficulty_selector"
local TRAINING_GROUNDS_CLASS = "TrainingGroundsOptionsView"
local SHOOTING_RANGE = "shooting_range"
local DEFAULT_DANGER = 3

local danger_settings

local module = {
	id = "training_grounds_danger_index_guard",
	label = "Shooting-range danger index guard",
	setting_id = "training_grounds_danger_index_guard_enabled",
}

local function _raw_class_name(value)
	if type(value) ~= "table" or rawget(value, "__deleted") == true then
		return nil
	end

	local direct_name = rawget(value, "__class_name")

	if direct_name ~= nil then
		return direct_name
	end

	local metatable = getmetatable(value)

	return type(metatable) == "table"
		and rawget(metatable, "__class_name")
end

local function _finite_number(value)
	local number = type(value) == "number" and value
		or type(value) == "string" and tonumber(value)

	if not number
		or number ~= number
		or number == math.huge
		or number == -math.huge then
		return nil
	end

	return number
end

local function _first_existing_index(settings, count)
	if rawget(settings, DEFAULT_DANGER) ~= nil then
		return DEFAULT_DANGER
	end

	for index = 1, count do
		if rawget(settings, index) ~= nil then
			return index
		end
	end

	return nil
end

local function _normalize_danger(value, settings)
	if type(settings) ~= "table" then
		return nil
	end

	local count = #settings

	if count < 1 then
		return nil
	end

	local number = _finite_number(value)

	if number ~= nil then
		local index = math.floor(number)

		index = math.max(1, math.min(count, index))

		if rawget(settings, index) ~= nil then
			return index
		end
	end

	return _first_existing_index(settings, count)
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local settings_ok = runtime:defer_file(
		self.id,
		SETTINGS_PATH,
		function (returned_settings)
			danger_settings = nil

			if type(returned_settings) ~= "table" or #returned_settings < 1 then
				runtime:set_available(self.id, false, "DangerSettings unavailable after game load")

				return
			end

			danger_settings = returned_settings
		end
	)

	local hook_ok = runtime:install_hook(
		self.id,
		SELECTOR_PATH,
		"initialize_data",
		"normal",
		function (func, selector, optional_difficulty_index)
			if not runtime:is_active(self.id) then
				return func(selector, optional_difficulty_index)
			end

			local parent = selector:parent()
			local exact_scope = _raw_class_name(parent) == TRAINING_GROUNDS_CLASS
				and rawget(parent, "training_grounds_settings") == SHOOTING_RANGE

			if not exact_scope or type(danger_settings) ~= "table" then
				return func(selector, optional_difficulty_index)
			end

			local normalized = _normalize_danger(
				optional_difficulty_index,
				danger_settings
			)

			if normalized == nil then
				return func(selector, optional_difficulty_index)
			end

			if normalized ~= optional_difficulty_index then
				runtime:record_hit(self.id)
				runtime:record_action(self.id)
			end

			return func(selector, normalized)
		end
	)

	if not settings_ok or not hook_ok then
		runtime:set_available(
			self.id,
			false,
			"DangerSettings or difficulty selector unavailable"
		)
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "normalizing" or "disabled"
end

function module:describe()
	return "normalizes only shooting-range danger values before selector setup"
end

return module
