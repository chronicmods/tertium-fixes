local source_root = arg and arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT")
assert(source_root, "the extracted Darktide source directory is required")

local checks, failures = 0, 0
local function check(value, message)
	checks = checks + 1
	if value then
		print("PASS " .. message)
	else
		failures = failures + 1
		print("FAIL " .. message)
	end
end

unpack = unpack or table.unpack
table.clear = function (value) for key in pairs(value) do value[key] = nil end end
math.index_wrapper = function (value, size) return (value - 1) % size + 1 end
function class() return {} end
function settings(_, value) return value end
Unit = { flow_event = function () end }
NetworkConstants = { action_combo_count = { max = 10 }, action_context_id = { max = 64 } }
local settings_path = "scripts/managers/player/player_game_states/input_handler_settings"
local loadout_path = "scripts/extension_systems/visual_loadout/utilities/player_unit_visual_loadout"
local handler_path = "scripts/managers/player/player_game_states/human_input_handler"
local action_path = "scripts/utilities/action/action_handler"
local parser_path = "scripts/extension_systems/action_input/action_input_parser"
local input_settings = dofile(source_root .. "/" .. settings_path .. ".lua")
local slot_inputs = {
	slot_primary = "wield_1", slot_secondary = "wield_2", slot_pocketable = "wield_3",
	slot_pocketable_small = "wield_4", slot_device = "wield_5",
	slot_grenade_ability = "grenade_ability_pressed", slot_combat_ability = "combat_ability_pressed",
}
local constants = {
	wield_inputs = {}, slot_configuration = {},
	quick_wield_configuration = { default = "slot_primary", slot_primary = "slot_secondary" },
	gamepad_pocketable_wield_configuration = { slot_pocketable = "slot_pocketable_small", slot_pocketable_small = "slot_pocketable" },
	scroll_wield_order = { "slot_secondary", "slot_primary", "slot_grenade_ability", slot_secondary = 1, slot_primary = 2, slot_grenade_ability = 3 },
}
for slot, input in pairs(slot_inputs) do
	constants.slot_configuration[slot] = { wieldable = true, slot_type = "weapon", wield_inputs = { pressed = { input } } }
end
constants.slot_configuration.slot_pocketable.wield_inputs.pressed[2] = "wield_3_gamepad"

local game_loadout
local original_require = require
function require(path)
	if path == settings_path then return input_settings end
	if path == "scripts/settings/player_character/player_character_constants" then return constants end
	if path == loadout_path then return game_loadout end
	if path == "scripts/settings/action/action_handler_settings" then return { transition_types = {} } end
	if path == "scripts/settings/buff/buff_settings" then return { stat_buffs = {}, proc_events = {} } end
	return {}
end
game_loadout = dofile(source_root .. "/" .. loadout_path .. ".lua")
local GameInput = dofile(source_root .. "/" .. handler_path .. ".lua")
local GameAction = dofile(source_root .. "/" .. action_path .. ".lua")
local GameParser = dofile(source_root .. "/" .. parser_path .. ".lua")
function require(path)
	if path == "scripts/settings/talent/talent_settings" then return { veteran_3 = { combat_ability = { radius = 10 } } } end
	return {}
end
local veteran_ability = dofile(source_root .. "/scripts/settings/ability/ability_templates/veteran_combat_ability.lua")
require = original_require

local hooks, defers, options, other_mods = {}, {}, {}, {}
local runtime = { clock = 0, active = true, hits = 0, retries = 0 }
function runtime:get(key) return options[key] ~= false end
function runtime:is_active() return self.active end
function runtime:record_hit() self.hits = self.hits + 1 end
function runtime:record_action() self.retries = self.retries + 1 end
function runtime:defer_file(_, path, callback) defers[path] = callback end
function runtime:install_hook(_, path, method, kind, callback)
	assert(kind == "safe")
	hooks[path .. ":" .. method] = callback
end
function runtime:set_available(_, value) self.active = value end
function runtime:run(_, callback, ...)
	local ok, value = pcall(callback, ...)
	assert(ok, value)
	return ok, value
