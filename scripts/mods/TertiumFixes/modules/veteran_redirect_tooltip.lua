local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "veteran_redirect_tooltip",
	label = "Redirect Fire description link",
	setting_id = "veteran_redirect_tooltip_enabled",
	_templates = nil,
	_patches = {},
}

local TEMPLATE_PATH = "scripts/settings/buff/archetype_buff_templates/veteran_buff_templates"
local OLD_TALENT = "veteran_improved_tag_dead_bonus"
local NEW_TALENT = "veteran_improved_tag_dead_coherency_bonus"
local TARGET_KEYS = {
	"veteran_improved_tag_allied_buff",
	"veteran_improved_tag_allied_buff_increased_stacks",
}

local function _clone_related_talents(source)
	local clone = {}

	for key, value in pairs(source) do
		clone[key] = value
	end

	clone[1] = NEW_TALENT

	return clone
end

function module:_restore()
	for i = #self._patches, 1, -1 do
		local patch = self._patches[i]

		if patch.template.related_talents == patch.replacement then
			patch.template.related_talents = patch.original
		end
	end

	self._patches = {}
end

function module:_apply()
	if #self._patches > 0 then
		return true
	end

	if type(self._templates) ~= "table" then
		return false
	end

	local targets = {}

	for i = 1, #TARGET_KEYS do
		local key = TARGET_KEYS[i]
		local template = self._templates[key]
		local related = type(template) == "table" and template.related_talents

		if type(related) ~= "table"
			or #related ~= 1
			or related[1] ~= OLD_TALENT then
			runtime:set_available(
				self.id,
				false,
				"exact 1.12.3 Redirect Fire metadata no longer matches"
			)

			return false
		end

		targets[#targets + 1] = {
			template = template,
			original = related,
		}
	end

	for i = 1, #targets do
		local target = targets[i]
		local replacement = _clone_related_talents(target.original)

		target.template.related_talents = replacement
		self._patches[#self._patches + 1] = {
			template = target.template,
			original = target.original,
			replacement = replacement,
		}
	end

	runtime:record_hit(self.id, #targets)
	runtime:record_action(self.id, #targets)

	return true
end

function module:install()
	runtime:defer_file(self.id, TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(self.id, false, "Veteran buff templates unavailable after game load")

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
	return #self._patches > 0 and "patched" or "inactive"
end

function module:describe()
	return "guarded metadata-only correction on two exact buff templates"
end

return module
