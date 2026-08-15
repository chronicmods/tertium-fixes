local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "player_fx_lifecycle",
	label = "Player FX lifecycle repair",
	setting_id = "player_fx_lifecycle_enabled",
	_warned = {},
}

local RING_BUFFER_LIMIT = 256

function module:_warn_once(key, message)
	if self._warned[key] then
		return
	end

	self._warned[key] = true
	mod:warning("[player_fx_lifecycle] %s", message)
end

function module:_repair_particle_world(fx_extension, world)
	if world ~= nil or type(fx_extension) ~= "table" then
		return world
	end

	local extension_world = rawget(fx_extension, "_world")

	if extension_world == nil then
		return world
	end

	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	return extension_world
end

function module:_cleanup_moving_sfx(fx_extension)
	local moving_sfx = type(fx_extension) == "table"
		and rawget(fx_extension, "_moving_sfx")

	if type(moving_sfx) ~= "table"
		or type(moving_sfx.buffer) ~= "table" then
		return 0
	end

	local size = math.floor(tonumber(moving_sfx.size) or 0)

	if size <= 0 then
		return 0
	end

	size = math.min(size, RING_BUFFER_LIMIT)

	local wwise_world = rawget(fx_extension, "_wwise_world")
	local wwise_api = rawget(_G, "WwiseWorld")
	local cleaned = 0
	local pending = false
	local stop_event = type(wwise_api) == "table"
		and wwise_api.stop_event
	local trigger_resource_event = type(wwise_api) == "table"
		and wwise_api.trigger_resource_event
	local has_source = type(wwise_api) == "table"
		and wwise_api.has_source
	local destroy_source = type(wwise_api) == "table"
		and wwise_api.destroy_manual_source

	if wwise_world == nil then
		self:_warn_once(
			"moving_sfx:world",
			"Wwise world was unavailable during moving-source teardown"
		)

		return 0
	end

	for i = 1, size do
		local data = moving_sfx.buffer[i]

		if type(data) == "table" then
			local playing_id = rawget(data, "playing_id")
			local source_id = rawget(data, "source_id")
			local wwise_stop_event = rawget(data, "wwise_stop_event")

			if playing_id ~= nil then
				if type(stop_event) == "function"
					and pcall(stop_event, wwise_world, playing_id) then
					data.playing_id = nil
					cleaned = cleaned + 1
				else
					self:_warn_once(
						"moving_sfx:stop",
						"a moving sound could not be stopped during teardown"
					)
				end
			end

			if source_id ~= nil then
				local queried = false
				local exists

				if type(has_source) == "function" then
					queried, exists = pcall(
						has_source,
						wwise_world,
						source_id
					)
				end

				if not queried then
					self:_warn_once(
						"moving_sfx:query",
						"a moving source could not be queried during teardown"
					)
				elseif not exists then
					data.playing_id = nil
					data.source_id = nil
					data.wwise_stop_event = nil
					cleaned = cleaned + 1
				else
					if wwise_stop_event ~= nil
						and type(trigger_resource_event) == "function" then
						if not pcall(
							trigger_resource_event,
							wwise_world,
							wwise_stop_event,
							source_id
						) then
							self:_warn_once(
								"moving_sfx:resource_stop",
								"a moving source stop event failed during teardown"
							)
						end
					end

					if type(destroy_source) == "function"
						and pcall(destroy_source, wwise_world, source_id) then
						data.playing_id = nil
						data.source_id = nil
						data.wwise_stop_event = nil
						cleaned = cleaned + 1
					else
						self:_warn_once(
							"moving_sfx:destroy",
							"a moving source could not be destroyed during teardown"
						)
					end
				end
			end

			if rawget(data, "playing_id") ~= nil
				or rawget(data, "source_id") ~= nil then
				pending = true
			end
		end
	end

	-- Keep failed handles inside the active buffer so a repeated teardown can
	-- retry them. Cleared records are harmless to revisit and preserve the
	-- source buffer's fixed record layout.
	moving_sfx.size = pending and size or 0

	return cleaned
end

function module:_cleanup_moving_vfx(fx_extension)
	local moving_vfx = type(fx_extension) == "table"
		and rawget(fx_extension, "_moving_vfx")

	if type(moving_vfx) ~= "table"
		or type(moving_vfx.buffer) ~= "table" then
		return 0
	end

	local size = math.floor(tonumber(moving_vfx.size) or 0)

	if size <= 0 then
		return 0
	end

	size = math.min(size, RING_BUFFER_LIMIT)

	local world = rawget(fx_extension, "_world")
	local world_api = rawget(_G, "World")
	local cleaned = 0
	local pending = false
	local are_particles_playing = type(world_api) == "table"
		and world_api.are_particles_playing
	local stop_particles = type(world_api) == "table"
		and world_api.stop_spawning_particles
	local destroy_particles = type(world_api) == "table"
		and world_api.destroy_particles

	if world == nil then
		self:_warn_once(
			"moving_vfx:world",
			"render world was unavailable during moving-particle teardown"
		)

		return 0
	end

	for i = 1, size do
		local data = moving_vfx.buffer[i]

		if type(data) == "table" then
			local effect_id = rawget(data, "effect_id")

			if effect_id ~= nil then
				local queried = false
				local exists

				if type(are_particles_playing) == "function" then
					queried, exists = pcall(
						are_particles_playing,
						world,
						effect_id
					)
				end

				if not queried then
					self:_warn_once(
						"moving_vfx:query",
						"a moving particle could not be queried during teardown"
					)
				elseif not exists then
					data.effect_id = nil
					cleaned = cleaned + 1
				else
					if type(stop_particles) == "function" then
						pcall(stop_particles, world, effect_id)
					end

					if type(destroy_particles) == "function"
						and pcall(destroy_particles, world, effect_id) then
						data.effect_id = nil
						cleaned = cleaned + 1
					else
						self:_warn_once(
							"moving_vfx:destroy",
							"a moving particle could not be destroyed during teardown"
						)
					end
				end
			end

			if rawget(data, "effect_id") ~= nil then
				pending = true
			end
		end
	end

	-- A native query/destruction failure must not make the retained effect ID
	-- unreachable to a later teardown attempt.
	moving_vfx.size = pending and size or 0

	return cleaned
end

function module:_cleanup_before_destroy(fx_extension)
	if not runtime:is_active(self.id) then
		return
	end

	local ok, cleaned = runtime:run(
		self.id,
		function ()
			return self:_cleanup_moving_sfx(fx_extension)
				+ self:_cleanup_moving_vfx(fx_extension)
		end
	)

	if ok and cleaned > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, cleaned)
	end
end

function module:install()
	local class_path = "scripts/extension_systems/fx/player_unit_fx_extension"
	local particle_ok = runtime:install_hook(
		self.id,
		class_path,
		"_create_particles_wrapper",
		"normal",
		function (func, fx_extension, world, ...)
			if runtime:is_active(self.id) then
				world = self:_repair_particle_world(fx_extension, world)
			end

			return func(fx_extension, world, ...)
		end
	)
	local destroy_ok = runtime:install_hook(
		self.id,
		class_path,
		"destroy",
		"normal",
		function (func, fx_extension, ...)
			self:_cleanup_before_destroy(fx_extension)

			return func(fx_extension, ...)
		end
	)

	if not particle_ok or not destroy_ok then
		runtime:set_available(
			self.id,
			false,
			"PlayerUnitFxExtension lifecycle methods unavailable"
		)
	end
end

function module:reset()
	self._warned = {}
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "repairs the missing world for local screen-space loops and releases moving FX buffers on player teardown"
end

return module