end
local mod = { _tf_runtime = runtime }
function get_mod(name) return name == "TertiumFixes" and mod or other_mods[name] end
local module = dofile("scripts/mods/TertiumFixes/modules/input_retry.lua")
module:install()
defers[loadout_path](game_loadout)
local after_parse = assert(hooks[handler_path .. ":_parse_input"])
local after_action = assert(hooks[action_path .. ":start_action"])
local after_correction = assert(hooks[action_path .. ":server_correction_occurred"])
local after_sequence = assert(hooks[parser_path .. ":_progress_input_sequence"])

local function world()
	module:reset()
	options, other_mods = {}, {}
	runtime.clock, runtime.active, runtime.hits, runtime.retries = 0, true, 0, 0
	local unit = {}
	local player = { player_unit = unit, local_player_id = function () return 1 end }
	local inventory = { wielded_slot = "slot_primary" }
	for slot in pairs(slot_inputs) do inventory[slot] = slot .. "_item" end
	local character = { state_name = "walking" }
	local weapon_action = { current_action_name = "none", start_t = -1 }
	local combat_action = { current_action_name = "none", start_t = -1 }
	local components = { inventory = inventory, character_state = character, weapon_action = weapon_action, combat_ability_action = combat_action }
	local ability = {
		_equipped_abilities = { combat_ability = {}, grenade_ability = { inventory_item_reference = "content/items/weapons/player/zealot_throwing_knives" } },
		usable = true, active = false, charges = 2,
		has_ability_type = function (self, kind) return self._equipped_abilities[kind] ~= nil end,
		can_use_ability = function (self) return self.usable and self.charges > 0 end,
		is_ability_active = function (self) return self.active end,
		get_slot_name = function (_, kind) return "slot_" .. kind end,
		can_wield = function () return true end,
		can_be_scroll_wielded = function () return true end,
	}
	local function parser(component)
		return {
			_unit = unit, _ring_buffer_index = 1, _MAX_ACTION_INPUT_QUEUE = 4,
			_action_component = component or { template_name = "weapon" },
			_action_input_queue = { { {}, {} } }, _sequences = { { {}, {}, {} } },
			_stop_running_sequence = GameParser._stop_running_sequence,
		}
	end
	local parsers = { weapon_action = parser(), combat_ability_action = parser() }
	local extensions = {
		unit_data_system = { read_component = function (_, name) return assert(components[name], name) end },
		action_input_system = { _action_input_parsers = parsers },
		weapon_system = { can_wield = function () return true end, can_be_scroll_wielded = function () return true end },
		ability_system = ability,
		visual_loadout_system = { slot_configuration = function () return constants.slot_configuration end, current_wielded_slot_scripts = function () end, can_wield = function () return true end },
		input_system = { get = function () return true end },
	}
	ALIVE = { [unit] = true }
	ScriptUnit = { has_extension = function (target, system) return target == unit and extensions[system] end }
	local ui = { menu = false, chat = false, locked = {} }
	function ui:has_active_view() return self.menu end
	function ui:chat_using_input() return self.chat end
	function ui:inputs_in_use() return self.locked end
	local sent
	local session = { fixed_time_step = 1 / 60, can_send_session_bound_rpcs = function () return true end }
	function session:send_rpc_server(name, id, frame, offset, ...)
		sent = { name = name, id = id, frame = frame, offset = offset, values = { ... } }
	end
	Managers = { player = { local_player = function () return player end }, ui = ui, state = { game_session = session } }
	local service = { values = {}, null = false, _actions = {}, _aliases = {} }
	function service:is_null_service() return self.null end
	function service:get_with_filters(name) return self.values[name] or false end
	local handler = setmetatable({
		_player = player, _frame = 0, _last_frame_parsed = -1, _input_buffer_size = 600,
		_action_lookup = {}, _input_cache = {}, _ephemeral_action_cache = {},
		_actions = input_settings.actions, _num_actions = #input_settings.actions,
		_ephemeral_actions = input_settings.ephemeral_actions, _num_ephemeral_actions = #input_settings.ephemeral_actions,
		_num_ui_interaction_actions = 0, _num_input_settings = 0, _num_pack_unpack_actions = 0,
		_input_settings = {}, _pack_unpack_actions = {}, _input_settings_table = {},
		_send_buffer_size = 20, _last_frame_acknowledged = 0, _last_sent_frame = nil, _send_array = {},
	}, { __index = GameInput })
	for i, input in ipairs(input_settings.actions) do handler._action_lookup[input] = i end
	for i, input in ipairs(input_settings.ephemeral_actions) do handler._action_lookup[input] = #input_settings.actions + i end
	for name, index in pairs(handler._action_lookup) do
		handler._input_cache[index] = {}
		handler._send_array[index] = {}
		service._actions[name] = { key_alias = name }
		service._aliases[name] = { name .. "_key" }
	end
	local w = { unit = unit, player = player, handler = handler, service = service, inventory = inventory,
		ability = ability, character = character, ui = ui, parsers = parsers, weapon_action = weapon_action,
		combat_action = combat_action, extensions = extensions, activations = 0 }
	function w:tick(seconds, values)
		runtime.clock = runtime.clock + (seconds or 1 / 60)
		handler._frame = handler._frame + 1
		service.values = values or {}
		for i, input in ipairs(input_settings.ephemeral_actions) do handler._ephemeral_action_cache[i] = service.values[input] or false end
		local index = handler:_buffer_index(handler._frame)
		GameInput._parse_input(handler, handler._input_cache, service, index)
		after_parse(handler, handler._input_cache, service, index)
		return index
	end
	function w:input(name) return handler:get(name, handler._frame) end
	function w:state() return module._handlers[handler] end
	function w:ack(raw, id, kind, time)
		id = id or "weapon_action"
		local component = id == "combat_ability_action" and combat_action or weapon_action
		local t = time or handler._frame / 60
		local action = { start = function () self.activations = self.activations + 1 end }
		local action_handler = {
			_unit = unit, _registered_components = { [id] = { component = component } },
			_inventory_component = inventory,
			_unit_data_extension = { read_component = function () return { special_active = false } end },
			_visual_loadout_extension = extensions.visual_loadout_system,
			_buff_extension = { request_proc_event_param_table = function () end },
			_fill_action_start_params = function () end, _calculate_time_scale = function () return 1 end,
			_calculate_action_total_time = function () return 0.2 end, _anim_event = function () end,
			_update_combo_count = function () end,
		}
		component.combo_count, component.action_context_id = 0, 0
		local settings = { kind = kind or "activate_special" }
		GameAction.start_action(action_handler, id, { accepted = action }, "accepted", {}, settings, raw, t, "start", {})
		after_action(action_handler, id, { accepted = action }, "accepted", {}, settings, raw, t)
	end
	function w:send()
		GameInput.update(handler)
		return sent
	end
	function w:correct(raw, id, name, time)
		id = id or "weapon_action"
		name = name or "corrected"
		local component = id == "combat_ability_action" and combat_action or weapon_action
		component.current_action_name = name
		component.used_input = raw
		component.start_t = time or handler._frame / 60
		local action = { server_correction_occurred = function () self.corrections = (self.corrections or 0) + 1 end }
		local action_handler = {
			_unit = unit, _registered_components = { [id] = { component = component } },
			_fill_action_start_params = function () end,
		}
		GameAction.server_correction_occurred(action_handler, unit, handler._frame, handler._frame, id, { [name] = action }, {}, {})
		after_correction(action_handler, unit, handler._frame, handler._frame, id)
	end
	return w
