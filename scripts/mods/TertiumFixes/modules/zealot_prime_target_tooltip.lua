local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "zealot_prime_target_tooltip",
	label = "Prime Target tactical-overlay text",
	setting_id = "zealot_prime_target_tooltip_enabled",
	_template = nil,
	_buff_templates = nil,
	_talent_templates = nil,
	_original = nil,
	_replacement = nil,
}

local BUFF_TEMPLATE_PATH = "scripts/settings/buff/archetype_buff_templates/zealot_buff_templates"
local TALENT_TEMPLATE_PATH = "scripts/settings/ability/archetype_talents/talents/zealot_talents"
local PARENT_KEY = "zealot_elite_kills_empowers"
local EFFECT_KEY = "zealot_elite_kills_empowers_effect"
local TALENT_KEY = "zealot_elite_kills_empowers"

function module:_restore()
	if self._template
		and self._template.related_talents == self._replacement then
		self._template.related_talents = self._original
	end

	self._replacement = nil
end

function module:_apply()
	if self._replacement then
		return true
	end

	local template = self._template

	if type(template) ~= "table" then
		return false
	end

	if template.class_name ~= "buff"
		or template.related_talents ~= nil
		or template.predicted ~= false
		or template.refresh_duration_on_stack ~= true
		or type(template.duration) ~= "number"
		or type(template.max_stacks) ~= "number" then
		runtime:set_available(
			self.id,
			false,
			"exact 1.12.3 Prime Target effect metadata no longer matches"
		)

		return false
	end

	local replacement = {
		TALENT_KEY,
	}

	self._original = template.related_talents
	self._replacement = replacement
	template.related_talents = replacement

	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	return true
end

function module:_finalize_templates()
	local templates = self._buff_templates
	local archetype_talents = self._talent_templates

	if templates == nil or archetype_talents == nil then
		return
	end

	local talent = type(archetype_talents.talents) == "table"
		and archetype_talents.talents[TALENT_KEY]

	if type(templates[PARENT_KEY]) ~= "table"
		or type(templates[EFFECT_KEY]) ~= "table"
		or type(talent) ~= "table"
		or type(talent.passive) ~= "table"
		or talent.passive.buff_template_name ~= PARENT_KEY then
		runtime:set_available(self.id, false, "Prime Target templates unavailable after game load")

		return
	end

	self._template = templates[EFFECT_KEY]

	if runtime:is_active(self.id) then
		self:_apply()
	end
end

function module:install()
	local buffs_ok = runtime:defer_file(self.id, BUFF_TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(self.id, false, "Prime Target buff templates unavailable after game load")

			return
		end

		self._buff_templates = templates
		self:_finalize_templates()
	end)
	local talents_ok = runtime:defer_file(self.id, TALENT_TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(self.id, false, "Prime Target talent templates unavailable after game load")

			return
		end

		self._talent_templates = templates
		self:_finalize_templates()
	end)

	if not buffs_ok or not talents_ok then
		runtime:set_available(self.id, false, "Prime Target deferred templates unavailable")
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
	return self._replacement and "patched" or "inactive"
end

function module:describe()
	return "guarded talent-link metadata repair on the exact Prime Target effect buff"
end

return module
