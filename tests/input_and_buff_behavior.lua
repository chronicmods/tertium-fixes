local passed = 0
local failed = 0

local function check(condition, name, detail)
    if condition then
        passed = passed + 1
        print("PASS: " .. name)
    else
        failed = failed + 1
        print("FAIL: " .. name .. (detail and (" (" .. detail .. ")") or ""))
    end
end

local function count_for(counters, module_id)
    return counters[module_id] or 0
end

-- Minimal DMF/runtime/require surface used by the production modules.
DEDICATED_SERVER = false

local input_device = {
    last_pressed_device = nil,
}

local original_require = require

function require(module_name)
    if module_name == "scripts/managers/input/input_device" then
        return input_device
    end

    return original_require(module_name)
end

local installed_hooks = {}
local availability = {}
local run_calls = {}
local run_callbacks = {}
local hits = {}
local actions = {}

local runtime = {}

function runtime:defer_file(_module_id, module_path, handler)
    if module_path ~= "scripts/managers/input/input_device" then
        return false
    end

    handler(input_device)

    return true
end

function runtime:is_active(_module_id)
    return true
end

function runtime:install_hook(module_id, class_path, method_name, hook_kind, handler)
    installed_hooks[module_id] = {
        class_path = class_path,
        method_name = method_name,
        hook_kind = hook_kind,
        handler = handler,
    }

    return true
end

function runtime:set_available(module_id, is_available, reason)
    availability[module_id] = {
        is_available = is_available,
        reason = reason,
    }
end

function runtime:run(module_id, callback, ...)
    run_calls[module_id] = count_for(run_calls, module_id) + 1
    run_callbacks[module_id] = run_callbacks[module_id] or {}
    table.insert(run_callbacks[module_id], callback)

    return pcall(callback, ...)
end

function runtime:record_hit(module_id, amount)
    hits[module_id] = count_for(hits, module_id) + (amount or 1)
end

function runtime:record_action(module_id, amount)
    actions[module_id] = count_for(actions, module_id) + (amount or 1)
end

local mod = {
    _tf_runtime = runtime,
}

function get_mod(mod_name)
    if mod_name ~= "TertiumFixes" then
        error("unexpected mod request: " .. tostring(mod_name))
    end

    return mod
end

local input_module = dofile("scripts/mods/TertiumFixes/modules/input_device_handoff.lua")
local buff_module = dofile("scripts/mods/TertiumFixes/modules/player_buff_removal.lua")

check(type(input_module) == "table", "input module loads")
check(type(buff_module) == "table", "buff module loads")
local input_install_ok = pcall(input_module.install, input_module)
local buff_install_ok = pcall(buff_module.install, buff_module)
check(input_install_ok, "input module installs")
check(buff_install_ok, "buff module installs")

local input_id = "input_device_handoff"
local buff_id = "player_buff_removal"
local input_hook = installed_hooks[input_id]
local buff_hook = installed_hooks[buff_id]
local input_handler = input_hook and input_hook.handler
local buff_handler = buff_hook and buff_hook.handler

check(
    input_hook ~= nil
        and input_hook.class_path == "scripts/managers/input/input_manager"
        and input_hook.method_name == "_update_devices"
        and input_hook.hook_kind == "safe"
        and type(input_handler) == "function",
    "input safe hook is captured"
)
check(
    buff_hook ~= nil
        and buff_hook.class_path
            == "scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling"
        and buff_hook.method_name == "update"
        and buff_hook.hook_kind == "safe"
        and type(buff_handler) == "function",
    "buff safe hook is captured"
)

local latest_logic = {}
local fixed_logic = {}
local combined_logic = {}
local selection_logic = {
    latest = latest_logic,
    fixed = fixed_logic,
    combined = combined_logic,
}

local keyboard = {
    name = "keyboard",
}
local controller = {
    name = "controller",
}

local function make_input_manager(logic, used_devices, update_selection)
    return {
        _selection = {
            logic = logic,
        },
        SELECTION_LOGIC = selection_logic,
        _used_input_devices = used_devices,
        _update_selection = update_selection,
    }
end

-- Already-selected latest device: the hook must be a complete no-op.
local already_selected_updates = 0
local function already_selected_update()
    already_selected_updates = already_selected_updates + 1
end

input_device.last_pressed_device = keyboard
local already_ok = pcall(
    input_handler,
    make_input_manager(latest_logic, {
        keyboard,
    }, already_selected_update)
)

check(
    already_ok
        and already_selected_updates == 0
        and count_for(run_calls, input_id) == 0
        and count_for(hits, input_id) == 0
        and count_for(actions, input_id) == 0,
    "input no-ops when latest device is already selected"
)

-- Fixed and combined selection modes must never be reconciled by this fix.
local non_latest_updates = 0
local function non_latest_update()
    non_latest_updates = non_latest_updates + 1
end

input_device.last_pressed_device = controller
local fixed_ok = pcall(
    input_handler,
    make_input_manager(fixed_logic, {
        keyboard,
    }, non_latest_update)
)
local combined_ok = pcall(
    input_handler,
    make_input_manager(combined_logic, {
        keyboard,
    }, non_latest_update)
)

