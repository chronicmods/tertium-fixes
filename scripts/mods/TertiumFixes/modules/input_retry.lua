local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "input_retry",
	label = "Input buffering",
	setting_id = "input_retry_enabled",
	_handlers = setmetatable({}, { __mode = "k" }),
	_units = setmetatable({}, { __mode = "kv" }),
}

local RETRY_WINDOW = 0.75
local RETRY_INTERVAL = 0.1
local swap_inputs = {
	"quick_wield", "wield_scroll_down", "wield_scroll_up",
	"wield_1", "wield_2", "wield_3", "wield_3_gamepad", "wield_4", "wield_5",
}
local allowed_states = {
	walking = true, sprinting = true, dodging = true, sliding = true,
	jumping = true, falling = true, lunging = true, stunned = true, exploding = true,
}
local allowed_slots = {
	slot_primary = true, slot_secondary = true, slot_grenade_ability = true,
	slot_combat_ability = true, slot_pocketable = true, slot_pocketable_small = true,
	slot_device = true,
}
local action_specs = {
	combat = { raw = "combat_ability_pressed", hold = "combat_ability_hold", ability_type = "combat_ability" },
	blitz = { raw = "grenade_ability_pressed", hold = "grenade_ability_hold", ability_type = "grenade_ability" },
	special = { raw = "weapon_extra_pressed", hold = "weapon_extra_hold", release = "weapon_extra_release" },
	reload = { raw = "weapon_reload_pressed", hold = "weapon_reload_hold" },
}
local quick_blitz_items = {
	["content/items/weapons/player/zealot_throwing_knives"] = true,
	["content/items/weapons/player/grenade_quick_flash"] = true,
}
local other_controllers = {
	swap = "guarantee_weapon_swap",
	blitz = "guarantee_weapon_swap",
	combat = "guarantee_ability_activation",
	special = "guarantee_special_action",
	reload = "guarantee_special_action",
}
local feature_settings = {
	swap = "input_retry_swap_enabled",
	combat = "input_retry_ability_enabled",
	blitz = "input_retry_blitz_enabled",
	special = "input_retry_special_enabled",
	reload = "input_retry_reload_enabled",
}

local function read_input(handler, cache, index, name)
	local action_index = handler._action_lookup[name]
	local values = action_index and cache[action_index]

	return values and values[index] == true or false
end

local function write_input(handler, cache, index, name, value)
	local action_index = handler._action_lookup[name]
	local values = action_index and cache[action_index]

	if values then
		values[index] = value
	end
end

local function matches(request, raw_input)
	return request and raw_input ~= nil and (raw_input == request.raw or raw_input == request.hold or raw_input == request.release)
end

local function clear_requests(state)
	state.swap = nil
	state.action = nil
	state.release = nil
end

function module:_feature_enabled(kind)
	if runtime:get(feature_settings[kind]) ~= true then
		return false
	end

	local other = get_mod(other_controllers[kind])

	return not other or type(other.is_enabled) == "function" and not other:is_enabled()
end

function module:_context(handler, service)
	local player = handler._player
	local managers = rawget(_G, "Managers")
	local players = managers and managers.player
	local ui = managers and managers.ui
	local imgui = managers and managers.imgui
	local ui_using_input = ui and type(ui.using_input) == "function" and ui:using_input()
	local imgui_using_input = imgui and type(imgui.using_input) == "function" and imgui:using_input()

	if not player or not players or type(player.local_player_id) ~= "function"
		or players:local_player(player:local_player_id()) ~= player
		or service:is_null_service()
		or ui_using_input or imgui_using_input
		or ui and (ui:has_active_view() or ui:chat_using_input()) then
		return nil
	end

	local unit = player.player_unit

	if not unit or not ALIVE[unit] then
		return nil
	end

	local state = self._handlers[handler]

	if not state or state.unit ~= unit then
		local data = ScriptUnit.has_extension(unit, "unit_data_system")
		local inputs = ScriptUnit.has_extension(unit, "action_input_system")
		local weapon = ScriptUnit.has_extension(unit, "weapon_system")
		local ability = ScriptUnit.has_extension(unit, "ability_system")
		local visual = ScriptUnit.has_extension(unit, "visual_loadout_system")
		local input = ScriptUnit.has_extension(unit, "input_system")

		if not data or not inputs or not weapon or not ability or not visual or not input
			or data.__deleted or inputs.__deleted or weapon.__deleted or ability.__deleted or visual.__deleted or input.__deleted
			or inputs._disabled then
			return nil
		end

		state = {
			unit = unit, data = data, inputs = inputs, weapon = weapon, ability = ability, visual = visual, input = input,
			inventory = data:read_component("inventory"),
			character = data:read_component("character_state"),
			weapon_action = data:read_component("weapon_action"),
			combat_action = data:read_component("combat_ability_action"),
		}
		self._handlers[handler] = state
		self._units[unit] = state
	end

	if state.data.__deleted or state.inputs.__deleted or state.weapon.__deleted
		or state.ability.__deleted or state.visual.__deleted or state.input.__deleted then
		clear_requests(state)
		self._handlers[handler] = nil
		self._units[unit] = nil

		return nil
	end

	if state.inputs._disabled or not allowed_states[state.character.state_name] or not allowed_slots[state.inventory.wielded_slot] then
		clear_requests(state)

		return nil
	end

	return state
