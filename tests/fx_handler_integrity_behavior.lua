local failures = 0
local checks = 0

local function check(condition, message)
	checks = checks + 1

	if condition then
		io.write("PASS " .. message .. "\n")
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local FX_SYSTEM_PATH = "scripts/extension_systems/fx/fx_system"
local HANDLER_PATH =
	"scripts/extension_systems/fx/utilities/effect_templates_handler"

local settings = {
	auto_quarantine_enabled = true,
	auto_quarantine_threshold = 3,
	diagnostic_logging = false,
	fx_handler_integrity_enabled = true,
	fx_handler_local_rewrite_enabled = true,
	fx_handler_rpc_idempotence_enabled = true,
}
local registrations = {}
local registration_counts = {}
local hook_counts = {
	normal = 0,
	safe = 0,
}
local require_calls = 0

local mod = {
	enabled = true,
}

function mod:echo(_, ...)
end

function mod:error(_, ...)
end

function mod:get(setting_id)
	return settings[setting_id]
end

function mod:info(_, ...)
end

function mod:is_enabled()
	return self.enabled
end

function mod:warning(_, ...)
end

function mod:hook_require(file_path, callback)
	registration_counts[file_path] =
		(registration_counts[file_path] or 0) + 1
	registrations[file_path] = callback
end

function mod:hook(target, method_name, handler)
	local original = target[method_name]

	hook_counts.normal = hook_counts.normal + 1
	target[method_name] = function (...)
		return handler(original, ...)
	end
end

function mod:hook_safe(target, method_name, handler)
	local original = target[method_name]

	hook_counts.safe = hook_counts.safe + 1
	target[method_name] = function (...)
		local a, b, c, d = original(...)

		handler(...)

		return a, b, c, d
	end
end

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	end

	return nil
end

local original_require = require

require = function (...)
	require_calls = require_calls + 1

	return original_require(...)
end

local runtime = dofile("scripts/mods/TertiumFixes/core.lua")

mod._tf_runtime = runtime

local module = dofile(
	"scripts/mods/TertiumFixes/modules/fx_handler_integrity.lua"
)

check(runtime:add_module(module), "FX handler module registers with the runtime")

runtime:install_modules()
module:install()
runtime:install_modules()

check(require_calls == 0, "installation never eagerly requires a game file")
check(
	registration_counts[FX_SYSTEM_PATH] == 1
		and registration_counts[HANDLER_PATH] == 1,
	"one aggregated deferred callback is registered per game file"
)

