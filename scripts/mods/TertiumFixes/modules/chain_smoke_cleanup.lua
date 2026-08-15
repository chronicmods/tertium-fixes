local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "chain_smoke_cleanup",
	label = "Aggressive chain-weapon smoke cleanup",
	setting_id = "chain_smoke_cleanup_enabled",
}

local function _capture_stopping_effect(effects)
	if type(effects) ~= "table"
		or type(effects._looping_effect_id) ~= "function"
		or type(effects._inventory_slot_component) ~= "table"
		or effects._inventory_slot_component.special_active ~= false then
		return nil
	end

	return effects:_looping_effect_id()
end

local function _destroy_released_effect(effects, effect_id)
	if type(effects) ~= "table"
		or World == nil
		or type(World.are_particles_playing) ~= "function"
		or type(World.destroy_particles) ~= "function"
		or effects._world == nil
		or effect_id == nil
		or type(effects._looping_effect_id) ~= "function"
		or effects:_looping_effect_id() ~= nil then
		return false
	end

	if World.are_particles_playing(effects._world, effect_id) then
		World.destroy_particles(effects._world, effect_id)

		return true
	end

	return false
end

function module:install()
	local owner = self
	local hook_ok = runtime:install_hook(
		self.id,
		"scripts/extension_systems/visual_loadout/wieldable_slot_scripts/chain_weapon_effects",
		"_update_active",
		"hook",
		function (func, effects, ...)
			local effect_id

			if runtime:is_active(owner.id) then
				local ok, captured_effect_id = runtime:run(
					owner.id,
					_capture_stopping_effect,
					effects
				)

				if ok then
					effect_id = captured_effect_id
				end
			end

			-- Preserve weapon_special_end: the original transition runs first.
			-- This optional workaround then hard-stops that exact just-released
			-- handle before it can be recycled. It intentionally trades the
			-- normal particle tail for eliminating persistent smoke.
			func(effects, ...)

			if effect_id ~= nil and runtime:is_active(owner.id) then
				local ok, destroyed = runtime:run(
					owner.id,
					_destroy_released_effect,
					effects,
					effect_id
				)

				if ok and destroyed then
					runtime:record_hit(owner.id)
					runtime:record_action(owner.id)
				end
			end
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "ChainWeaponEffects._update_active unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "aggressive hard-stop enabled" or "disabled"
end

function module:describe()
	return "opt-in: removes the normal particle tail"
end

return module
