local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local TARGET_PATH = "scripts/extension_systems/proximity/side_relation_gameplay_logic/proximity_broker_stimm_field"

local module = {
	id = "stimm_field_deleted_extension_guard",
	label = "Stimm field deleted-extension guard",
	setting_id = "stimm_field_deleted_extension_guard_enabled",
}

local function _is_exact_deleted_extension(value)
	return type(value) == "table" and rawget(value, "__deleted") == true
end

local function _row_extension(broker, list_name, unit)
	local units = type(broker) == "table" and rawget(broker, list_name)
	local row = type(units) == "table" and rawget(units, unit)

	return type(row) == "table" and rawget(row, "buff_extension"), units
end

function module:_discard_deleted_row(broker, unit)
	if unit == nil then
		return false
	end

	local extension, units = _row_extension(broker, "_units_in_proximity", unit)

	if not _is_exact_deleted_extension(extension) then
		return false
	end

	-- Local buff IDs belong to this extension, so they cannot be used again
	-- after the extension has been destroyed.
	units[unit] = nil

	local lingering = rawget(broker, "_lingering_units")

	if type(lingering) == "table" then
		local lingering_extension = _row_extension(broker, "_lingering_units", unit)

		if not lingering_extension or lingering_extension == extension then
			lingering[unit] = nil
		end
	end

	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	return true
end

function module:_discard_old_linger(broker, unit)
	if unit == nil then
		return
	end

	local extension, lingering = _row_extension(broker, "_lingering_units", unit)

	if _is_exact_deleted_extension(extension) then
		-- Let the normal add path make new buffs on the current extension.
		lingering[unit] = nil
		runtime:record_hit(self.id)
		runtime:record_action(self.id)
	end
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local remove_ok = runtime:install_hook(
		self.id,
		TARGET_PATH,
		"_remove_buff_from_unit",
		"normal",
		function (func, broker, t, unit)
			if runtime:is_active(self.id) and self:_discard_deleted_row(broker, unit) then
				return
			end

			return func(broker, t, unit)
		end
	)
	local add_ok = runtime:install_hook(
		self.id,
		TARGET_PATH,
		"_add_buff_to_unit",
		"normal",
		function (func, broker, t, unit)
			if runtime:is_active(self.id) then
				self:_discard_old_linger(broker, unit)
			end

			return func(broker, t, unit)
		end
	)
	local linger_ok = runtime:install_hook(
		self.id,
		TARGET_PATH,
		"_make_linger",
		"normal",
		function (func, broker, unit, t, linger_time)
			if runtime:is_active(self.id) and self:_discard_deleted_row(broker, unit) then
				return
			end

			return func(broker, unit, t, linger_time)
		end
	)

	if not remove_ok or not add_ok or not linger_ok then
		runtime:set_available(self.id, false, "stimm field buff methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "removes old stimm buff IDs when their extension is destroyed, including leaving and re-entering the field"
end

return module
