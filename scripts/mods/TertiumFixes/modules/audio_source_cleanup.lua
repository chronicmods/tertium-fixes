local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "audio_source_cleanup",
	label = "Manual audio-source teardown repair",
	setting_id = "audio_source_cleanup_enabled",
	_warned = {},
	_dialogue_manual_sources = setmetatable({}, { __mode = "k" }),
}

local HOOKS = {
	{
		path = "scripts/extension_systems/dialogue/dialogue_extension",
		method = "destroy",
		world = function (owner)
			return type(owner) == "table"
				and rawget(owner, "_wwise_world")
		end,
		field = "_wwise_source_id",
		tracked_dialogue_source = true,
	},
	{
		path = "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects",
		method = "destroy",
		world = function (owner)
			return type(owner) == "table"
				and rawget(owner, "_wwise_world")
		end,
		field = "_source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/renegade_flamer_mutator_throw",
		method = "stop",
		world = function (_, template_context)
			return type(template_context) == "table"
				and rawget(template_context, "wwise_world")
		end,
		field = "source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/cultist_mutant_charge_foley",
		method = "stop",
		world = function (_, template_context)
			return type(template_context) == "table"
				and rawget(template_context, "wwise_world")
		end,
		field = "source_id",
	},
	{
		path = "scripts/settings/fx/effect_templates/chaos_poxwalker_bomber_foley",
		method = "stop",
		world = function (_, template_context)
			return type(template_context) == "table"
				and rawget(template_context, "wwise_world")
		end,
		field = "source_id",
	},
}

function module:_warn_once(key, message)
	if self._warned[key] then
		return
	end

	self._warned[key] = true
	mod:warning("[audio_source_cleanup] %s", message)
end

function module:_source_for_spec(spec, owner)
	if spec.tracked_dialogue_source then
		return self._dialogue_manual_sources[owner]
	end

	return rawget(owner, spec.field)
end

function module:_clear_source_for_spec(spec, owner, source_id)
	if spec.tracked_dialogue_source then
		self._dialogue_manual_sources[owner] = nil

		if rawget(owner, spec.field) == source_id then
			owner[spec.field] = nil
		end

		return
	end

	owner[spec.field] = nil
end

function module:_destroy_source(wwise_world, owner, spec)
	if type(owner) ~= "table" then
		return false, 0, false
	end

	local source_id = self:_source_for_spec(spec, owner)

	if source_id == nil then
		return true, 0, false
	end

	if wwise_world == nil then
		self:_warn_once(
			spec.field .. ":world",
			"Wwise world was unavailable during source teardown"
		)

		return false, 0, true
	end

	local wwise_api = rawget(_G, "WwiseWorld")
	local has_source = type(wwise_api) == "table"
		and wwise_api.has_source
	local destroy_source = type(wwise_api) == "table"
		and wwise_api.destroy_manual_source

	if type(has_source) ~= "function"
		or type(destroy_source) ~= "function" then
		self:_warn_once(
			spec.field .. ":api",
			"Wwise manual-source API was unavailable during teardown"
		)

		return false, 0, true
	end

	local queried, exists = pcall(has_source, wwise_world, source_id)

	if not queried then
		self:_warn_once(
			spec.field .. ":query",
			"Wwise source lookup failed during teardown"
		)

		return false, 0, true
	end

	if not exists then
		self:_clear_source_for_spec(spec, owner, source_id)

		return true, 0, true
	end

	local destroyed = pcall(destroy_source, wwise_world, source_id)

	if not destroyed then
		self:_warn_once(
			spec.field .. ":destroy",
			"Wwise source destruction failed during teardown"
		)

		return false, 0, true
	end

	self:_clear_source_for_spec(spec, owner, source_id)

	return true, 1, true
end

function module:_after_stop(spec, owner, template_context)
	if not runtime:is_active(self.id) then
		return
	end

	local ok, complete, actions, found = runtime:run(
		self.id,
		self._destroy_source,
		self,
		spec.world(owner, template_context),
		owner,
		spec
	)

	if ok and complete and found then
		runtime:record_hit(self.id)

		if actions > 0 then
			runtime:record_action(self.id, actions)
		end
	end
end

function module:_track_dialogue_source(func, owner, ...)
	local before_source = type(owner) == "table"
		and rawget(owner, "_wwise_source_id")
	local result = func(owner, ...)

	if before_source == nil and type(owner) == "table" then
		local created_source = rawget(owner, "_wwise_source_id")

		if created_source ~= nil then
			self._dialogue_manual_sources[owner] = created_source
		end
	end

	return result
end

function module:_install_spec(spec)
	return runtime:install_hook(
		self.id,
		spec.path,
		spec.method,
		"safe",
		function (owner, template_context)
			self:_after_stop(spec, owner, template_context)
		end
	)
end

function module:install()
	local track_ok = runtime:install_hook(
		self.id,
		"scripts/extension_systems/dialogue/dialogue_extension",
		"extensions_ready",
		"normal",
		function (func, owner, ...)
			return self:_track_dialogue_source(func, owner, ...)
		end
	)

	if not track_ok then
		runtime:set_available(
			self.id,
			false,
			"dialogue manual-source ownership hook was unavailable"
		)

		return
	end

	for i = 1, #HOOKS do
		local hook_ok = self:_install_spec(HOOKS[i])

		if not hook_ok then
			runtime:set_available(
				self.id,
				false,
				"one or more manual-source hooks were unavailable"
			)

			return
		end
	end
end

function module:reset()
	self._warned = {}
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "releases five source-confirmed manual Wwise handles while preserving auto-source ownership"
end

return module