local function remove_running_reference(handler, template_effect)
	local running = handler._running_template_effects

	for i = 1, #running do
		if running[i] == template_effect then
			running[i] = running[#running]
			running[#running] = nil

			return
		end
	end
end

local HandlerClass = {}

function HandlerClass:has_running_effect_with_global_id(global_effect_id)
	local buffer_index =
		global_effect_id % self._max_num_template_effects + 1

	return self._template_effects[buffer_index].template ~= nil
end

function HandlerClass:start_template_effect(
		unit_to_particle_group_lookup,
		template_context,
		template_effect,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	template.start(template_effect.template_data, template_context, optional_unit)
	template_effect.optional_unit = optional_unit
	template_effect.optional_node = optional_node
	template_effect.optional_position = optional_position
	template_effect.optional_player_owner_unit = optional_player_owner_unit
	template_effect.is_running = true
	template_effect.template = template
	self._running_template_effects[#self._running_template_effects + 1] =
		template_effect
end

function HandlerClass:stop_template_effect(
		template_context,
		template_effect,
		template
	)
	template.stop(template_effect.template_data, template_context)
	template_effect.optional_unit = nil
	template_effect.optional_node = nil
	template_effect.optional_position = nil
	template_effect.optional_player_owner_unit = nil
	template_effect.is_running = false
	template_effect.template = nil
	remove_running_reference(self, template_effect)
	self.stop_calls = self.stop_calls + 1
end

function HandlerClass:add_template_effect(
		unit_to_particle_group_lookup,
		template_context,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	local global_effect_id = self._next_global_effect_id
	local template_effect
	local buffer_index

	for i = 1, self._max_num_template_effects do
		buffer_index =
			global_effect_id % self._max_num_template_effects + 1
		template_effect = self._template_effects[buffer_index]

		if not template_effect.is_running then
			break
		elseif i < self._max_num_template_effects then
			global_effect_id = global_effect_id + 1
		end
	end

	if template_effect.is_running then
		self:remove_template_effect(
			template_context,
			template_effect.global_effect_id
		)
	end

	self:start_template_effect(
		unit_to_particle_group_lookup,
		template_context,
		template_effect,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	template_effect.global_effect_id = global_effect_id
	self._next_global_effect_id = global_effect_id + 1
	self.rpc_starts = self.rpc_starts + 1

	return global_effect_id
end

function HandlerClass:remove_template_effect(
		template_context,
		global_effect_id
	)
	local buffer_index =
		global_effect_id % self._max_num_template_effects + 1
	local template_effect = self._template_effects[buffer_index]

	if template_effect.global_effect_id ~= global_effect_id then
		return
	end

	local player_owned =
		template_effect.optional_player_owner_unit ~= nil

	self:stop_template_effect(
		template_context,
		template_effect,
		template_effect.template
	)
	template_effect.global_effect_id = nil
	self.rpc_stops = self.rpc_stops + 1
	self.last_stop_was_player_owned = player_owned
end

function HandlerClass:update(template_context, dt, t)
	local effects_to_stop = {}

	for i = 1, #self._running_template_effects do
		local template_effect = self._running_template_effects[i]
		local stop_effect = template_effect.template.update(
			template_effect.template_data,
			template_context,
			dt,
			t
		)

		if template_context.is_server
			and self._allow_template_effects_life_time
			and stop_effect then
			effects_to_stop[#effects_to_stop + 1] =
				template_effect.global_effect_id
		end
	end

	if template_context.is_server then
		for i = 1, #effects_to_stop do
			self:remove_template_effect(
				template_context,
				effects_to_stop[i]
			)
		end
	end
end

function HandlerClass:remove_effects_on_unit(template_context, unit)
	for i = #self._running_template_effects, 1, -1 do
		local template_effect = self._running_template_effects[i]

		if template_effect.optional_unit == unit then
			self:stop_template_effect(
				template_context,
				template_effect,
				template_effect.template
			)
		end
	end
end

function HandlerClass:clear(template_context)
	for i = #self._running_template_effects, 1, -1 do
		local template_effect = self._running_template_effects[i]

		self:stop_template_effect(
			template_context,
			template_effect,
			template_effect.template
		)
	end
end

function HandlerClass:start_template_effect_from_rpc(
		unit_to_particle_group_lookup,
		template_context,
		buffer_index,
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
	self:start_template_effect(
		unit_to_particle_group_lookup,
		template_context,
		self._template_effects[buffer_index],
		template,
		optional_unit,
		optional_node,
		optional_position,
		optional_player_owner_unit
	)
end

function HandlerClass:stop_template_effect_from_rpc(
		template_context,
		buffer_index
	)
	local template_effect = self._template_effects[buffer_index]

	self:stop_template_effect(
		template_context,
		template_effect,
		template_effect.template
	)
end

local FxSystemClass = {}

function FxSystemClass:init(local_handler)
	self._local_effect_templates_handler = local_handler
end

registrations[FX_SYSTEM_PATH](FxSystemClass)
registrations[HANDLER_PATH](HandlerClass)

local applied_normal_hooks = hook_counts.normal
local applied_safe_hooks = hook_counts.safe

registrations[FX_SYSTEM_PATH](FxSystemClass)
registrations[HANDLER_PATH](HandlerClass)

check(
	hook_counts.normal == applied_normal_hooks
		and hook_counts.safe == applied_safe_hooks
		and applied_normal_hooks == 7
		and applied_safe_hooks == 2,
	"deferred callbacks apply nine hooks once even when replayed"
)

local function new_handler(max_num_template_effects, allow_lifetime)
	local handler = {
		_allow_template_effects_life_time = allow_lifetime,
		_max_num_template_effects = max_num_template_effects,
		_next_global_effect_id = 0,
		_running_template_effects = {},
		_template_effects = {},
		last_stop_was_player_owned = false,
		rpc_starts = 0,
		rpc_stops = 0,
		stop_calls = 0,
	}

	for i = 1, max_num_template_effects do
		handler._template_effects[i] = {
			buffer_index = i,
			global_effect_id = nil,
			is_running = false,
			template = nil,
			template_data = {},
		}
	end

	return setmetatable(handler, {
		__index = HandlerClass,
	})
end

local function new_template(name, stop_on_update)
	local counters = {
		starts = 0,
		stops = 0,
		updates = 0,
	}
	local template = {
		name = name,
	}

	function template.start()
		counters.starts = counters.starts + 1
	end

	function template.stop()
		counters.stops = counters.stops + 1
	end

	function template.update()
		counters.updates = counters.updates + 1

		return stop_on_update == true
	end

	return template, counters
end

local client_context = {
	is_server = false,
}
local lookup = {}
local local_handler = new_handler(2, true)
local network_handler = new_handler(2, true)
local fx_system = setmetatable({}, {
	__index = FxSystemClass,
})

fx_system:init(local_handler)

check(
	local_handler._tertium_local_only == true
		and network_handler._tertium_local_only == nil,
	"FX initialization marks only the dedicated local handler"
)

local local_template, local_counters = new_template("local_lifetime", true)
local attachment_unit = {}
local owner_unit = {}
local local_id = local_handler:add_template_effect(
	lookup,
	client_context,
	local_template,
	attachment_unit,
	7,
	{ x = 1 },
	owner_unit
)

check(
	local_id == 0
		and local_handler.rpc_starts == 0
		and local_handler._template_effects[1].optional_unit ==
			attachment_unit
		and local_handler._template_effects[1].optional_player_owner_unit ==
			owner_unit,
	"marked local allocation preserves arguments and emits no start RPC"
)
check(
	local_handler:has_running_effect_with_global_id(local_id) == true
		and local_handler:has_running_effect_with_global_id(local_id + 2) ==
			false,
	"global-ID queries require an exact live ring-buffer generation"
)

local invalid_query_ok, invalid_query_result = pcall(
	local_handler.has_running_effect_with_global_id,
	local_handler,
	-1
)

check(
	invalid_query_ok and invalid_query_result == false,
	"invalid global IDs are rejected without arithmetic errors"
)

local_handler:update(client_context, 0.016, 1)

local first_scratch = local_handler._tertium_effects_to_stop

check(
	local_counters.updates == 1
		and local_counters.stops == 1
		and local_handler.rpc_stops == 0
		and local_handler._template_effects[1].global_effect_id == nil,
	"client lifetime expiry stops local FX and emits no stop RPC"
)

local_handler:add_template_effect(
	lookup,
	client_context,
	local_template,
	nil,
	nil,
	nil,
	nil
)
local_handler:update(client_context, 0.016, 2)

check(
	first_scratch == local_handler._tertium_effects_to_stop,
	"local lifetime updates reuse per-handler scratch storage"
)

local ring_handler = new_handler(1, true)

module:_mark_local_handler(ring_handler)

local ring_template, ring_counters = new_template("ring", false)
local old_id = ring_handler:add_template_effect(
	lookup,
	client_context,
	ring_template
)

ring_handler:remove_template_effect(client_context, old_id)

local current_id = ring_handler:add_template_effect(
	lookup,
	client_context,
	ring_template
)

ring_handler:remove_template_effect(client_context, old_id)

check(
	current_id == old_id + 1
		and ring_handler:has_running_effect_with_global_id(old_id) == false
		and ring_handler:has_running_effect_with_global_id(current_id) == true
		and ring_counters.stops == 1,
	"stale generation removal cannot stop a reused slot"
)

local stress_handler = new_handler(4, true)

module:_mark_local_handler(stress_handler)

local stress_template, stress_counters = new_template("stress", false)
local first_evicted_stress_id
local latest_stress_id

for i = 1, 300 do
	latest_stress_id = stress_handler:add_template_effect(
		lookup,
		client_context,
		stress_template
	)

	if i == 4 then
		first_evicted_stress_id = latest_stress_id
	end
end

local stale_stress_remove_ok = pcall(
	stress_handler.remove_template_effect,
	stress_handler,
	client_context,
	first_evicted_stress_id
)

check(
	stale_stress_remove_ok
		and latest_stress_id == 299
		and #stress_handler._running_template_effects == 4
		and stress_handler:has_running_effect_with_global_id(
			first_evicted_stress_id
		) == false
		and stress_handler:has_running_effect_with_global_id(
			latest_stress_id
		) == true
		and stress_counters.starts == 300
		and stress_counters.stops == 296
		and stress_handler.rpc_starts == 0
		and stress_handler.rpc_stops == 0,
	"300 ring allocations stay bounded and reject an evicted generation"
)

local corrupt_ring_handler = new_handler(1, true)

module:_mark_local_handler(corrupt_ring_handler)

local corrupt_old_template, corrupt_old_counters =
	new_template("corrupt_old", false)
local corrupt_new_template, corrupt_new_counters =
	new_template("corrupt_new", false)

corrupt_ring_handler:add_template_effect(
	lookup,
	client_context,
	corrupt_old_template
)

local corrupt_slot = corrupt_ring_handler._template_effects[1]

corrupt_slot.global_effect_id = nil

local repaired_corrupt_id = corrupt_ring_handler:add_template_effect(
	lookup,
	client_context,
	corrupt_new_template
)

check(
	repaired_corrupt_id == 1
		and corrupt_old_counters.stops == 1
		and corrupt_new_counters.starts == 1
		and #corrupt_ring_handler._running_template_effects == 1
		and corrupt_slot.is_running == true
		and corrupt_slot.template == corrupt_new_template
		and corrupt_slot.global_effect_id == repaired_corrupt_id
		and corrupt_ring_handler.rpc_starts == 0,
	"a saturated corrupt slot is stopped before one replacement starts"
)

local failed_stop_handler = new_handler(1, true)

module:_mark_local_handler(failed_stop_handler)

local uncooperative_template = new_template("uncooperative", false)
local blocked_template, blocked_counters = new_template("blocked", false)

failed_stop_handler:add_template_effect(
	lookup,
	client_context,
	uncooperative_template
)

function uncooperative_template.stop()
	error("simulated teardown failure")
end

local blocked_id = failed_stop_handler:add_template_effect(
	lookup,
	client_context,
	blocked_template
)
local uncooperative_slot = failed_stop_handler._template_effects[1]

check(
	blocked_id == nil
		and blocked_counters.starts == 0
		and uncooperative_slot.is_running == true
		and uncooperative_slot.template == uncooperative_template
		and uncooperative_slot._tertium_fx_slot_quarantined == true
		and #failed_stop_handler._running_template_effects == 0,
	"failed saturated teardown quarantines the slot instead of double-starting"
)

local malformed_handler = new_handler(1, true)

module:_mark_local_handler(malformed_handler)

local malformed_slot = malformed_handler._template_effects[1]

malformed_slot.global_effect_id = 0
malformed_slot.is_running = true
malformed_slot.template = {}
malformed_handler._running_template_effects[1] = malformed_slot

local malformed_actions_before = module.state.actions
local malformed_first_ok = pcall(
	malformed_handler.update,
	malformed_handler,
	client_context,
	0.016,
	3
)
local malformed_actions_after_first = module.state.actions
local malformed_second_ok = pcall(
	malformed_handler.update,
	malformed_handler,
	client_context,
	0.016,
	4
)

check(
	malformed_first_ok
		and malformed_second_ok
		and malformed_actions_after_first == malformed_actions_before + 1
		and module.state.actions == malformed_actions_after_first
		and #malformed_handler._running_template_effects == 0
		and malformed_slot._tertium_fx_slot_quarantined == true,
	"a malformed live entry is quarantined once without per-frame churn"
)

ring_handler:remove_template_effect(client_context, current_id)
ring_handler:remove_template_effect(client_context, current_id)

check(
	ring_counters.stops == 2
		and ring_handler.rpc_stops == 0
		and ring_handler._template_effects[1].global_effect_id == nil,
	"local removal is idempotent and never sends a stop RPC"
)

local network_template, network_counters = new_template("network", false)
local network_id = network_handler:add_template_effect(
	lookup,
	client_context,
	network_template
)

network_handler:remove_template_effect(client_context, network_id)
network_handler:remove_template_effect(client_context, network_id)

check(
	network_handler.rpc_starts == 1
		and network_handler.rpc_stops == 1
		and network_counters.stops == 1,
	"unmarked handlers retain vanilla RPC ownership with idempotent removal"
)

local teardown_handler = new_handler(3, true)
local target_unit = {}
local other_unit = {}
local attached_template, attached_counters = new_template("attached", false)
local owner_template, owner_counters = new_template("owner", false)
local attached_id = teardown_handler:add_template_effect(
	lookup,
	client_context,
	attached_template,
	target_unit,
	nil,
	nil,
	other_unit
)
local owner_id = teardown_handler:add_template_effect(
	lookup,
	client_context,
	owner_template,
	other_unit,
	nil,
	nil,
	target_unit
)

teardown_handler:remove_effects_on_unit(client_context, target_unit)

check(
	attached_counters.stops == 1
		and owner_counters.stops == 1
		and teardown_handler._template_effects[
			attached_id % teardown_handler._max_num_template_effects + 1
		].global_effect_id == nil
		and teardown_handler._template_effects[
			owner_id % teardown_handler._max_num_template_effects + 1
		].global_effect_id == nil,
	"unit teardown clears attachment and player-owner effects plus stale IDs"
)

local reentrant_handler = new_handler(1, true)

module:_mark_local_handler(reentrant_handler)

local reentrant_target = {}
local replacement_target = {}
local reentrant_old_template = new_template("reentrant_old", false)
local reentrant_new_template = new_template("reentrant_new", false)
local reentrant_old_id = reentrant_handler:add_template_effect(
	lookup,
	client_context,
	reentrant_old_template,
	reentrant_target
)
local reentrant_new_id

module:_remove_effects_on_unit(
	function (handler, template_context)
		local slot = handler._template_effects[1]

		handler:stop_template_effect(
			template_context,
			slot,
			slot.template
		)
		reentrant_new_id = handler:add_template_effect(
			lookup,
			template_context,
			reentrant_new_template,
			replacement_target
		)
	end,
	reentrant_handler,
	client_context,
	reentrant_target
)

local reentrant_slot = reentrant_handler._template_effects[1]

check(
	reentrant_new_id == reentrant_old_id + 1
		and reentrant_slot.is_running == true
		and reentrant_slot.template == reentrant_new_template
		and reentrant_slot.global_effect_id == reentrant_new_id
		and reentrant_handler:has_running_effect_with_global_id(
			reentrant_new_id
		) == true,
	"reentrant unit teardown preserves the replacement slot generation"
)

local clear_handler = new_handler(2, true)
local clear_template = new_template("clear", false)

clear_handler:add_template_effect(lookup, client_context, clear_template)
clear_handler:add_template_effect(lookup, client_context, clear_template)
clear_handler:clear(client_context)

check(
	clear_handler._template_effects[1].global_effect_id == nil
		and clear_handler._template_effects[2].global_effect_id == nil,
	"clear removes generation IDs left behind by the engine"
)

local rpc_handler = new_handler(1, true)
local rpc_first, rpc_first_counters = new_template("rpc_first", false)
local rpc_second, rpc_second_counters = new_template("rpc_second", false)

rpc_handler:start_template_effect_from_rpc(
	lookup,
	client_context,
	1,
	rpc_first
)
rpc_handler:start_template_effect_from_rpc(
	lookup,
	client_context,
	1,
	rpc_second
)

check(
	rpc_first_counters.stops == 1
		and rpc_second_counters.starts == 1
		and #rpc_handler._running_template_effects == 1
		and rpc_handler._template_effects[1].template == rpc_second,
	"duplicate RPC starts replace the occupied slot without duplicate roots"
)

rpc_handler:stop_template_effect_from_rpc(client_context, 1)
rpc_handler:stop_template_effect_from_rpc(client_context, 1)

local invalid_rpc_start_ok = pcall(
	rpc_handler.start_template_effect_from_rpc,
	rpc_handler,
	lookup,
	client_context,
	0,
	rpc_first
)
local invalid_rpc_stop_ok = pcall(
	rpc_handler.stop_template_effect_from_rpc,
	rpc_handler,
	client_context,
	2
)

check(
	rpc_second_counters.stops == 1
		and #rpc_handler._running_template_effects == 0
		and invalid_rpc_start_ok
		and invalid_rpc_stop_ok,
	"duplicate and invalid RPC stops are harmless"
)

settings.fx_handler_local_rewrite_enabled = false
runtime:setting_changed("fx_handler_local_rewrite_enabled")

local fallback_handler = new_handler(1, true)

module:_mark_local_handler(fallback_handler)

local fallback_template = new_template("fallback", false)
local fallback_id = fallback_handler:add_template_effect(
	lookup,
	client_context,
	fallback_template
)

fallback_handler:remove_template_effect(client_context, fallback_id)

check(
	fallback_handler.rpc_starts == 1
		and fallback_handler.rpc_stops == 1,
	"medium-risk local rewrite can be disabled independently"
)

settings.fx_handler_local_rewrite_enabled = true
runtime:setting_changed("fx_handler_local_rewrite_enabled")

local reconciled_handler = new_handler(1, true)

Managers = {
	state = {
		extension = {
			system = function (_, system_name)
				if system_name == "fx_system" then
					return {
						_local_effect_templates_handler = reconciled_handler,
					}
				end
			end,
		},
	},
}

module:on_all_mods_loaded()

check(
	reconciled_handler._tertium_local_only == true,
	"late installation reconciles an already-live local FX handler"
)
check(
	module.state.available == true and module.state.errors == 0,
	"all simulated lifecycle paths remain available without runtime errors"
)

io.write(
	string.format(
		"\n%s: %d checks, %d failures\n",
		failures == 0 and "OK" or "FAILED",
		checks,
		failures
	)
)

if failures > 0 then
	os.exit(1)
end
