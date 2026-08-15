local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "effect_template_safety",
	label = "Partial effect-template initialization guards",
	setting_id = "effect_template_safety_enabled",
	_templates = nil,
	_records = {},
	_seen_suppressions = setmetatable({}, {
		__mode = "k",
	}),
	_lifecycle = setmetatable({}, {
		__mode = "k",
	}),
}

local TEMPLATE_PATH = "scripts/settings/fx/effect_templates"

local AIM_REQUIRED_FIELDS = {
	"_position_finder_component",
	"_action_module_target_finder_component",
	"_combat_ability_action_component",
	"_grenade_ability_action_component",
	"_unit_data_extension",
	"_input_extension",
	"_talent_extension",
	"_ability_extension",
	"_companion_spawner_extension",
	"_player_unit",
	"_world",
}

local function _is_dedicated_server()
	return rawget(_G, "DEDICATED_SERVER") == true
end

local function _known_dead(lookup_name, unit)
	if unit == nil then
		return true
	end

	local lookup = rawget(_G, lookup_name)

	return type(lookup) == "table" and not lookup[unit]
end

local function _missing_fields(data, fields)
	if type(data) ~= "table" then
		return true
	end

	for i = 1, #fields do
		if rawget(data, fields[i]) == nil then
			return true
		end
	end

	return false
end

local function _context_value(template_context, field)
	return type(template_context) == "table"
		and rawget(template_context, field)
end

local function _missing_world(template_context)
	return _context_value(template_context, "world") == nil
end

local function _owner_is_missing(unit)
	local managers = rawget(_G, "Managers")
	local state = managers and managers.state
	local player_unit_spawn = state and state.player_unit_spawn
	local owner = player_unit_spawn and player_unit_spawn.owner

	if type(owner) ~= "function" then
		return true
	end

	local ok, player = pcall(owner, player_unit_spawn, unit)

	return not ok or player == nil
end

local function _has_extension(unit, extension_name)
	local script_unit = rawget(_G, "ScriptUnit")
	local has_extension = script_unit and script_unit.has_extension

	if type(has_extension) ~= "function" then
		return false
	end

	local ok, extension = pcall(has_extension, unit, extension_name)

	return ok and extension ~= nil
end

local function _game_object_is_ready(unit)
	local managers = rawget(_G, "Managers")
	local state = managers and managers.state
	local game_session_manager = state and state.game_session
	local unit_spawner = state and state.unit_spawner
	local get_game_session = game_session_manager
		and game_session_manager.game_session
	local get_game_object_id = unit_spawner
		and unit_spawner.game_object_id
	local game_session_api = rawget(_G, "GameSession")
	local game_object_exists = game_session_api
		and game_session_api.game_object_exists

	if type(get_game_session) ~= "function"
		or type(get_game_object_id) ~= "function"
		or type(game_object_exists) ~= "function" then
		return false
	end

	local session_ok, game_session = pcall(
		get_game_session,
		game_session_manager
	)
	local id_ok, game_object_id = pcall(
		get_game_object_id,
		unit_spawner,
		unit
	)

	if not session_ok
		or game_session == nil
		or not id_ok
		or game_object_id == nil then
		return false
	end

	local exists_ok, exists = pcall(
		game_object_exists,
		game_session,
		game_object_id
	)

	return exists_ok and exists == true
end

local function _call_engine(api_name, method_name, ...)
	local api = rawget(_G, api_name)
	local callback = type(api) == "table" and api[method_name]

	if type(callback) ~= "function" then
		return false
	end

	return pcall(callback, ...)
end

local function _cleanup_particle(
		template_data,
		template_context,
		field,
		method_name
	)
	if type(template_data) ~= "table" then
		return false, 0
	end

	local effect_id = rawget(template_data, field)

	if effect_id == nil then
		return true, 0
	end

	local world = _context_value(template_context, "world")
		or rawget(template_data, "_world")

	if world == nil
		or not _call_engine(
			"World",
			method_name,
			world,
			effect_id
		) then
		return false, 0
	end

	template_data[field] = nil

	return true, 1
end

