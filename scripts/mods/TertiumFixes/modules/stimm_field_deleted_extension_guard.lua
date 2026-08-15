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

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local hook_ok = runtime:install_hook(
		self.id,
		TARGET_PATH,
		"_make_linger",
		"normal",
		function (func, broker, unit, t, linger_time)
			if not runtime:is_active(self.id) then
				return func(broker, unit, t, linger_time)
			end

			local units = type(broker) == "table"
				and rawget(broker, "_units_in_proximity")

			if unit == nil or type(units) ~= "table" then
				return func(broker, unit, t, linger_time)
			end

			local row = rawget(units, unit)
			local cached_extension = type(row) == "table"
				and rawget(row, "buff_extension")

			if not _is_exact_deleted_extension(cached_extension) then
				return func(broker, unit, t, linger_time)
			end

			-- The local buff IDs in this row belong to the destroyed extension.
			-- Discard the row instead of replaying those IDs on a new extension.
			runtime:record_hit(self.id)
			rawset(units, unit, nil)

			local lingering = rawget(broker, "_lingering_units")

			if type(lingering) == "table" then
				rawset(lingering, unit, nil)
			end

			runtime:record_action(self.id)
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "ProximityBrokerStimmField._make_linger unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "discards stimm proximity rows whose cached buff extension was destroyed"
end

return module
