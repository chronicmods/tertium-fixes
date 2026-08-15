local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "localization_guard",
	label = "Localization guard",
	setting_id = "localization_guard_enabled",
}

local localize_states = setmetatable({}, {
	__mode = "k",
})

local function _invalid_key_fallback(key)
	if runtime:get("localization_fallback_mode") == "blank" then
		return ""
	end

	if key == nil then
		return "<missing localization key>"
	end

	return "<invalid localization key: " .. type(key) .. ">"
end

local function _invalid_value_fallback(raw_str)
	if runtime:get("localization_fallback_mode") == "blank" then
		return ""
	end

	return "<invalid localized value: " .. type(raw_str) .. ">"
end

local function _begin_localize(localization_manager, key)
	local state = localize_states[localization_manager]

	if state == nil then
		state = {
			depth = 0,
			fallbacks = {},
			keys = {},
		}
		localize_states[localization_manager] = state
	end

	local depth = state.depth + 1

	state.depth = depth
	state.keys[depth] = key
	state.fallbacks[depth] = nil

	return state, depth
end

local function _finish_localize(localization_manager, state, depth)
	local key = state.keys[depth]
	local invalid_fallback = state.fallbacks[depth]

	if invalid_fallback ~= nil then
		local string_cache = localization_manager._string_cache

		-- LocalizationManager.localize caches the value returned by _process_string.
		-- Remove only the exact temporary fallback produced by this invocation.
		if type(string_cache) == "table" and string_cache[key] == invalid_fallback then
			string_cache[key] = nil
		end
	end

	state.keys[depth] = nil
	state.fallbacks[depth] = nil
	state.depth = depth - 1
end

local function _mark_invalid_fallback(localization_manager, key, fallback)
	local state = localize_states[localization_manager]
	local depth = state and state.depth or 0

	if depth > 0 and state.keys[depth] == key then
		state.fallbacks[depth] = fallback
	end
end

function module:install()
	local localize_ok = runtime:install_hook(
		self.id,
		"scripts/managers/localization/localization_manager",
		"localize",
		"normal",
		function (func, localization_manager, key, no_cache, context)
			if not runtime:is_active(self.id) then
				return func(localization_manager, key, no_cache, context)
			end

			if type(key) ~= "string" or key == "" then
				runtime:record_hit(self.id)
				runtime:record_action(self.id)

				return _invalid_key_fallback(key)
			end

			local state, depth = _begin_localize(localization_manager, key)
			local localized_string = func(localization_manager, key, no_cache, context)

			_finish_localize(localization_manager, state, depth)

			return localized_string
		end
	)

	local process_ok = runtime:install_hook(
		self.id,
		"scripts/managers/localization/localization_manager",
		"_process_string",
		"normal",
		function (func, localization_manager, key, raw_str, context)
			if not runtime:is_active(self.id) then
				return func(localization_manager, key, raw_str, context)
			end

			if type(raw_str) ~= "string" then
				runtime:record_hit(self.id)
				runtime:record_action(self.id)

				local fallback = _invalid_value_fallback(raw_str)

				_mark_invalid_fallback(localization_manager, key, fallback)

				return fallback
			end

			return func(localization_manager, key, raw_str, context)
		end
	)

	if not localize_ok or not process_ok then
		runtime:set_available(self.id, false, "LocalizationManager methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "guards invalid keys and non-string raw values"
end

return module