local function _cleanup_sound(
		template_data,
		template_context,
		destroy_manual_source
	)
	if type(template_data) ~= "table" then
		return false, 0
	end

	local source_id = rawget(template_data, "source_id")
	local playing_id = rawget(template_data, "playing_id")
	local stop_event_name = rawget(template_data, "stop_event_name")

	if source_id == nil
		and playing_id == nil
		and stop_event_name == nil then
		return true, 0
	end

	local needs_stop = playing_id ~= nil
		or source_id ~= nil and stop_event_name ~= nil
	local needs_destroy = destroy_manual_source and source_id ~= nil
	local wwise_world = _context_value(
		template_context,
		"wwise_world"
	) or rawget(template_data, "wwise_world")

	if (needs_stop or needs_destroy) and wwise_world == nil then
		return false, 0
	end

	local actions = 0
	local sound_stopped = not needs_stop

	if source_id ~= nil and stop_event_name ~= nil then
		sound_stopped = _call_engine(
			"WwiseWorld",
			"trigger_resource_event",
			wwise_world,
			stop_event_name,
			source_id
		)

		if sound_stopped then
			actions = actions + 1
		end
	end

	if not sound_stopped and playing_id ~= nil then
		sound_stopped = _call_engine(
			"WwiseWorld",
			"stop_event",
			wwise_world,
			playing_id
		)

		if sound_stopped then
			actions = actions + 1
		end
	end

	local source_released = true

	if destroy_manual_source and source_id ~= nil then
		source_released = _call_engine(
			"WwiseWorld",
			"destroy_manual_source",
			wwise_world,
			source_id
		)

		if source_released then
			actions = actions + 1
			template_data.source_id = nil
		end
	elseif sound_stopped then
		template_data.source_id = nil
	end

	if sound_stopped then
		template_data.playing_id = nil
		template_data.stop_event_name = nil
	end

	return sound_stopped and source_released, actions
end

local function _cleanup_moving(template_data, template_context)
	return _cleanup_sound(template_data, template_context, false)
end

local function _cleanup_aim(template_data, template_context)
	return _cleanup_particle(
		template_data,
		template_context,
		"_targeting_effect_id",
		"destroy_particles"
	)
end

local function _cleanup_flamer(template_data, template_context)
	local particle_ok, particle_actions = _cleanup_particle(
		template_data,
		template_context,
		"stream_effect_id",
		"stop_spawning_particles"
	)
	local sound_ok, sound_actions = _cleanup_sound(
		template_data,
		template_context,
		true
	)

	return particle_ok and sound_ok,
		particle_actions + sound_actions
end

local function _cleanup_empowered(template_data, template_context)
	local particle_ok, particle_actions = _cleanup_particle(
		template_data,
		template_context,
		"stream_effect_id",
		"stop_spawning_particles"
	)
	local sound_ok, sound_actions = _cleanup_sound(
		template_data,
		template_context,
		false
	)

	return particle_ok and sound_ok,
		particle_actions + sound_actions
end

local function _cleanup_charged(template_data, template_context)
	local particle_ok, particle_actions = _cleanup_particle(
		template_data,
		template_context,
		"stream_effect_id",
		"stop_spawning_particles"
	)
	local sound_ok, sound_actions = _cleanup_sound(
		template_data,
		template_context,
		false
	)

	return particle_ok and sound_ok,
		particle_actions + sound_actions
end

local function _cleanup_arc(template_data, template_context)
	return _cleanup_particle(
		template_data,
		template_context,
		"link_particle_id",
		"stop_spawning_particles"
	)
end

local function _never_suppress()
	return false
end

local function _guard_moving_update(template_data)
	if _is_dedicated_server() then
		return false
	end

	return type(template_data) ~= "table"
		or _known_dead("ALIVE", rawget(template_data, "unit"))
		or rawget(template_data, "flying_companion_movement_extension") == nil
		or rawget(template_data, "wwise_world") == nil
		or rawget(template_data, "source_id") == nil
end

local function _guard_aim_start(template_data)
	if _is_dedicated_server() then
		return false
	end

	local unit = type(template_data) == "table"
		and rawget(template_data, "unit")

	return _known_dead("ALIVE", unit) or _owner_is_missing(unit)
end