end

function module:_locked(service, input)
	local ui = Managers.ui
	local locked = ui and ui:inputs_in_use()
	local rule = service._actions and service._actions[input]
	local aliases = rule and service._aliases and service._aliases[rule.key_alias]

	if locked and aliases then
		for i = 1, #aliases do
			if locked[aliases[i]] then
				return true
			end
		end
	end

	return false
end

function module:_new_request(kind, raw, now, game_t)
	return { kind = kind, raw = raw, deadline = now + RETRY_WINDOW, next_try = now + RETRY_INTERVAL, game_t = game_t }
end

function module:_start_swap(state, raw, now, game_t)
	state.swap = nil
	state.action = nil

	if not self:_feature_enabled("swap") or not self._loadout then
		return nil
	end

	local target = self._loadout.slot_name_from_wield_input(raw, state.inventory, state.visual, state.weapon, state.ability, state.input)

	if not target or target == state.inventory.wielded_slot or not allowed_slots[target]
		or not state.inventory[target] or state.inventory[target] == "not_equipped"
		or not state.weapon:can_wield(target) or not state.ability:can_wield(target) or not state.visual:can_wield(target) then
		return nil
	end

	local canonical = self._loadout.wield_input_from_slot_name(target)
	local request = self:_new_request("swap", canonical, now, game_t)
	request.target = target
	request.item = state.inventory[target]
	state.swap = request
	runtime:record_hit(self.id)

	return canonical
end

function module:_start_action(state, kind, now, game_t)
	state.action = nil

	if not self:_feature_enabled(kind) then
		return nil
	end

	local spec = action_specs[kind]
	local request = self:_new_request(kind, spec.raw, now, game_t)
	request.hold = spec.hold
	request.release = spec.release

	if spec.ability_type then
		local ability = state.ability
		local ability_type = spec.ability_type

		if not ability:has_ability_type(ability_type) or not ability:can_use_ability(ability_type)
			or ability:is_ability_active(ability_type) then
			return nil
		end

		request.ability_type = ability_type
		request.ability = ability._equipped_abilities[ability_type]
		state.swap = nil

		if kind == "combat" and request.ability.inventory_item_reference then
			request.target = ability:get_slot_name(ability_type)

			if request.target == state.inventory.wielded_slot then
				return nil
			end
		end
	else
		request.slot = state.swap and state.swap.target or state.inventory.wielded_slot

		if request.slot ~= "slot_primary" and request.slot ~= "slot_secondary" then
			return nil
		end

		request.item = state.inventory[request.slot]

		if not request.item or request.item == "not_equipped" then
			return nil
		end
	end

	state.action = request
	runtime:record_hit(self.id)

	return request
end

function module:_native_pending(state, request)
	if request.accepted_name then
		local component = request.accepted_id == "combat_ability_action" and state.combat_action or state.weapon_action

		if component.current_action_name == request.accepted_name and component.start_t == request.accepted_t then
			return true
		end

		request.accepted_name = nil
	end

	if request.sequences then
		for parser, sequence in pairs(request.sequences) do
			local frame = parser._sequences[parser._ring_buffer_index]

			if parser._action_component.template_name == sequence.template and frame and frame[1][sequence.index] then
				return true
			end

			request.sequences[parser] = nil
		end
	end

	-- These are the local player's two relevant parsers, not every game input.
	local parsers = state.inputs._action_input_parsers
	local weapon = parsers.weapon_action
	local combat = parsers.combat_ability_action

	for i = 1, 2 do
		local parser = i == 1 and weapon or combat
		local queues = parser and parser._action_input_queue
		local frame = queues and queues[parser._ring_buffer_index]
		local raw_inputs = frame and frame[2]

		if raw_inputs then
			for j = 1, parser._MAX_ACTION_INPUT_QUEUE do
				if matches(request, raw_inputs[j]) then
					return true
				end
			end
		end
	end

	return false
