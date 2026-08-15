local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "gas_outline_recovery",
	label = "Toxic-gas outline recovery after death",
	setting_id = "gas_outline_recovery_enabled",
	_templates = nil,
	_records = {},
}

local TEMPLATE_PATH = "scripts/settings/buff/liquid_area_buff_templates"
local TEMPLATE_NAMES = {
	"in_toxic_gas",
	"in_cultist_grenadier_gas",
	"in_twin_toxic_gas",
	"in_buildup_twin_toxic_gas",
}

local function _is_dead_local_player(template_context)
	if type(template_context) ~= "table"
		or template_context.is_local_unit ~= true
		or template_context.is_player ~= true then
		return false
	end

	local unit = template_context.unit
	local health_alive = rawget(_G, "HEALTH_ALIVE")

	return unit ~= nil
		and type(health_alive) == "table"
		and not health_alive[unit]
end

function module:_restore_outlines(template_context)
	if not _is_dead_local_player(template_context) then
		return
	end

	local managers = rawget(_G, "Managers")
	local state = managers and managers.state
	local extension_manager = state and state.extension

	if not extension_manager or type(extension_manager.system) ~= "function" then
		return
	end

	local outline_system = extension_manager:system("outline_system")

	if not outline_system or type(outline_system.set_global_visibility) ~= "function" then
		return
	end

	outline_system:set_global_visibility(true)
	runtime:record_action(self.id)
end

function module:_make_wrapper(template_name, original)
	return function (template_data, template_context, ...)
		local a, b, c, d = original(template_data, template_context, ...)

		if runtime:is_active(self.id) then
			runtime:record_hit(self.id)
			runtime:run(
				self.id,
				self._restore_outlines,
				self,
				template_context
			)
		end

		return a, b, c, d
	end
end

function module:_restore()
	for i = 1, #self._records do
		local record = self._records[i]

		if record.template.stop_func == record.wrapper then
			record.template.stop_func = record.original
		end
	end

	self._records = {}
end

function module:_apply()
	if #self._records > 0 then
		return true
	end

	local templates = self._templates
	local staged = {}

	for i = 1, #TEMPLATE_NAMES do
		local template_name = TEMPLATE_NAMES[i]
		local template = templates and templates[template_name]

		if type(template) ~= "table"
			or template.class_name ~= "interval_buff"
			or type(template.start_func) ~= "function"
			or type(template.stop_func) ~= "function"
			or type(template.player_effects) ~= "table"
			or template.player_effects.looping_wwise_start_event ~= "wwise/events/player/play_player_gas_enter"
			or template.player_effects.looping_wwise_stop_event ~= "wwise/events/player/play_player_gas_exit" then
			runtime:set_available(
				self.id,
				false,
				"exact 1.12.3 toxic-gas buff shape no longer matches"
			)

			return false
		end

		local original = template.stop_func

		staged[#staged + 1] = {
			name = template_name,
			template = template,
			original = original,
			wrapper = self:_make_wrapper(template_name, original),
		}
	end

	for i = 1, #staged do
		local record = staged[i]

		record.template.stop_func = record.wrapper
		self._records[#self._records + 1] = record
	end

	return true
end

function module:install()
	runtime:defer_file(self.id, TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(self.id, false, "liquid-area buff templates unavailable after game load")

			return
		end

		self._templates = templates

		if runtime:is_active(self.id) then
			self:_apply()
		end
	end)
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
	return #self._records == #TEMPLATE_NAMES and "patched" or "inactive"
end

function module:describe()
	return "restores global outlines only when an exact toxic-gas buff stops on the dead local player"
end

return module