local function _guard_aim_update(template_data)
	if _is_dedicated_server()
		or type(template_data) == "table"
			and rawget(template_data, "is_local_unit") ~= true then
		return false
	end

	if _missing_fields(template_data, AIM_REQUIRED_FIELDS) then
		return true
	end

	return _known_dead(
		"ALIVE",
		rawget(template_data, "_player_unit")
	)
end

local function _guard_flamer_start(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	local unit = type(template_data) == "table"
		and rawget(template_data, "unit")

	return _known_dead("ALIVE", unit)
		or _missing_world(template_context)
		or _context_value(template_context, "wwise_world") == nil
		or not _has_extension(unit, "fx_system")
		or not _has_extension(unit, "visual_loadout_system")
end

local function _guard_flamer_update(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	if type(template_data) ~= "table"
		or _missing_world(template_context) then
		return true
	end

	local unit = rawget(template_data, "unit")
	local attachment_unit = rawget(template_data, "attachment_unit")

	return _known_dead("ALIVE", unit)
		or _known_dead("ALIVE", attachment_unit)
		or rawget(template_data, "attachment_node") == nil
		or rawget(template_data, "game_session") == nil
		or rawget(template_data, "game_object_id") == nil
		or not _game_object_is_ready(unit)
end

local function _guard_empowered_start(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	local unit = type(template_data) == "table"
		and rawget(template_data, "unit")

	return _known_dead("ALIVE", unit)
		or _missing_world(template_context)
		or not _has_extension(unit, "fx_system")
		or not _has_extension(unit, "visual_loadout_system")
end

local function _guard_empowered_update(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	if type(template_data) ~= "table"
		or rawget(template_data, "stream_effect_id") == nil then
		return false
	end

	local unit = rawget(template_data, "unit")
	local attachment_unit = rawget(template_data, "attachment_unit")

	return _missing_world(template_context)
		or _known_dead("ALIVE", unit)
		or _known_dead("ALIVE", attachment_unit)
		or rawget(template_data, "attachment_node") == nil
end

local function _guard_charged_start(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	local unit = type(template_data) == "table"
		and rawget(template_data, "unit")

	return _known_dead("ALIVE", unit)
		or _missing_world(template_context)
		or _context_value(template_context, "wwise_world") == nil
		or not _has_extension(unit, "visual_loadout_system")
		or not _game_object_is_ready(unit)
end

local function _guard_charged_update(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	if type(template_data) ~= "table"
		or _missing_world(template_context) then
		return true
	end

	return _known_dead("ALIVE", rawget(template_data, "unit"))
		or rawget(template_data, "_game_session") == nil
		or rawget(template_data, "_game_object_id") == nil
		or rawget(template_data, "stream_effect_id") == nil
		or not _game_object_is_ready(rawget(template_data, "unit"))
end

local function _guard_arc_start(template_data, template_context)
	if _is_dedicated_server() then
		return false
	end

	if type(template_data) ~= "table"
		or _missing_world(template_context) then
		return true
	end

	return _known_dead("HEALTH_ALIVE", rawget(template_data, "unit"))
		or rawget(template_data, "position") == nil
end

local function _guard_arc_update(template_data, template_context, dt, t)
	if _is_dedicated_server() then
		return false
	end

	if type(template_data) ~= "table"
		or _missing_world(template_context) then
		return true
	end

	local effect_lifetime_end_t = rawget(
		template_data,
		"effect_lifetime_end_t"
	)

	return _known_dead("HEALTH_ALIVE", rawget(template_data, "unit"))
		or rawget(template_data, "target_pos") == nil
		or rawget(template_data, "link_particle_id") == nil
		or type(effect_lifetime_end_t) ~= "number"
		or type(t) ~= "number"
		or t >= effect_lifetime_end_t
end

local SPECS = {
	{
		name = "companion_servo_skull_moving_effect",
		cleanup = _cleanup_moving,
		guards = {
			update = _guard_moving_update,
			stop = _never_suppress,
		},
	},
	{
		name = "companion_servo_skull_aim_on_ground_effect",
		cleanup = _cleanup_aim,
		guards = {
			start = _guard_aim_start,
			update = _guard_aim_update,
			stop = _never_suppress,
		},
	},
	{
		name = "companion_servo_skull_flamer",
		cleanup = _cleanup_flamer,
		guards = {
			start = _guard_flamer_start,
			update = _guard_flamer_update,
			stop = _never_suppress,
		},
		quiet_empty_stop_field = "stream_effect_id",
	},
	{
		name = "companion_servo_skull_empowered_effect",
		cleanup = _cleanup_empowered,
		guards = {
			start = _guard_empowered_start,
			update = _guard_empowered_update,
			stop = _never_suppress,
		},
		quiet_empty_stop_field = "stream_effect_id",
	},
	{
		name = "companion_servo_skull_charged_shooting",
		cleanup = _cleanup_charged,
		guards = {
			start = _guard_charged_start,
			update = _guard_charged_update,
			stop = _never_suppress,
		},
		quiet_empty_stop_field = "stream_effect_id",
	},
	{
		name = "arc_chain_to_position",
		cleanup = _cleanup_arc,
		guards = {
			start = _guard_arc_start,
			update = _guard_arc_update,
			stop = _never_suppress,
		},
		update_suppression_result = true,
	},
}

local PATCH_COUNT = 17

local function _has_terminal_lifecycle(state)
	return state
		and (
			state.start_suppressed
			or state.cleanup_attempted
			or state.cleaned
		)
end

function module:_lifecycle_state(template_data, template_name, create)
	if type(template_data) ~= "table" then
		return nil
	end

	local states = self._lifecycle[template_data]

	if not states and create then
		states = {}
		self._lifecycle[template_data] = states
	end

	local state = states and states[template_name]

	if not state and create then
		state = {}
		states[template_name] = state
	end

	return state
end

function module:_clear_lifecycle(template_data, template_name)
	local states = type(template_data) == "table"
		and self._lifecycle[template_data]

	if states then
		states[template_name] = nil
	end
end

function module:_set_start_suppressed(
		template_data,
		template_name,
		suppressed
	)
	local state = self:_lifecycle_state(
		template_data,
		template_name,
		suppressed
	)

	if state then
		state.start_suppressed = suppressed and true or nil

		if not suppressed then
			state.cleanup_attempted = nil
			state.cleaned = nil
		end
	end
end

function module:_record_suppression(template_data, key)
	if type(template_data) ~= "table" then
		runtime:record_hit(self.id)
		runtime:record_action(self.id)

		return
	end

	local seen = self._seen_suppressions[template_data]

	if not seen then
		seen = {}
		self._seen_suppressions[template_data] = seen
	end

	if seen[key] then
		return
	end

	seen[key] = true
	runtime:record_hit(self.id)
	runtime:record_action(self.id)
end

function module:_run_cleanup(spec, template_data, template_context)
	local state = self:_lifecycle_state(
		template_data,
		spec.name,
		true
	)

	if state.cleaned then
		return true
	end

	state.cleanup_attempted = true

	local ok, complete, actions = runtime:run(
		self.id,
		spec.cleanup,
		template_data,
		template_context
	)

	if ok and tonumber(actions) and actions > 0 then
		runtime:record_action(self.id, actions)
	end

	if ok and complete == true then
		state.cleaned = true

		return true
	end

	return false
end

function module:_make_wrapper(spec, field, original, guard)
	local suppression_result = field == "update"
		and spec.update_suppression_result

	return function (template_data, template_context, ...)
		local state = self:_lifecycle_state(
			template_data,
			spec.name,
			false
		)

		-- Lifecycle interception deliberately outlives the setting/mod toggle.
		-- Once start was suppressed or cleanup began, vanilla must not observe
		-- the partial/cleared handles on a later update, start, or stop.
		if _has_terminal_lifecycle(state) then
			if field == "start" then
				return
			end

			if field == "update" then
				if state.cleanup_attempted and not state.cleaned then
					self:_run_cleanup(
						spec,
						template_data,
						template_context
					)
				end

				return suppression_result
			end

			if field == "stop" then
				if state.start_suppressed then
					self:_clear_lifecycle(
						template_data,
						spec.name
					)
					self:_record_suppression(
						template_data,
						spec.name .. ":stop-after-suppressed-start"
					)

					return
				end

				local complete = state.cleaned == true

				if not complete then
					complete = self:_run_cleanup(
						spec,
						template_data,
						template_context
					)
				end

				if complete then
					self:_clear_lifecycle(
						template_data,
						spec.name
					)
				end

				-- Even an incomplete retry is terminal for this wrapper. Falling
				-- through would ask vanilla to stop already-cleared handles.
				return
			end
		end

		if runtime:is_active(self.id) then
			if field == "stop" then
				if spec.quiet_empty_stop_field
					and type(template_data) == "table"
					and rawget(
						template_data,
						spec.quiet_empty_stop_field
					) == nil then
					local complete = self:_run_cleanup(
						spec,
						template_data,
						template_context
					)

					self:_record_suppression(
						template_data,
						spec.name .. ":empty-stop"
					)

					if complete then
						self:_clear_lifecycle(
							template_data,
							spec.name
						)
					end

					return
				end
			end

			local ok, suppress = runtime:run(
				self.id,
				guard,
				template_data,
				template_context,
				...
			)

			if ok and suppress then
				if field == "start" then
					self:_set_start_suppressed(
						template_data,
						spec.name,
						true
					)
				elseif field == "update" then
					self:_run_cleanup(
						spec,
						template_data,
						template_context
					)
				end

				self:_record_suppression(
					template_data,
					spec.name .. ":" .. field
				)

				return suppression_result
			end

			if field == "start" then
				self:_set_start_suppressed(
					template_data,
					spec.name,
					false
				)
			end
		end

		local a, b, c, d = original(
			template_data,
			template_context,
			...
		)

		if field == "stop" then
			self:_clear_lifecycle(template_data, spec.name)
		end

		return a, b, c, d
	end
end

function module:_restore()
	for i = 1, #self._records do
		local record = self._records[i]

		if record.template[record.field] == record.wrapper then
			record.template[record.field] = record.original
		end
	end

	self._records = {}
	self._seen_suppressions = setmetatable({}, {
		__mode = "k",
	})
	self._lifecycle = setmetatable({}, {
		__mode = "k",
	})
end

function module:_apply()
	if #self._records > 0 then
		return true
	end

	local staged = {}

	for i = 1, #SPECS do
		local spec = SPECS[i]
		local template = self._templates and self._templates[spec.name]

		if type(template) ~= "table"
			or template.name ~= spec.name
			or type(template.resources) ~= "table"
			or type(template.start) ~= "function"
			or type(template.update) ~= "function"
			or type(template.stop) ~= "function"
			or type(spec.cleanup) ~= "function" then
			runtime:set_available(
				self.id,
				false,
				"exact 1.12.3 effect-template shape no longer matches"
			)

			return false
		end

		for field, guard in pairs(spec.guards) do
			local original = template[field]

			staged[#staged + 1] = {
				template = template,
				field = field,
				original = original,
				wrapper = self:_make_wrapper(
					spec,
					field,
					original,
					guard
				),
			}
		end
	end

	if #staged ~= PATCH_COUNT then
		runtime:set_available(
			self.id,
			false,
			"effect-template guard set is incomplete"
		)

		return false
	end

	for i = 1, #staged do
		local record = staged[i]

		record.template[record.field] = record.wrapper
		self._records[#self._records + 1] = record
	end

	return true
end

function module:install()
	runtime:defer_file(self.id, TEMPLATE_PATH, function (templates)
		if type(templates) ~= "table" then
			runtime:set_available(
				self.id,
				false,
				"effect-template registry unavailable after game load"
			)

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
	end
end

function module:on_enabled()
	if runtime:get(self.setting_id) == true then
		self:_apply()
	end
end

function module:on_disabled()
	-- Keep the wrappers and weak lifecycle tombstones installed. Guards pass
	-- through while inactive, but late authoritative stops remain idempotent.
end

function module:on_unload()
	-- Unloading ends the late-stop window. Restore only wrappers this module
	-- still owns so a same-session reload cannot retain or stack old closures.
	self:_restore()
end

function module:runtime_status()
	return #self._records == PATCH_COUNT and "guarding" or "inactive"
end

function module:describe()
	return "guards six exact client FX templates and idempotently releases partially initialized particles and audio"
end

return module