end

local w = world()
w:tick(0, { quick_wield = true })
check(w:input("wield_2") and not w:input("quick_wield") and w:state().swap.target == "slot_secondary", "quick swap captures a fixed destination through the game's slot helper")
w:tick(0.11)
check(w:input("wield_2") and runtime.retries == 1, "a missed swap gets a bounded retry in the real input cache")
local sent = w:send()
check(sent.name == "rpc_player_input_array" and sent.values[w.handler._action_lookup.wield_2][2] == true, "the game's normal input RPC includes the retry, matching local prediction")
w:ack("wield_2", "weapon_action", "unwield")
w:tick(0.11)
check(not w:input("wield_2"), "an accepted unwield action is allowed to finish without repeated presses")
w.inventory.wielded_slot = "slot_secondary"
w:tick(0.11)
check(not w:state().swap and not w:input("quick_wield") and not w:input("wield_1"), "arrival at the requested slot stops the retry without swapping back")

w = world()
w:tick(0, { wield_scroll_up = true })
check(w:state().swap.target == "slot_grenade_ability" and w:input("grenade_ability_pressed"), "scroll selection follows the current game's slot order")
w:tick(0.05, { wield_1 = true })
check(not w:state().swap, "selecting the current slot cancels an opposite pending swap")
w:tick(0.2)
check(not w:input("grenade_ability_pressed"), "cancelled scroll intent does not return later")