check(
    fixed_ok
        and combined_ok
        and non_latest_updates == 0
        and count_for(run_calls, input_id) == 0
        and count_for(hits, input_id) == 0
        and count_for(actions, input_id) == 0,
    "input fixed/combined modes no-op"
)

-- No last-pressed device means there is nothing safe to reconcile.
local nil_latest_updates = 0
local function nil_latest_update()
    nil_latest_updates = nil_latest_updates + 1
end

input_device.last_pressed_device = nil
local nil_latest_ok = pcall(
    input_handler,
    make_input_manager(latest_logic, {
        keyboard,
    }, nil_latest_update)
)

check(
    nil_latest_ok
        and nil_latest_updates == 0
        and count_for(run_calls, input_id) == 0
        and count_for(hits, input_id) == 0
        and count_for(actions, input_id) == 0,
    "input nil latest device no-ops"
)

-- A sparse device array is a malformed engine shape and must fail open.
local malformed_updates = 0
local function malformed_update()
    malformed_updates = malformed_updates + 1
end

input_device.last_pressed_device = controller
local malformed_ok = pcall(input_handler, make_input_manager(latest_logic, {
    [2] = keyboard,
}, malformed_update))
local nil_manager_ok = pcall(input_handler, nil)

check(
    malformed_ok
        and nil_manager_ok
        and malformed_updates == 0
        and count_for(run_calls, input_id) == 0
        and count_for(hits, input_id) == 0
        and count_for(actions, input_id) == 0,
    "input malformed/nil manager shapes fail open"
)

-- A same-frame latest-device change is reconciled once through runtime:run.
local switch_updates = 0
local observed_manager = nil
local switch_manager = nil
local function switch_update(self)
    switch_updates = switch_updates + 1
    observed_manager = self
    self._used_input_devices[1] = input_device.last_pressed_device

    for index = #self._used_input_devices, 2, -1 do
        table.remove(self._used_input_devices, index)
    end
end

switch_manager = make_input_manager(latest_logic, {
    keyboard,
}, switch_update)
input_device.last_pressed_device = controller

local input_runs_before = count_for(run_calls, input_id)
local first_switch_ok = pcall(input_handler, switch_manager)
-- The simulated engine selection now contains the latest device; a second frame
-- proves the repair is not repeatedly dispatched.
local second_switch_ok = pcall(input_handler, switch_manager)
local input_callback_log = run_callbacks[input_id] or {}

check(first_switch_ok and second_switch_ok, "input same-frame hook remains error-free")
check(
    switch_updates == 1
        and observed_manager == switch_manager
        and switch_manager._used_input_devices[1] == controller,
    "input latest switch calls _update_selection exactly once"
)
check(
    count_for(run_calls, input_id) == input_runs_before + 1
        and input_callback_log[input_runs_before + 1] == switch_update,
    "input latest switch dispatches the captured method through runtime"
)
check(
    count_for(hits, input_id) == 1 and count_for(actions, input_id) == 1,
    "input latest switch records one actual hit and action"
)

-- Consecutive marked buffs are the original forward-removal failure mode.
local kept_first = {
    name = "kept-first",
}
local removed_first = {
    name = "removed-first",
    remove = true,
}
local removed_second = {
    name = "removed-second",
    remove = true,
}
local kept_second = {
    name = "kept-second",
    remove = false,
}
local removed_third = {
    name = "removed-third",
    remove = true,
}
local active_buffs = {
    kept_first,
    removed_first,
    removed_second,
    kept_second,
    removed_third,
}
local hud = {
    _active_buffs_data = active_buffs,
}

local buff_runs_before = count_for(run_calls, buff_id)
local buff_ok = pcall(buff_handler, hud)
local buff_callback_log = run_callbacks[buff_id] or {}

check(buff_ok, "buff hook remains error-free")
check(
    #active_buffs == 2
        and active_buffs[1] == kept_first
        and active_buffs[2] == kept_second,
    "buff backward pass removes all consecutive marked entries and keeps order"
)
check(
    count_for(run_calls, buff_id) == buff_runs_before + 1
        and type(buff_callback_log[buff_runs_before + 1]) == "function",
    "buff cleanup dispatches through runtime"
)
check(
    count_for(hits, buff_id) == 1 and count_for(actions, buff_id) == 3,
    "buff cleanup records one hit and the exact removal action count"
)

-- Nil/malformed HUD shapes must not crash or create false telemetry.
local buff_hits_before = count_for(hits, buff_id)
local buff_actions_before = count_for(actions, buff_id)
local malformed_hud = {
    _active_buffs_data = "not-a-table",
}
local nil_hud_ok = pcall(buff_handler, nil)
local missing_data_ok = pcall(buff_handler, {})
local malformed_hud_ok = pcall(buff_handler, malformed_hud)

check(
    nil_hud_ok
        and missing_data_ok
        and malformed_hud_ok
        and malformed_hud._active_buffs_data == "not-a-table"
        and count_for(hits, buff_id) == buff_hits_before
        and count_for(actions, buff_id) == buff_actions_before,
    "buff malformed/nil HUD shapes fail open"
)

print(string.format("input_and_buff_behavior: %d passed, %d failed", passed, failed))

if failed > 0 then
    os.exit(1)
end
