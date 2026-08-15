local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "fx_handler_integrity",
	label = "FX handler ID and local-lifecycle integrity",
	setting_id = "fx_handler_integrity_enabled",
	local_rewrite_setting_id = "fx_handler_local_rewrite_enabled",
	rpc_containment_setting_id = "fx_handler_rpc_idempotence_enabled",
	_install_queued = false,
}

local FX_SYSTEM_PATH = "scripts/extension_systems/fx/fx_system"
local HANDLER_PATH = "scripts/extension_systems/fx/utilities/effect_templates_handler"
local LOCAL_HANDLER_MARKER = "_tertium_local_only"
local QUARANTINED_SLOT_MARKER = "_tertium_fx_slot_quarantined"

local function _is_non_negative_integer(value)
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value == math.floor(value)
end

local function _handler_storage(handler)
	if type(handler) ~= "table" then
		return nil, nil
	end

	local max_num_template_effects = rawget(
		handler,
		"_max_num_template_effects"
	)
	local template_effects = rawget(handler, "_template_effects")

	if not _is_non_negative_integer(max_num_template_effects)
		or max_num_template_effects == 0
		or type(template_effects) ~= "table" then
		return nil, nil
	end

	return max_num_template_effects, template_effects
end

local function _global_effect_slot(handler, global_effect_id)
	if not _is_non_negative_integer(global_effect_id) then
		return nil, nil
	end

	local max_num_template_effects, template_effects = _handler_storage(
		handler
	)

	if not max_num_template_effects then
		return nil, nil
	end

	local buffer_index = global_effect_id % max_num_template_effects + 1

	return template_effects[buffer_index], buffer_index
end

local function _buffer_slot(handler, buffer_index)
	if not _is_non_negative_integer(buffer_index)
		or buffer_index < 1 then
		return nil
	end

	local max_num_template_effects, template_effects = _handler_storage(
		handler
	)

	if not max_num_template_effects
		or buffer_index > max_num_template_effects then
		return nil
	end

	return template_effects[buffer_index]
end

local function _slot_matches_id(template_effect, global_effect_id)
	return type(template_effect) == "table"
		and template_effect.is_running == true
		and template_effect.template ~= nil
		and template_effect.global_effect_id == global_effect_id
end

local function _clear_array(array)
	for i = #array, 1, -1 do
		array[i] = nil
	end
end

local function _clear_map(map)
	for key in pairs(map) do
		map[key] = nil
	end
end

local function _remove_all_references(array, value)
	local removed = 0

	for i = #array, 1, -1 do
		if array[i] == value then
			table.remove(array, i)
			removed = removed + 1
		end
	end

	return removed
end

local function _clear_generation_after_stop(template_effect, expected_id)
	if type(template_effect) ~= "table"
		or template_effect.is_running == true
		or template_effect.global_effect_id ~= expected_id then
		return false
	end

	template_effect.global_effect_id = nil

	return expected_id ~= nil
end

local function _next_ticket_for_slot(cursor, capacity, slot_index)
	local slot_remainder = slot_index - 1
	local distance = (slot_remainder - cursor % capacity) % capacity
	local ticket = cursor + distance

	if not _is_non_negative_integer(ticket) then
		return nil
	end

	return ticket, distance
end

local function _allocation_floor(cursor, capacity, slots)
	local floor = cursor

	for slot_index = 1, capacity do
		local slot = slots[slot_index]

		if type(slot) ~= "table" then
			return nil
		end

		local stored_id = slot.global_effect_id

		if _is_non_negative_integer(stored_id) and stored_id >= floor then
			floor = stored_id + 1

			if not _is_non_negative_integer(floor) then
				return nil
			end
		end
	end

	return floor
end


