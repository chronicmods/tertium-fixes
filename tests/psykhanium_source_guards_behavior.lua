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

local function returned_four(handler, original, ...)
    local ok, a, b, c, d = pcall(handler, original, ...)

    return ok
        and a == "first"
        and b == nil
        and c == "third"
        and d == 4,
        ok and nil or tostring(a)
end

DEDICATED_SERVER = false

local original_require = require
local require_calls = 0

function require(module_name)
    require_calls = require_calls + 1

    return original_require(module_name)
end

local active = {}
local availability = {}
local defers = {}
local hooks = {}
local registrations = {}
local hits = {}
local actions = {}

local runtime = {}

function runtime:defer_file(module_id, module_path, handler)
    defers[module_id] = {
        module_path = module_path,
        handler = handler,
    }
    registrations[#registrations + 1] = {
        kind = "defer",
        module_id = module_id,
        path = module_path,
    }

    return true
end

function runtime:install_hook(module_id, class_path, method_name, hook_kind, handler)
    hooks[module_id] = {
        class_path = class_path,
        method_name = method_name,
        hook_kind = hook_kind,
        handler = handler,
    }
    registrations[#registrations + 1] = {
        kind = "hook",
        module_id = module_id,
        path = class_path,
    }

    return true
end

function runtime:is_active(module_id)
    return active[module_id] ~= false
end

function runtime:set_available(module_id, is_available, reason)
    availability[module_id] = {
        is_available = is_available,
        reason = reason,
    }

    if not is_available then
        active[module_id] = false
    end
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

local stimm_module = dofile(
    "scripts/mods/TertiumFixes/modules/stimm_field_deleted_extension_guard.lua"
)
local danger_module = dofile(
    "scripts/mods/TertiumFixes/modules/training_grounds_danger_index_guard.lua"
)

check(type(stimm_module) == "table", "stimm guard loads")
check(type(danger_module) == "table", "danger guard loads")
check(require_calls == 0, "guard modules perform no eager game require")

local stimm_install_ok = pcall(stimm_module.install, stimm_module)
local danger_install_ok = pcall(danger_module.install, danger_module)

check(stimm_install_ok, "stimm guard installs")
check(danger_install_ok, "danger guard installs")

local stimm_id = "stimm_field_deleted_extension_guard"
local danger_id = "training_grounds_danger_index_guard"
local stimm_hook = hooks[stimm_id]
local danger_hook = hooks[danger_id]
local danger_defer = defers[danger_id]

check(
    stimm_hook ~= nil
        and stimm_hook.class_path
            == "scripts/extension_systems/proximity/side_relation_gameplay_logic/proximity_broker_stimm_field"
        and stimm_hook.method_name == "_make_linger"
        and stimm_hook.hook_kind == "normal"
        and type(stimm_hook.handler) == "function",
    "stimm guard registers the exact deferred normal hook"
)
check(
    danger_defer ~= nil
        and danger_defer.module_path == "scripts/settings/difficulty/danger_settings"
        and type(danger_defer.handler) == "function",
    "danger guard defers DangerSettings"
)
check(
    danger_hook ~= nil
        and danger_hook.class_path
            == "scripts/ui/view_elements/view_element_mission_board_difficulty_selector/view_element_mission_board_difficulty_selector"
        and danger_hook.method_name == "initialize_data"
        and danger_hook.hook_kind == "normal"
        and type(danger_hook.handler) == "function",
    "danger guard registers the exact deferred normal hook"
)

local danger_defer_order
local danger_hook_order

for index, registration in ipairs(registrations) do
    if registration.module_id == danger_id and registration.kind == "defer" then
        danger_defer_order = index
    elseif registration.module_id == danger_id and registration.kind == "hook" then
        danger_hook_order = index
    end
end

check(
    danger_defer_order ~= nil
        and danger_hook_order ~= nil
        and danger_defer_order < danger_hook_order,
    "DangerSettings is deferred before selector interception"
)

local stimm_handler = stimm_hook and stimm_hook.handler
local original_calls = 0
local original_arguments

local function original_stimm(...)
    original_calls = original_calls + 1
    original_arguments = {
        count = select("#", ...),
        ...,
    }

    return "first", nil, "third", 4
end

local unit = {}
local live_extension = {
    __deleted = false,
}
local live_row = {
    buff_extension = live_extension,
}
local live_broker = {
    _units_in_proximity = {
        [unit] = live_row,
    },
    _lingering_units = {},
}
local returns_ok, returns_error = returned_four(
    stimm_handler,
    original_stimm,
    live_broker,
    unit,
    10,
    3
)

check(returns_ok, "live stimm extension preserves all vanilla returns", returns_error)
check(
    original_calls == 1
        and original_arguments.count == 4
        and original_arguments[1] == live_broker
        and original_arguments[2] == unit
        and original_arguments[3] == 10
        and original_arguments[4] == 3,
    "live stimm extension calls vanilla exactly once with unchanged arguments"
)
check(
    live_broker._units_in_proximity[unit] == live_row
        and count_for(hits, stimm_id) == 0
        and count_for(actions, stimm_id) == 0,
    "live stimm extension is untouched"
)