w = world()
w:tick(0, { wield_2 = true })
w:tick(0.02, { weapon_extra_pressed = true })
check(not w:input("weapon_extra_pressed") and w:state().action.slot == "slot_secondary", "a special queued behind a swap cannot fire on the old weapon")
w:tick(0.2)
check(not w:input("weapon_extra_pressed"), "queued special waits while the requested weapon is still unavailable")
w.inventory.wielded_slot = "slot_secondary"
w:tick(0.01)
check(w:input("weapon_extra_pressed"), "queued special runs after the requested weapon arrives")
w:ack("weapon_extra_pressed")
w:tick(0.2)
check(not w:input("weapon_extra_pressed") and w.activations == 1 and not w:state().action, "acknowledged special cannot toggle itself a second time")

w = world()
w:tick(0, { combat_ability_pressed = true, combat_ability_hold = true })
w:tick(0.11, { combat_ability_hold = true })
check(w:input("combat_ability_pressed") and w:input("combat_ability_hold") and not w:input("combat_ability_release"), "ability retry preserves a held aim input")
w:ack("combat_ability_pressed", "combat_ability_action", "shout_aim")
w:tick(0.2, { combat_ability_hold = true })
check(not w:input("combat_ability_pressed") and w:input("combat_ability_hold") and w.ability.charges == 2, "ability acknowledgement stops retrying without directly changing charges or hold state")
w:tick(0.1, { combat_ability_release = true })
check(w:input("combat_ability_release") and not w:input("combat_ability_hold"), "the user's ability release remains unchanged")

w = world()
w:tick(0, { combat_ability_pressed = true })
w:tick(0.11)
w:ack("combat_ability_pressed", "combat_ability_action")
w:tick(0.01)
check(not w:input("combat_ability_release") and not w:input("combat_ability_pressed") and not w:input("combat_ability_hold"), "a delayed ability tap leaves both physical release and hold state unchanged")
local released = GameParser._evaluate_input(
	{ _input_aliases = { wielded_input_hold = { "combat_ability_hold" } } },
	veteran_ability.action_inputs.combat_ability_released.input_sequence[1],
	{ combat_ability_hold = w:input("combat_ability_hold") }
)
check(released, "the current Veteran template releases aim from hold=false without a fabricated ability-release edge")
w:tick(0.1)
check(not w:input("combat_ability_release"), "an acknowledged ability cannot receive a later fabricated release")

w = world()
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.11)
w:ack("weapon_extra_pressed")
w:tick(0.01)
check(w:input("weapon_extra_release") and not w:input("weapon_extra_pressed"), "a delayed special tap supplies the release edge used by weapon action sequences")
w:tick(0.1)
check(not w:input("weapon_extra_release"), "a delayed special emits its release once")

local release_cancellations = {
	{ "release key locked by UI", function (v) v.ui.locked.weapon_extra_release_key = true end },
	{ "press key locked by UI", function (v) v.ui.locked.weapon_extra_pressed_key = true end },
	{ "wielded slot changed", function (v) v.inventory.wielded_slot = "slot_secondary" end },
	{ "weapon item changed", function (v) v.inventory.slot_primary = "new_item" end },
}
for _, case in ipairs(release_cancellations) do
	w = world()
	w:tick(0, { weapon_extra_pressed = true })
	w:tick(0.11)
	w:ack("weapon_extra_pressed")
	case[2](w)
	w:tick(0.01)
	check(not w:input("weapon_extra_release"), "deferred release is discarded when " .. case[1])
end
w = world()
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.11)
w:tick(0.01, { action_two_pressed = true })
check(not w:input("weapon_extra_release"), "a new blocking input cancels the deferred special release too")