-- Produces a reservation from physical slot state. Free capacity is preferred;
-- when saturated, the oldest stoppable generation is recycled. A malformed
-- generation is selected first so a valid stop can repair it without relying on
-- generation-based removal.
local function _reserve_local_slot(cursor, capacity, slots)
	local free_slot
	local free_index
	local free_distance
	local recycle_slot
	local recycle_index
	local recycle_generation
	local corrupt_recycle = false

	for slot_index = 1, capacity do
		local slot = slots[slot_index]

		if type(slot) ~= "table" then
			return nil
		end

		if slot.is_running ~= true then
			local _, distance = _next_ticket_for_slot(
				cursor,
				capacity,
				slot_index
			)

			if distance ~= nil
				and (free_distance == nil or distance < free_distance) then
				free_slot = slot
				free_index = slot_index
				free_distance = distance
			end
		elseif slot[QUARANTINED_SLOT_MARKER] ~= true
			and type(slot.template) == "table" then
			local generation = slot.global_effect_id
			local generation_is_valid = _is_non_negative_integer(generation)

			if not generation_is_valid and not corrupt_recycle then
				recycle_slot = slot
				recycle_index = slot_index
				recycle_generation = nil
				corrupt_recycle = true
			elseif not corrupt_recycle
				and (recycle_generation == nil
					or generation < recycle_generation) then
				recycle_slot = slot
				recycle_index = slot_index
				recycle_generation = generation
			end
		end
	end

	local selected_slot = free_slot or recycle_slot
	local selected_index = free_index or recycle_index

	if not selected_slot then
		return nil
	end

	local ticket = _next_ticket_for_slot(cursor, capacity, selected_index)

	if ticket == nil then
		return nil
	end

	return selected_slot, ticket, free_slot == nil
end

local function _retire_local_slot(handler, template_context, slot)
	local running = rawget(handler, "_running_template_effects")
	local stop_template_effect = handler.stop_template_effect
	local template = type(slot) == "table" and slot.template
	local expected_id = type(slot) == "table" and slot.global_effect_id

	if type(running) ~= "table"
		or type(stop_template_effect) ~= "function"
		or type(template) ~= "table" then
		return false
	end

	local stopped_without_error = pcall(
		stop_template_effect,
		handler,
		template_context,
		slot,
		template
	)

	if not stopped_without_error or slot.is_running == true then
		if slot.global_effect_id == expected_id then
			slot[QUARANTINED_SLOT_MARKER] = true
		end

		return false
	end

	_clear_generation_after_stop(slot, expected_id)
	_remove_all_references(running, slot)
	slot[QUARANTINED_SLOT_MARKER] = nil

	return true
end

local function _park_malformed_slot(handler, slot)
	local running = rawget(handler, "_running_template_effects")

	if type(running) == "table" then
		_remove_all_references(running, slot)
	end

	if type(slot) == "table" and slot.is_running == true then
		slot[QUARANTINED_SLOT_MARKER] = true
	end
end

local function _local_update_workspace(handler)
	local workspace = rawget(handler, "_tertium_local_update_workspace")

	if type(workspace) ~= "table" then
		workspace = {
			invalid = {},
			invalid_ids = {},
			invalid_templates = {},
			retire = {},
			retire_ids = {},
			seen = {},
			snapshot = {},
			snapshot_ids = {},
			snapshot_templates = {},
		}
		handler._tertium_local_update_workspace = workspace
		handler._tertium_effects_to_stop = workspace.retire
	else
		_clear_array(workspace.invalid)
		_clear_array(workspace.invalid_ids)
		_clear_array(workspace.invalid_templates)
		_clear_array(workspace.retire)
		_clear_array(workspace.retire_ids)
		_clear_map(workspace.seen)
		_clear_array(workspace.snapshot)
		_clear_array(workspace.snapshot_ids)
		_clear_array(workspace.snapshot_templates)
	end

	return workspace
end

function module:_active()
	return runtime:is_active(self.id)
end

function module:_local_rewrite_active(handler)
	return self:_active()
		and type(handler) == "table"
		and rawget(handler, LOCAL_HANDLER_MARKER) == true
		and runtime:get(self.local_rewrite_setting_id) == true
end