end

function module:_retry(state, request, handler, cache, index, service, now)
	if now >= request.deadline or runtime:get(feature_settings[request.kind]) ~= true or self:_locked(service, request.raw) then
		return false
	end

	local inventory = state.inventory

	if request.target and inventory.wielded_slot == request.target then
		return false
	elseif request.kind == "swap" and inventory[request.target] ~= request.item then
		return false
	elseif request.slot then
		if inventory[request.slot] ~= request.item then
			return false
		elseif inventory.wielded_slot ~= request.slot then
			return state.swap and state.swap.target == request.slot or false
		end
	elseif request.ability_type then
		local ability = state.ability

		if ability._equipped_abilities[request.ability_type] ~= request.ability
			or ability:is_ability_active(request.ability_type)
			or not ability:can_use_ability(request.ability_type) then
			return false
		end
	end

	if now < request.next_try or self:_native_pending(state, request) then
		return true
	end

	write_input(handler, cache, index, request.raw, true)
	request.next_try = now + RETRY_INTERVAL

	if request.release and not read_input(handler, cache, index, request.hold) then
		state.release = request
	end

	runtime:record_action(self.id)

	return true
end

function module:_capture(handler, cache, service, index)
	local old_state = self._handlers[handler]
	local swap_input
	local swap_count = 0

	for i = 1, #swap_inputs do
		if read_input(handler, cache, index, swap_inputs[i]) then
			swap_input = swap_inputs[i]
			swap_count = swap_count + 1
		end
	end

	local combat = read_input(handler, cache, index, "combat_ability_pressed")
	local grenade = read_input(handler, cache, index, "grenade_ability_pressed")
	local special = read_input(handler, cache, index, "weapon_extra_pressed")
	local reload = read_input(handler, cache, index, "weapon_reload_pressed")

	if not swap_input and not combat and not grenade and not special and not reload
		and not (old_state and (old_state.swap or old_state.action or old_state.release)) then
		return
	end

	local state = self:_context(handler, service)

	if not state then
		if old_state then clear_requests(old_state) end

		return
	end

	local frame = handler._frame
	local session = Managers.state and Managers.state.game_session
	local fixed_step = session and session.fixed_time_step

	if type(frame) ~= "number" or type(fixed_step) ~= "number" or frame <= (state.last_frame or -1) then
		return
	end

	state.last_frame = frame
	local now = runtime.clock
	local game_t = frame * fixed_step

	if swap_count > 1 or read_input(handler, cache, index, "interact_pressed") or read_input(handler, cache, index, "interact_hold") then
		clear_requests(state)

		return
	end

	local release = state.release
	state.release = nil

	if swap_input then
		local canonical = self:_start_swap(state, swap_input, now, game_t)

		if canonical then
			-- A repeated wheel/quick-swap input must keep its original destination.
			write_input(handler, cache, index, swap_input, false)
			write_input(handler, cache, index, canonical, true)
		end
	end

	if combat then
		state.swap = nil
		self:_start_action(state, "combat", now, game_t)
	elseif grenade then
		local ability = state.ability._equipped_abilities.grenade_ability

		if ability and quick_blitz_items[ability.inventory_item_reference] then
			self:_start_action(state, "blitz", now, game_t)
		elseif ability and state.ability:can_use_ability("grenade_ability") then
			self:_start_swap(state, "grenade_ability_pressed", now, game_t)
		else
			clear_requests(state)
		end
	elseif special or reload then
		local request = self:_start_action(state, special and "special" or "reload", now, game_t)

		if request and request.slot ~= state.inventory.wielded_slot then
			write_input(handler, cache, index, request.raw, false)
		end
	elseif state.action and (read_input(handler, cache, index, "action_two_pressed")
		or read_input(handler, cache, index, "action_one_pressed") and not state.action.ability_type) then
		state.action = nil
	end

	-- Special-action sequences use a release edge. Ability aim uses hold=false,
	-- which already comes from the user's input and needs no extra release.
	if release and not swap_input and not combat and not grenade and not special and not reload
		and not read_input(handler, cache, index, "action_one_pressed")
		and not read_input(handler, cache, index, "action_two_pressed")
		and not read_input(handler, cache, index, release.hold)
		and state.inventory.wielded_slot == release.slot and state.inventory[release.slot] == release.item
		and not self:_locked(service, release.raw) and not self:_locked(service, release.release) then
		write_input(handler, cache, index, release.release, true)
	end

	if state.swap and not self:_retry(state, state.swap, handler, cache, index, service, now) then
		state.swap = nil
	end

	if state.action and not self:_retry(state, state.action, handler, cache, index, service, now) then
		state.action = nil
	end