w = world()
w:tick(0, { weapon_reload_pressed = true })
w.parsers.weapon_action._action_input_queue[1][2][1] = "weapon_reload_pressed"
w:tick(0.2)
check(not w:input("weapon_reload_pressed"), "native queued reload is not duplicated")
w.parsers.weapon_action._action_input_queue[1][2][1] = nil
w:tick(0.01)
check(w:input("weapon_reload_pressed"), "a reload retries after the native queue drops it")
w:ack("weapon_reload_pressed", "weapon_action", "reload")
w:tick(0.2)
check(not w:input("weapon_reload_pressed"), "reload acknowledgement stops further input")

w = world()
w:tick(0, { weapon_extra_pressed = true })
local parser = w.parsers.weapon_action
local sequences = parser._sequences[1]
sequences[2][1] = 1
GameParser._progress_input_sequence(parser, sequences, 1, w.handler._frame / 60, { elements = { {}, {} } }, {}, "weapon_extra_pressed", {})
after_sequence(parser, sequences, 1, w.handler._frame / 60, {}, {}, "weapon_extra_pressed")
w:tick(0.2)
check(not w:input("weapon_extra_pressed"), "a recognised multi-step input sequence is not restarted")
GameParser._stop_running_sequence(parser, sequences, 1)
w:tick(0.01)
check(w:input("weapon_extra_pressed"), "a dropped sequence can retry inside the original time window")

w = world()
w:tick(0, { grenade_ability_pressed = true })
w:tick(0.11)
check(w:input("grenade_ability_pressed") and w:state().action.kind == "blitz", "metadata-confirmed quick Blitz uses an action retry")
w:ack("grenade_ability_pressed", "weapon_action", "spawn_projectile")
w:tick(0.2)
check(not w:input("grenade_ability_pressed") and w.ability.charges == 2, "accepted quick Blitz cannot be repeated or consume a charge directly")
w = world()
w.ability._equipped_abilities.grenade_ability.inventory_item_reference = "ordinary_grenade"
w:tick(0, { grenade_ability_pressed = true, grenade_ability_hold = true })
check(w:state().swap and not w:state().action and w:input("grenade_ability_hold"), "an aimed grenade remains a wield request with the original hold")
w.inventory.wielded_slot = "slot_grenade_ability"
w:tick(0.2, { grenade_ability_hold = true })
check(not w:input("grenade_ability_pressed") and w:input("grenade_ability_hold"), "aimed grenade retries stop on wield without inventing a throw")

local cancellations = {
	{ "menu", function (v) v.ui.menu = true end, function (v) v.ui.menu = false end },
	{ "chat", function (v) v.ui.chat = true end, function (v) v.ui.chat = false end },
	{ "HUD input ownership", function (v)
		v.ui.overlay = true
		v.ui.using_input = function (self) return self.overlay end
	end, function (v) v.ui.overlay = false end },
	{ "developer UI input ownership", function ()
		Managers.imgui = { using_input = function () return true end }
	end, function () Managers.imgui = nil end },
	{ "null input service", function (v) v.service.null = true end, function (v) v.service.null = false end },
	{ "downed state", function (v) v.character.state_name = "knocked_down" end, function (v) v.character.state_name = "walking" end },
	{ "death", function (v) ALIVE[v.unit] = false end, function (v) ALIVE[v.unit] = true end },
	{ "luggable slot", function (v) v.inventory.wielded_slot = "slot_item" end, function (v) v.inventory.wielded_slot = "slot_primary" end },
	{ "interaction", function (v) v.character.state_name = "interacting" end, function (v) v.character.state_name = "walking" end },
	{ "weapon replacement", function (v) v.inventory.slot_primary = "new_weapon" end, function () end },
	{ "disabled input extension", function (v) v.extensions.action_input_system._disabled = true end, function (v) v.extensions.action_input_system._disabled = false end },
	{ "deleted ability extension", function (v) v.extensions.ability_system.__deleted = true end, function (v) v.extensions.ability_system.__deleted = false end },
}
for _, case in ipairs(cancellations) do
	w = world()
	w:tick(0, { weapon_extra_pressed = true })
	case[2](w)
	w:tick(0.11)
	case[3](w)
	w:tick(0.11)
	check(not w:input("weapon_extra_pressed") and runtime.retries == 0, case[1] .. " cancels the old intention instead of reviving it")
end

