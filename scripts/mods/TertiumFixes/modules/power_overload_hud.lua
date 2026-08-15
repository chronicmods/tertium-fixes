local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "power_overload_hud",
	label = "Power Overload ally-buff icon",
	setting_id = "power_overload_hud_enabled",
	_templates = nil,
	_patch = nil,
}

local TEMPLATE_PATH = "scripts/settings/buff/archetype_buff_templates/cryptic_buff_templates"
local TARGET_KEY = "cryptic_overload_keystone_allies_buff"
local SOURCE_KEY = "cryptic_overload_keystone_stack"
local PRESENTATION_FIELDS = {
	"always_show_in_hud",
	"hud_icon",
	"hud_icon_gradient_map",
	"hud_priority",
	"related_talents",
}

function module:_restore()
	local patch = self._patch

	if not patch then
		return
	end

	for i = 1, #PRESENTATION_FIELDS do
		local field = PRESENTATION_FIELDS[i]

		if patch.target[field] == patch.applied[field] then
			patch.target[field] = patch.original[field]
		end
	end

	self._patch = nil
end

function module:_apply()
	if self._patch then
		return true
	end

	local target = self._templates and self._templates[TARGET_KEY]
	local source = self._templates and self._templates[SOURCE_KEY]

	if type(target) ~= "table"
		or target.class_name ~= "buff"
		or target.max_stacks ~= 1
		or target.max_stacks_cap ~= 1
		or target.predicted ~= false
		or target.refresh_duration_on_stack ~= true
		or target.duration ~= 8
		or type(source) ~= "table"
		or type(source.hud_icon) ~= "string"
		or type(source.hud_icon_gradient_map) ~= "string"
		or type(source.hud_priority) ~= "number"
		or type(source.related_talents) ~= "table"
		or #source.related_talents ~= 1
		or source.related_talents[1] ~= "cryptic_overload_keystone" then
		runtime:set_available(self.id, false, "exact 1.12.3 Power Overload templates no longer match")

		return false
	end

	for i = 1, #PRESENTATION_FIELDS do
		local field = PRESENTATION_FIELDS[i]

		if target[field] ~= nil then
			runtime:set_available(self.id, false, "Power Overload HUD metadata is already populated")

			return false
		end
	end

	local original = {}
	local applied = {
		always_show_in_hud = true,
		hud_icon = source.hud_icon,
		hud_icon_gradient_map = source.hud_icon_gradient_map,
		hud_priority = source.hud_priority,
		related_talents = {
			source.related_talents[1],
		},
	}

	for i = 1, #PRESENTATION_FIELDS do
		local field = PRESENTATION_FIELDS[i]

		original[field] = target[field]
		target[field] = applied[field]
	end

	self._patch = {
		target = target,
		original = original,
		applied = applied,
	}

	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	return true
end

function module:install()
	runtime:defer_file(self.id, TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(self.id, false, "Cryptic buff templates unavailable after game load")

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
	return self._patch and "patched" or "inactive"
end

function module:describe()
	return "presentation-only metadata on the exact 8-second ally buff"
end

return module
