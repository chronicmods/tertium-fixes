local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "event_listener_cleanup",
	label = "Engine event-listener teardown repair",
	setting_id = "event_listener_cleanup_enabled",
}

local INPUT_HAPTIC_EVENTS = {
	"event_update_haptic_trigger_melee_resistance_strength",
	"event_update_haptic_trigger_ranged_resistance_strength",
	"event_update_haptic_trigger_melee_vibration_strength",
	"event_update_haptic_trigger_ranged_vibration_strength",
}

local SURVIVAL_EVENTS = {
	"hordes_mode_on_mcguffin_picked_up",
}

local EXPEDITION_EVENTS = {
	"event_hogtied_player_rescued",
}

local function _unregister_events(owner, event_names)
	local managers = rawget(_G, "Managers")
	local event_manager = managers and managers.event
	local unregister = type(event_manager) == "table"
		and event_manager.unregister

	if owner == nil or type(unregister) ~= "function" then
		return 0
	end

	local removed = 0

	for i = 1, #event_names do
		unregister(event_manager, owner, event_names[i])
		removed = removed + 1
	end

	return removed
end

function module:_after_destroy(owner, event_names)
	if not runtime:is_active(self.id) then
		return
	end

	local ok, removed = runtime:run(
		self.id,
		_unregister_events,
		owner,
		event_names
	)

	if ok and removed > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, removed)
	end
end

function module:install()
	local input_ok = runtime:install_hook(
		self.id,
		"scripts/managers/input/input_manager",
		"destroy",
		"safe",
		function (input_manager)
			if rawget(_G, "IS_PLAYSTATION") == true then
				self:_after_destroy(input_manager, INPUT_HAPTIC_EVENTS)
			end
		end
	)
	local survival_ok = runtime:install_hook(
		self.id,
		"scripts/managers/game_mode/game_modes/game_mode_survival",
		"destroy",
		"safe",
		function (game_mode)
			self:_after_destroy(game_mode, SURVIVAL_EVENTS)
		end
	)
	local expedition_ok = runtime:install_hook(
		self.id,
		"scripts/utilities/expeditions/expedition_loot_handler",
		"destroy",
		"safe",
		function (loot_handler)
			if type(loot_handler) == "table"
				and rawget(loot_handler, "_is_server") == true then
				self:_after_destroy(loot_handler, EXPEDITION_EVENTS)
			end
		end
	)

	if not input_ok or not survival_ok or not expedition_ok then
		runtime:set_available(
			self.id,
			false,
			"one or more engine teardown hooks were unavailable"
		)
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "unregisters six source-confirmed listeners omitted by three stock destroy paths"
end

return module