active[stimm_id] = false
local inactive_deleted = {
    __deleted = true,
}
local inactive_row = {
    buff_extension = inactive_deleted,
}
local inactive_broker = {
    _units_in_proximity = {
        [unit] = inactive_row,
    },
}
local before_inactive_calls = original_calls
local inactive_ok = returned_four(
    stimm_handler,
    original_stimm,
    inactive_broker,
    unit,
    11,
    4
)

check(
    inactive_ok
        and original_calls == before_inactive_calls + 1
        and inactive_broker._units_in_proximity[unit] == inactive_row,
    "disabled stimm guard passes a deleted row through unchanged"
)
active[stimm_id] = true

local destroyed_member_reads = 0
local deleted_extension = setmetatable({
    __deleted = true,
}, {
    __index = function (_, key)
        destroyed_member_reads = destroyed_member_reads + 1
        error("destroyed extension member read: " .. tostring(key))
    end,
})
local deleted_row = {
    buff_extension = deleted_extension,
    buff_datas = {
        {
            component_index = 17,
            local_index = 31,
        },
    },
}
local lingering_row = {}
local deleted_broker = {
    _units_in_proximity = {
        [unit] = deleted_row,
    },
    _lingering_units = {
        [unit] = lingering_row,
    },
}
local script_unit_reads = 0

ScriptUnit = setmetatable({}, {
    __index = function (_, key)
        script_unit_reads = script_unit_reads + 1
        error("unexpected ScriptUnit reacquisition: " .. tostring(key))
    end,
})

local before_deleted_calls = original_calls
local deleted_ok, deleted_error = pcall(
    stimm_handler,
    original_stimm,
    deleted_broker,
    unit,
    12,
    5
)

check(deleted_ok, "deleted stimm extension is handled without a destroyed-object read", deleted_error)
check(
    original_calls == before_deleted_calls
        and destroyed_member_reads == 0
        and script_unit_reads == 0,
    "deleted stimm row is neither replayed nor reacquired"
)
check(
    deleted_broker._units_in_proximity[unit] == nil
        and deleted_broker._lingering_units[unit] == nil,
    "deleted stimm proximity and lingering rows are discarded"
)
check(
    count_for(hits, stimm_id) == 1
        and count_for(actions, stimm_id) == 1,
    "deleted stimm discard records one hit and action"
)

local inherited_deleted_extension = setmetatable({}, {
    __index = {
        __deleted = true,
    },
})
local inherited_row = {
    buff_extension = inherited_deleted_extension,
}
local inherited_broker = {
    _units_in_proximity = {
        [unit] = inherited_row,
    },
}
local before_inherited_calls = original_calls

returned_four(
    stimm_handler,
    original_stimm,
    inherited_broker,
    unit,
    13,
    6
)
check(
    original_calls == before_inherited_calls + 1
        and inherited_broker._units_in_proximity[unit] == inherited_row
        and count_for(actions, stimm_id) == 1,
    "stimm guard matches only a raw exact deleted marker"
)

local malformed_cases = {
    {
        name = "missing broker table",
        broker = false,
        unit = unit,
    },
    {
        name = "missing unit",
        broker = {
            _units_in_proximity = {},
        },
        unit = nil,
    },
    {
        name = "missing proximity table",
        broker = {},
        unit = unit,
    },
    {
        name = "missing proximity row",
        broker = {
            _units_in_proximity = {},
        },
        unit = unit,
    },
    {
        name = "non-table proximity row",
        broker = {
            _units_in_proximity = {
                [unit] = true,
            },
        },
        unit = unit,
    },
    {
        name = "row without cached extension",
        broker = {
            _units_in_proximity = {
                [unit] = {},
            },
        },
        unit = unit,
    },
}

for _, case in ipairs(malformed_cases) do
    local before_calls = original_calls
    local case_returns_ok, case_error = returned_four(
        stimm_handler,
        original_stimm,
        case.broker,
        case.unit,
        14,
        7
    )

    check(
        case_returns_ok and original_calls == before_calls + 1,
        "stimm guard fails open for " .. case.name,
        case_error
    )
end

local danger_levels = {
    { name = "uprising" },
    { name = "malice" },
    { name = "heresy" },
    { name = "damnation" },
    { name = "auric" },
}
local danger_settings = { danger_levels = danger_levels }
local settings_load_ok, settings_load_error = pcall(
    danger_defer.handler,
    danger_settings
)

check(settings_load_ok, "deferred DangerSettings load succeeds", settings_load_error)
check(availability[danger_id] == nil, "valid DangerSettings keeps guard available")

local danger_handler = danger_hook and danger_hook.handler
local danger_original_calls = 0
local captured_danger

local function original_danger(_selector, value)
    danger_original_calls = danger_original_calls + 1
    captured_danger = value

    return "first", nil, "third", 4
end

local training_class = {
    __class_name = "TrainingGroundsOptionsView",
}
local shooting_parent = setmetatable({
    training_grounds_settings = "shooting_range",
}, training_class)
local parent_calls = 0
local selector = {
    parent = function ()
        parent_calls = parent_calls + 1

        return shooting_parent
    end,
}