function module:_rpc_containment_active()
	return self:_active()
		and runtime:get(self.rpc_containment_setting_id) == true
end

function module:_record_prevented_failure()
	runtime:record_hit(self.id)
	runtime:record_action(self.id)
end

function module:_mark_local_handler(handler)
	if type(handler) ~= "table"
		or rawget(handler, LOCAL_HANDLER_MARKER) == true then
		return false
	end

	handler[LOCAL_HANDLER_MARKER] = true

	if self:_active() then
		runtime:record_action(self.id)
	end

	return true
end

function module:_mark_live_local_handler()
	local managers = rawget(_G, "Managers")
	local state = type(managers) == "table" and managers.state
	local extension_manager = type(state) == "table" and state.extension
	local get_system = type(extension_manager) == "table"
		and extension_manager.system

	if type(get_system) ~= "function" then
		return false
	end

	local ok, fx_system = pcall(
		get_system,
		extension_manager,
		"fx_system"
	)

	if not ok or type(fx_system) ~= "table" then
		return false
	end

	return self:_mark_local_handler(
		rawget(fx_system, "_local_effect_templates_handler")
	)
end

function module:_has_running_effect(
		func,
		handler,
		global_effect_id
	)
	if not self:_active() then
		return func(handler, global_effect_id)
	end

	if not _is_non_negative_integer(global_effect_id) then
		return false
	end

	local max_num_template_effects = _handler_storage(handler)

	if not max_num_template_effects then
		return func(handler, global_effect_id)
	end

	local template_effect = _global_effect_slot(
		handler,
		global_effect_id
	)

	return _slot_matches_id(template_effect, global_effect_id)
end