end

function module:_action_started(handler, id, action_name, settings, raw_input, t)
	local state = self._units[handler._unit]

	if not state then return end

	local request = matches(state.swap, raw_input) and state.swap or matches(state.action, raw_input) and state.action

	if not request or t + 0.000001 < request.game_t then
		return
	end

	if request.target then
		if action_name ~= "none" then
			request.accepted_name = action_name
			request.accepted_id = id
			request.accepted_t = t
		end
	elseif request.kind == "combat" and id == "combat_ability_action"
		or request.kind ~= "combat" and id == "weapon_action" then
		state.action = nil
	end
end

function module:_action_corrected(handler, id)
	local data = handler._registered_components[id]
	local component = data and data.component

	if component then
		-- A correction binds the server's action without calling start_action.
		-- Completed actions retain used_input/start_t and count as accepted too.
		self:_action_started(handler, id, component.current_action_name, nil, component.used_input, component.start_t)
	end
end

function module:_sequence_progressed(parser, sequences, sequence_index, t, raw_input)
	local state = self._units[parser._unit]

	if not state then return end

	local request = matches(state.swap, raw_input) and state.swap or matches(state.action, raw_input) and state.action

	if request and t + 0.000001 >= request.game_t and sequences[1][sequence_index] then
		request.sequences = request.sequences or {}
		request.sequences[parser] = { index = sequence_index, template = parser._action_component.template_name }
	end
end

function module:install()
	runtime:defer_file(self.id, "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout", function (loadout)
		if type(loadout.slot_name_from_wield_input) ~= "function" or type(loadout.wield_input_from_slot_name) ~= "function" then
			runtime:set_available(self.id, false, "weapon selection helpers unavailable")
			return
		end

		self._loadout = loadout
	end)
	runtime:install_hook(self.id, "scripts/managers/player/player_game_states/human_input_handler", "_parse_input", "safe", function (handler, cache, service, index)
		if runtime:is_active(self.id) then runtime:run(self.id, self._capture, self, handler, cache, service, index) end
	end)
	runtime:install_hook(self.id, "scripts/utilities/action/action_handler", "start_action", "safe", function (handler, id, objects, action_name, params, settings, raw_input, t)
		local state = self._units[handler._unit]

		if runtime:is_active(self.id) and state and (state.swap or state.action) then
			runtime:run(self.id, self._action_started, self, handler, id, action_name, settings, raw_input, t)
		end
	end)
	runtime:install_hook(self.id, "scripts/utilities/action/action_handler", "server_correction_occurred", "safe", function (handler, unit, from_frame, to_frame, id)
		local state = self._units[handler._unit]

		if runtime:is_active(self.id) and state and (state.swap or state.action) then
			runtime:run(self.id, self._action_corrected, self, handler, id)
		end
	end)
	runtime:install_hook(self.id, "scripts/extension_systems/action_input/action_input_parser", "_progress_input_sequence", "safe", function (parser, sequences, sequence_index, t, config, queue, raw_input)
		local state = self._units[parser._unit]

		if runtime:is_active(self.id) and state and (state.swap or state.action) then
			runtime:run(self.id, self._sequence_progressed, self, parser, sequences, sequence_index, t, raw_input)
		end
	end)
end

function module:reset()
	self._handlers = setmetatable({}, { __mode = "k" })
	self._units = setmetatable({}, { __mode = "kv" })
end

function module:on_disabled() self:reset() end
function module:on_unload() self:reset() end
function module:on_game_state_changed() self:reset() end
function module:on_setting_changed() self:reset() end

function module:describe()
	return "retries recent swap, ability, special and reload presses for up to 0.75 seconds"
end

return module
