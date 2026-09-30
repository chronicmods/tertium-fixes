local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "weapon_effect_transitions",
	label = "Weapon effects on camera changes",
	setting_id = "weapon_effect_transitions_enabled",
	_tox_sources = setmetatable({}, { __mode = "k" }),
	_pending_lockout_stops = setmetatable({}, { __mode = "k" }),
}

local SCRIPT_PATH = "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/"
local STAGES = { low = true, middle = true, high = true }

local function stop_playing(wwise_world, playing_id)
	if wwise_world == nil or playing_id == nil then
		return false
	end

	local api = rawget(_G, "WwiseWorld")
	local stop = type(api) == "table" and api.stop_event

	return type(stop) == "function" and pcall(stop, wwise_world, playing_id)
end

local function tox_source(effects)
	local fx = rawget(effects, "_fx_extension")

	if type(fx) ~= "table" or rawget(fx, "__deleted") == true then
		return nil
	end

	local source_name = rawget(effects, "_sfx_source_name")

	if source_name == nil or type(fx.sound_source) ~= "function" then
		return nil
	end

	local ok, source = pcall(fx.sound_source, fx, source_name)

	return ok and source or nil
end

function module:_stop_lockout(effects)
	if type(effects) ~= "table" then
		return
	end

	local playing_id = rawget(effects, "_looping_lockout_playing_id")

	if stop_playing(rawget(effects, "_wwise_world"), playing_id) then
		effects._looping_lockout_playing_id = nil
		effects._looping_lockout_stop_event_name = nil
		self._pending_lockout_stops[effects] = nil
		runtime:record_hit(self.id)
		runtime:record_action(self.id)
	elseif playing_id ~= nil then
		self._pending_lockout_stops[effects] = playing_id
	end
end

function module:_remember_tox_source(effects)
	if type(effects) ~= "table" then
		return
	end

	local playing_id = rawget(effects, "_sfx_loop_id")
	local source = playing_id ~= nil and tox_source(effects)

	if source ~= nil then
		self._tox_sources[effects] = {
			playing_id = playing_id,
			source = source,
			world = rawget(effects, "_wwise_world"),
		}
	else
		self._tox_sources[effects] = nil
	end
end

function module:_stop_moved_tox_loop(effects)
	local record = self._tox_sources[effects]

	if not record then
		return false
	elseif rawget(effects, "_sfx_loop_id") ~= record.playing_id then
		self._tox_sources[effects] = nil
		return false
	end

	local current_source = tox_source(effects)

	if current_source == nil or current_source == record.source then
		return false
	end

	-- The stop event would use the new source. Stop the old playing ID before
	-- the stock code clears it, leaving shared sound sources alone.
	if not stop_playing(record.world, record.playing_id) then
		return false
	end

	effects._sfx_loop_id = nil
	effects._stop_event_name = nil
	self._tox_sources[effects] = nil
	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	return true
end

function module:_move_tox_loop(effects)
	if type(effects) ~= "table" or not self:_stop_moved_tox_loop(effects) then
		return
	end

	-- Visual loadout moves sources after the camera callback. Its normal update
	-- reaches this point afterwards, so the replacement loop uses the new source.
	effects:_stop_vfx_loop(true)
	effects:_start_vfx_loop()
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")
		return
	end

	local hooks_ok = true
	local function hook(script, method, kind, callback)
		hooks_ok = runtime:install_hook(self.id, SCRIPT_PATH .. script, method, kind, callback) and hooks_ok
	end

	hook("force_weapon_wind_slash_stage_effects", "update_first_person_mode", "normal", function (func, effects, ...)
		if not runtime:is_active(self.id) or type(effects) ~= "table" then
			return func(effects, ...)
		end

		local stage = rawget(effects, "_current_stage")
		local slot = rawget(effects, "_inventory_slot_component")
		local charges = type(slot) == "table" and slot.num_special_charges
		local a, b, c, d = func(effects, ...)

		if STAGES[stage] and stage ~= "low" and effects._current_stage == "low"
			and type(slot) == "table" and slot.num_special_charges == charges then
			-- A visibility refresh did not add charges. Keep its previous tier so
			-- the next update does not replay the charge gain sound and flash.
			effects._current_stage = stage
			runtime:record_hit(self.id)
			runtime:record_action(self.id)
		end

		return a, b, c, d
	end)

	for _, method in ipairs({ "update_first_person_mode", "destroy" }) do
		hook("power_weapon_overheat_effects", method, "normal", function (func, effects, ...)
			if runtime:is_active(self.id) then
				runtime:run(self.id, self._stop_lockout, self, effects)
			end

			return func(effects, ...)
		end)
	end
	hook("power_weapon_overheat_effects", "_update_lockout_sfx_loop", "normal", function (func, effects, ...)
		local pending_id = self._pending_lockout_stops[effects]

		if pending_id ~= nil and type(effects) == "table" then
			if pending_id == rawget(effects, "_looping_lockout_playing_id") then
				if runtime:is_active(self.id) then
					runtime:run(self.id, self._stop_lockout, self, effects)
				end
			else
				self._pending_lockout_stops[effects] = nil
			end
		end

		return func(effects, ...)
	end)

	hook("tox_grenade_effects", "_start_vfx_loop", "safe", function (effects)
		if runtime:is_active(self.id) then
			runtime:run(self.id, self._remember_tox_source, self, effects)
		end
	end)
	hook("tox_grenade_effects", "_stop_vfx_loop", "normal", function (func, effects, ...)
		if runtime:is_active(self.id) and type(effects) == "table" then
			runtime:run(self.id, self._stop_moved_tox_loop, self, effects)
		end

		local a, b, c, d = func(effects, ...)

		if type(effects) == "table" and rawget(effects, "_sfx_loop_id") == nil then
			self._tox_sources[effects] = nil
		end

		return a, b, c, d
	end)
	hook("tox_grenade_effects", "update", "safe", function (effects)
		if runtime:is_active(self.id) then
			runtime:run(self.id, self._move_tox_loop, self, effects)
		end
	end)

	if not hooks_ok then
		runtime:set_available(self.id, false, "weapon effect methods unavailable")
	end
end

function module:_clear_tracking()
	self._tox_sources = setmetatable({}, { __mode = "k" })
	self._pending_lockout_stops = setmetatable({}, { __mode = "k" })
end

function module:on_setting_changed(setting_id)
	if setting_id == self.setting_id then
		self:_clear_tracking()
	end
end

function module:on_enabled()
	self:_clear_tracking()
end

function module:on_disabled()
	self:_clear_tracking()
end

function module:on_unload()
	self:_clear_tracking()
end

function module:reset()
	self:_clear_tracking()
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "keeps charge tier cues quiet on visibility refreshes and moves chem grenade and power weapon loops with their sound sources"
end

return module