function module:_add_template_effect(
		func,
		handler,
		unit_to_particle_group_lookup,
		template_context,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	if not self:_local_rewrite_active(handler) then
		return func(
			handler,
			unit_to_particle_group_lookup,
			template_context,
			template,
			optional_unit,
			optional_node,
			optional_position,
			optional_player_owner_unit
		)
	end

	local capacity, slots = _handler_storage(handler)
	local running = type(handler) == "table"
		and rawget(handler, "_running_template_effects")
	local cursor = type(handler) == "table"
		and rawget(handler, "_next_global_effect_id")

	-- Once a handler is known to be local, an uncertain shape must not be sent
	-- through the network-owning implementation. Refuse this one allocation and
	-- leave the existing state untouched instead.
	if not capacity
		or type(running) ~= "table"
		or not _is_non_negative_integer(cursor)
		or type(handler.start_template_effect) ~= "function"
		or type(handler.stop_template_effect) ~= "function" then
		self:_record_prevented_failure()

		return nil
	end

	cursor = _allocation_floor(cursor, capacity, slots)

	if cursor == nil then
		self:_record_prevented_failure()

		return nil
	end

	local slot, ticket, needs_recycle = _reserve_local_slot(
		cursor,
		capacity,
		slots
	)

	if not slot then
		self:_record_prevented_failure()

		return nil
	end

	if needs_recycle
		and not _retire_local_slot(handler, template_context, slot) then
		_park_malformed_slot(handler, slot)
		self:_record_prevented_failure()

		return nil
	end

	-- A stopped slot can retain stale bookkeeping after interrupted teardown.
	-- Removing all stale list references before start prevents duplicate roots.
	_remove_all_references(running, slot)
	slot.global_effect_id = nil
	slot[QUARANTINED_SLOT_MARKER] = nil

	local started_without_error = pcall(
		handler.start_template_effect,
		handler,
		unit_to_particle_group_lookup,
		template_context,
		slot,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)

	if not started_without_error
		or slot.is_running ~= true
		or slot.template ~= template then
		if slot.is_running == true and type(slot.template) == "table" then
			_retire_local_slot(handler, template_context, slot)
		else
			_park_malformed_slot(handler, slot)
		end

		self:_record_prevented_failure()

		return nil
	end

	slot.global_effect_id = ticket
	handler._next_global_effect_id = ticket + 1
	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	-- A marked local handler has no network ownership, so allocation ends here.
	return ticket
end

function module:_remove_template_effect(
		func,
		handler,
		template_context,
		global_effect_id
	)
	if not self:_active() then
		return func(handler, template_context, global_effect_id)
	end

	local template_effect = _global_effect_slot(
		handler,
		global_effect_id
	)

	if not _slot_matches_id(template_effect, global_effect_id) then
		self:_record_prevented_failure()

		return nil
	end

	if not self:_local_rewrite_active(handler) then
		return func(handler, template_context, global_effect_id)
	end

	local template = template_effect.template

	handler:stop_template_effect(
		template_context,
		template_effect,
		template
	)
	template_effect.global_effect_id = nil
	runtime:record_hit(self.id)
	runtime:record_action(self.id)

	-- A marked local handler owns no network state, so it must emit no stop RPC.
	return nil
end

function module:_update_local_handler(
		func,
		handler,
		template_context,
		dt,
		t
	)
	if not self:_local_rewrite_active(handler) then
		return func(handler, template_context, dt, t)
	end

	local running_template_effects = rawget(
		handler,
		"_running_template_effects"
	)

	if type(running_template_effects) ~= "table" then
		return func(handler, template_context, dt, t)
	end

	local workspace = _local_update_workspace(handler)
	local snapshot = workspace.snapshot
	local snapshot_ids = workspace.snapshot_ids
	local snapshot_templates = workspace.snapshot_templates
	local seen = workspace.seen
	local write_index = 1
	local malformed_references = 0

	-- Snapshot unique slot identities first. This makes update callbacks free to
	-- stop or replace other effects without invalidating traversal state.
	for read_index = 1, #running_template_effects do
		local slot = running_template_effects[read_index]

		if type(slot) == "table" and not seen[slot] then
			seen[slot] = true
			snapshot[#snapshot + 1] = slot
			snapshot_ids[#snapshot] = slot.global_effect_id
			snapshot_templates[#snapshot] = slot.template
			running_template_effects[write_index] = slot
			write_index = write_index + 1
		else
			malformed_references = malformed_references + 1
		end
	end

	for index = #running_template_effects, write_index, -1 do
		running_template_effects[index] = nil
	end

	if malformed_references > 0 then
		self:_record_prevented_failure()
	end

	for index = 1, #snapshot do
		local slot = snapshot[index]
		local expected_id = snapshot_ids[index]
		local expected_template = snapshot_templates[index]

		-- A callback earlier in the snapshot may have replaced this physical
		-- slot. Never update or retire that newer generation in the same pass.
		if slot.global_effect_id == expected_id
			and slot.template == expected_template then
			if slot.is_running ~= true then
				_clear_generation_after_stop(slot, expected_id)
				_remove_all_references(running_template_effects, slot)
				self:_record_prevented_failure()
			elseif type(expected_template) ~= "table"
				or type(expected_template.update) ~= "function"
				or not _is_non_negative_integer(expected_id)
				or _global_effect_slot(handler, expected_id) ~= slot then
				local invalid_index = #workspace.invalid + 1

				workspace.invalid[invalid_index] = slot
				workspace.invalid_ids[invalid_index] = expected_id
				workspace.invalid_templates[invalid_index] = expected_template
			else
				local lifetime_complete = expected_template.update(
					slot.template_data,
					template_context,
					dt,
					t
				)

				if handler._allow_template_effects_life_time
					and lifetime_complete
					and slot.is_running == true
					and slot.global_effect_id == expected_id
					and slot.template == expected_template then
					local retire_index = #workspace.retire + 1

					workspace.retire[retire_index] = slot
					workspace.retire_ids[retire_index] = expected_id
				end
			end
		end
	end

	for index = 1, #workspace.retire do
		local slot = workspace.retire[index]
		local expected_id = workspace.retire_ids[index]

		if slot.is_running == true
			and slot.global_effect_id == expected_id then
			if _retire_local_slot(handler, template_context, slot) then
				runtime:record_hit(self.id)
				runtime:record_action(self.id)
			else
				_park_malformed_slot(handler, slot)
				self:_record_prevented_failure()
			end
		end
	end

	for index = 1, #workspace.invalid do
		local slot = workspace.invalid[index]

		if slot.is_running == true
			and slot.global_effect_id == workspace.invalid_ids[index]
			and slot.template == workspace.invalid_templates[index] then
			if not _retire_local_slot(handler, template_context, slot) then
				_park_malformed_slot(handler, slot)
			end

			self:_record_prevented_failure()
		end
	end

	return nil
end

function module:_remove_effects_on_unit(
		func,
		handler,
		template_context,
		unit
	)
	if not self:_active() then
		return func(handler, template_context, unit)
	end

	local running_template_effects = type(handler) == "table"
		and rawget(handler, "_running_template_effects")

	if type(running_template_effects) ~= "table" then
		return func(handler, template_context, unit)
	end

	local target_effects = {}
	local target_generations = {}

	for i = 1, #running_template_effects do
		local template_effect = running_template_effects[i]

		if type(template_effect) == "table"
			and template_effect.optional_unit == unit then
			local target_index = #target_effects + 1

			target_effects[target_index] = template_effect
			target_generations[target_index] =
				template_effect.global_effect_id
		end
	end

	local a, b, c, d = func(handler, template_context, unit)
	local cleared = 0

	for i = 1, #target_effects do
		local template_effect = target_effects[i]
		local expected_id = target_generations[i]

		-- Teardown callbacks may synchronously reuse a physical slot. Only clear
		-- the generation that was captured, and only after that slot is stopped.
		if _clear_generation_after_stop(template_effect, expected_id) then
			cleared = cleared + 1
		end
	end

	-- Vanilla only matches optional_unit. Player-owned effects can point at a
	-- different attachment unit, so their owner teardown needs a second pass.
	for i = #running_template_effects, 1, -1 do
		local template_effect = running_template_effects[i]

		if type(template_effect) == "table"
			and template_effect.optional_player_owner_unit == unit
			and template_effect.is_running == true
			and template_effect.template ~= nil then
			local expected_id = template_effect.global_effect_id

			handler:stop_template_effect(
				template_context,
				template_effect,
				template_effect.template
			)

			if _clear_generation_after_stop(template_effect, expected_id) then
				cleared = cleared + 1
			end
		end
	end

	if cleared > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, cleared)
	end

	return a, b, c, d
end

function module:_clear_stopped_ids(handler)
	if not self:_active() or type(handler) ~= "table" then
		return
	end

	local template_effects = rawget(handler, "_template_effects")

	if type(template_effects) ~= "table" then
		return
	end

	local cleared = 0

	for i = 1, #template_effects do
		local template_effect = template_effects[i]

		if type(template_effect) == "table"
			and template_effect.is_running ~= true
			and template_effect.global_effect_id ~= nil then
			template_effect.global_effect_id = nil
			cleared = cleared + 1
		end
	end

	if cleared > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, cleared)
	end
end

function module:_start_template_effect_from_rpc(
		func,
		handler,
		unit_to_particle_group_lookup,
		template_context,
		buffer_index,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	if not self:_rpc_containment_active() then
		return func(
			handler,
			unit_to_particle_group_lookup,
			template_context,
			buffer_index,
			template,
			optional_unit,
			optional_node,
			optional_position,
			optional_player_owner_unit
		)
	end

	local template_effect = _buffer_slot(handler, buffer_index)

	if type(template_effect) ~= "table" then
		self:_record_prevented_failure()

		return nil
	end

	if template_effect.is_running == true
		and template_effect.template ~= nil then
		handler:stop_template_effect(
			template_context,
			template_effect,
			template_effect.template
		)
		template_effect.global_effect_id = nil
		self:_record_prevented_failure()
	end

	return func(
		handler,
		unit_to_particle_group_lookup,
		template_context,
		buffer_index,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
end

function module:_stop_template_effect_from_rpc(
		func,
		handler,
		template_context,
		buffer_index
	)
	if not self:_rpc_containment_active() then
		return func(handler, template_context, buffer_index)
	end

	local template_effect = _buffer_slot(handler, buffer_index)

	if type(template_effect) ~= "table"
		or template_effect.is_running ~= true
		or template_effect.template == nil then
		self:_record_prevented_failure()

		return nil
	end

	local a, b, c, d = func(handler, template_context, buffer_index)

	template_effect.global_effect_id = nil

	return a, b, c, d
end

function module:install()
	if self._install_queued then
		return
	end

	self._install_queued = true

	local hooks_ok = runtime:install_hook(
		self.id,
		FX_SYSTEM_PATH,
		"init",
		"safe",
		function (fx_system)
			self:_mark_local_handler(
				type(fx_system) == "table"
					and rawget(
						fx_system,
						"_local_effect_templates_handler"
					)
			)
		end
	)

	local function queue_handler_hook(method_name, hook_kind, handler)
		local queued = runtime:install_hook(
			self.id,
			HANDLER_PATH,
			method_name,
			hook_kind,
			handler
		)

		hooks_ok = queued and hooks_ok
	end

	queue_handler_hook(
		"has_running_effect_with_global_id",
		"normal",
		function (func, handler, global_effect_id)
			return self:_has_running_effect(
				func,
				handler,
				global_effect_id
			)
		end
	)
	queue_handler_hook(
		"add_template_effect",
		"normal",
		function (func, handler, ...)
			return self:_add_template_effect(func, handler, ...)
		end
	)
	queue_handler_hook(
		"remove_template_effect",
		"normal",
		function (func, handler, template_context, global_effect_id)
			return self:_remove_template_effect(
				func,
				handler,
				template_context,
				global_effect_id
			)
		end
	)
	queue_handler_hook(
		"update",
		"normal",
		function (func, handler, template_context, dt, t)
			return self:_update_local_handler(
				func,
				handler,
				template_context,
				dt,
				t
			)
		end
	)
	queue_handler_hook(
		"remove_effects_on_unit",
		"normal",
		function (func, handler, template_context, unit)
			return self:_remove_effects_on_unit(
				func,
				handler,
				template_context,
				unit
			)
		end
	)
	queue_handler_hook(
		"clear",
		"safe",
		function (handler)
			self:_clear_stopped_ids(handler)
		end
	)
	queue_handler_hook(
		"start_template_effect_from_rpc",
		"normal",
		function (func, handler, ...)
			return self:_start_template_effect_from_rpc(
				func,
				handler,
				...
			)
		end
	)
	queue_handler_hook(
		"stop_template_effect_from_rpc",
		"normal",
		function (func, handler, template_context, buffer_index)
			return self:_stop_template_effect_from_rpc(
				func,
				handler,
				template_context,
				buffer_index
			)
		end
	)

	if not hooks_ok then
		runtime:set_available(
			self.id,
			false,
			"FX handler lifecycle methods unavailable"
		)
	end
end

function module:on_all_mods_loaded()
	self:_mark_live_local_handler()
end

function module:on_game_state_changed(status)
	if status == "enter" then
		self:_mark_live_local_handler()
	end
end

function module:on_setting_changed(setting_id)
	if setting_id == self.setting_id
		or setting_id == self.local_rewrite_setting_id then
		self:_mark_live_local_handler()
	end
end

function module:on_enabled()
	self:_mark_live_local_handler()
end

function module:runtime_status()
	if not self:_active() then
		return "disabled"
	elseif runtime:get(self.local_rewrite_setting_id) == true then
		return "hardening + local no-RPC lifecycle"
	end

	return "ID hardening only"
end

function module:describe()
	return "validates exact ring-buffer generations, clears stale IDs, optionally bounds duplicate RPC effects, and keeps marked local FX off the network"
end

return module