w = world()
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.01, { action_two_pressed = true, action_two_hold = true })
w:tick(0.2)
check(not w:input("weapon_extra_pressed"), "blocking or aiming cancels a waiting special")
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.01, { weapon_reload_pressed = true })
w:tick(0.2)
check(w:input("weapon_reload_pressed") and not w:input("weapon_extra_pressed"), "new reload intent replaces a waiting special")

w = world()
w:tick(0, { combat_ability_pressed = true })
w.ui.locked.combat_ability_pressed_key = true
w:tick(0.11)
check(not w:input("combat_ability_pressed") and not w:state().action, "per-key UI filtering also applies to a pending retry")
w = world()
w.ability.usable = false
w:tick(0, { combat_ability_pressed = true })
w.ability.usable = true
w:tick(0.2)
check(not w:input("combat_ability_pressed"), "pressing on cooldown cannot schedule activation when it later becomes ready")
w = world()
w.ability.active = true
w:tick(0, { combat_ability_pressed = true })
check(w:input("combat_ability_pressed") and not w:state().action, "an active ability keeps its deliberate toggle/cancel input without buffering it")

w = world()
w:tick(0, { weapon_extra_pressed = true })
w:ack(nil)
w:tick(0.11)
check(w:input("weapon_extra_pressed"), "an unrelated automatic action is not a false acknowledgement")
w:ack("weapon_extra_pressed", "weapon_action", nil, -1)
w:tick(0.11)
check(w:input("weapon_extra_pressed"), "an old resimulated action cannot acknowledge a newer intention")
w:ack("weapon_extra_pressed")
w:ack("weapon_extra_pressed", "weapon_action", nil, -1)
w:tick(0.11)
check(not w:input("weapon_extra_pressed") and not w:state().action, "replayed acknowledgements cannot recreate a completed intention")

w = world()
w:tick(0, { weapon_extra_pressed = true })
w:correct("weapon_extra_pressed")
w:tick(0.11)
check(w.corrections == 1 and not w:input("weapon_extra_pressed") and not w:state().action, "the game's authoritative correction acknowledges a special without a second press")
w = world()
w:tick(0, { weapon_extra_pressed = true })
w:correct("weapon_extra_pressed", "weapon_action", "none")
w:tick(0.11)
check(not w:input("weapon_extra_pressed") and not w:state().action, "an already completed authoritative special is also acknowledged")
w = world()
w:tick(0, { weapon_extra_pressed = true })
w:correct("weapon_extra_pressed", "weapon_action", "corrected", -1)
w:tick(0.11)
check(w:input("weapon_extra_pressed"), "an older authoritative action cannot consume a new intention")
w = world()
w:tick(0, { weapon_extra_pressed = true })
w:correct("action_one_pressed")
w:tick(0.11)
check(w:input("weapon_extra_pressed"), "an unrelated authoritative action cannot consume a special intention")
w = world()
w:tick(0, { combat_ability_pressed = true })
w:correct("combat_ability_pressed", "combat_ability_action")
w:tick(0.11)
check(not w:input("combat_ability_pressed") and not w:state().action, "combat abilities also acknowledge authoritative action correction")
w = world()
w:tick(0, { wield_2 = true })
w:correct("wield_2")
w:tick(0.11)
check(not w:input("wield_2") and w:state().swap, "an authoritative unwield pauses retries while its action runs")
w:correct("wield_2", "weapon_action", "none")
w:tick(0.11)
check(w:input("wield_2") and w:state().swap, "a corrected interrupted swap may retry until its target slot arrives")

w = world()
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.75)
check(not w:input("weapon_extra_pressed") and not w:state().action, "retry expires at the original 0.75-second deadline")
w = world()
w.handler._player = { player_unit = w.unit, local_player_id = function () return 2 end }
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.2)
check(runtime.hits == 0 and not w:input("weapon_extra_pressed"), "another player's input handler is left alone")
w = world()
other_mods.guarantee_special_action = { is_enabled = function () return true end }
w:tick(0, { weapon_extra_pressed = true })
w:tick(0.2)
check(not w:input("weapon_extra_pressed") and runtime.hits == 0, "enabled standalone buffering takes precedence for its own actions")
w = world()
w:tick(0, { weapon_reload_pressed = true })
module:on_game_state_changed()
w:tick(0.2)
check(not w:input("weapon_reload_pressed"), "game-state changes discard queued input")

print(string.format("\n%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