local normalization_cases = {
    {
        name = "valid integer",
        value = 4,
        expected = 4,
        repaired = false,
    },
    {
        name = "high value",
        value = 99,
        expected = 5,
        repaired = true,
    },
    {
        name = "low value",
        value = -20,
        expected = 1,
        repaired = true,
    },
    {
        name = "fractional value",
        value = 3.9,
        expected = 3,
        repaired = true,
    },
    {
        name = "numeric string",
        value = "4",
        expected = 4,
        repaired = true,
    },
    {
        name = "missing value",
        value = nil,
        expected = 3,
        repaired = true,
    },
    {
        name = "non-numeric string",
        value = "damnation",
        expected = 3,
        repaired = true,
    },
    {
        name = "boolean",
        value = true,
        expected = 3,
        repaired = true,
    },
    {
        name = "not-a-number",
        value = 0 / 0,
        expected = 3,
        repaired = true,
    },
    {
        name = "positive infinity",
        value = math.huge,
        expected = 3,
        repaired = true,
    },
    {
        name = "negative infinity",
        value = -math.huge,
        expected = 3,
        repaired = true,
    },
}

for _, case in ipairs(normalization_cases) do
    local before_calls = danger_original_calls
    local before_parent_calls = parent_calls
    local before_hits = count_for(hits, danger_id)
    local before_actions = count_for(actions, danger_id)
    local case_ok, case_error = returned_four(
        danger_handler,
        original_danger,
        selector,
        case.value
    )

    check(
        case_ok
            and danger_original_calls == before_calls + 1
            and parent_calls == before_parent_calls + 1
            and captured_danger == case.expected,
        "shooting-range danger normalizes " .. case.name,
        case_error
    )
    check(
        count_for(hits, danger_id) == before_hits + (case.repaired and 1 or 0)
            and count_for(actions, danger_id)
                == before_actions + (case.repaired and 1 or 0),
        "shooting-range danger telemetry matches " .. case.name
    )
end

local direct_parent = {
    __class_name = "TrainingGroundsOptionsView",
    training_grounds_settings = "shooting_range",
}
local direct_selector = {
    parent = function ()
        return direct_parent
    end,
}

returned_four(danger_handler, original_danger, direct_selector, 100)
check(captured_danger == 5, "direct raw TrainingGroundsOptionsView class is scoped")

local out_of_scope_cases = {
    {
        name = "mission board parent",
        parent = setmetatable({
            training_grounds_settings = "shooting_range",
        }, {
            __class_name = "MissionBoardView",
        }),
        value = 99,
    },
    {
        name = "non-shooting training mode",
        parent = setmetatable({
            training_grounds_settings = "basic_training",
        }, training_class),
        value = -10,
    },
    {
        name = "deleted training parent",
        parent = setmetatable({
            __deleted = true,
            training_grounds_settings = "shooting_range",
        }, training_class),
        value = "invalid",
    },
    {
        name = "missing parent",
        parent = nil,
        value = 99,
    },
}

for _, case in ipairs(out_of_scope_cases) do
    local scoped_selector = {
        parent = function ()
            return case.parent
        end,
    }
    local before_calls = danger_original_calls
    local before_hits = count_for(hits, danger_id)
    local before_actions = count_for(actions, danger_id)
    local case_ok, case_error = returned_four(
        danger_handler,
        original_danger,
        scoped_selector,
        case.value
    )

    check(
        case_ok
            and danger_original_calls == before_calls + 1
            and captured_danger == case.value
            and count_for(hits, danger_id) == before_hits
            and count_for(actions, danger_id) == before_actions,
        "danger guard fails open for " .. case.name,
        case_error
    )
end

active[danger_id] = false
local disabled_parent_calls = 0
local disabled_selector = {
    parent = function ()
        disabled_parent_calls = disabled_parent_calls + 1

        return shooting_parent
    end,
}
local disabled_ok = returned_four(
    danger_handler,
    original_danger,
    disabled_selector,
    500
)

check(
    disabled_ok and captured_danger == 500 and disabled_parent_calls == 0,
    "disabled danger guard passes through before inspecting the parent"
)
active[danger_id] = true

local invalid_settings_ok, invalid_settings_error = pcall(
    danger_defer.handler,
    {}
)

check(
    invalid_settings_ok
        and availability[danger_id] ~= nil
        and availability[danger_id].is_available == false,
    "empty DangerSettings disables the guard",
    invalid_settings_error
)

local unavailable_parent_calls = 0
local unavailable_selector = {
    parent = function ()
        unavailable_parent_calls = unavailable_parent_calls + 1

        return shooting_parent
    end,
}

returned_four(
    danger_handler,
    original_danger,
    unavailable_selector,
    "still-invalid"
)
check(
    captured_danger == "still-invalid" and unavailable_parent_calls == 0,
    "unavailable danger guard cannot reuse stale settings"
)

require = original_require
ScriptUnit = nil

print(string.format("RESULT: %d passed, %d failed", passed, failed))

if failed > 0 then
    os.exit(1)
end
