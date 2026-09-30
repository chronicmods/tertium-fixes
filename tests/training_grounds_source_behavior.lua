local source_root = assert(arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT"), "pass the extracted game source directory")
local checks, failures = 0, 0
local function check(ok, message)
	checks = checks + 1
	if ok then print("PASS " .. message) else failures = failures + 1 print("FAIL " .. message) end
end

function settings(_, value) return value end
function class(name)
	local value = { __class_name = name }
	value.__index = value
	return value
end

local danger_settings = dofile(source_root .. "/scripts/settings/difficulty/danger_settings.lua")
local levels = danger_settings.danger_levels
check(#danger_settings == 0 and type(levels) == "table" and #levels > 0,
	"the installed DangerSettings keeps levels in a named field")

local dependencies = {
	["scripts/settings/difficulty/danger_settings"] = danger_settings,
	["scripts/managers/ui/ui_widget"] = {
		create_definition = function(_, _, content) return content end,
		init = function(_, content) content.hotspot = {} return { content = content, offset = {} } end,
	},
	["scripts/utilities/ui/text"] = { localize_to_upper = function(value) return value end },
	["scripts/ui/pass_templates/stepper_pass_templates"] = { difficulty_stepper_indicator = { passes = {} } },
}
function require(path) return dependencies[path] or {} end

local selector_path = "scripts/ui/view_elements/view_element_mission_board_difficulty_selector/view_element_mission_board_difficulty_selector"
local selector_class = dofile(source_root .. "/" .. selector_path .. ".lua")
local active, available, hook, deferred = true, nil, nil, nil
local hits, actions = 0, 0
local runtime = {}
function runtime:defer_file(_, path, callback)
	assert(path == "scripts/settings/difficulty/danger_settings")
	deferred = callback
	callback(danger_settings)
	return true
end
function runtime:install_hook(_, path, method, kind, callback)
	assert(path == selector_path and method == "initialize_data" and kind == "normal")
	hook = callback
	return true
end
function runtime:set_available(_, value) available = value end
function runtime:is_active() return active and available ~= false end
function runtime:record_hit() hits = hits + 1 end
function runtime:record_action() actions = actions + 1 end
function get_mod() return { _tf_runtime = runtime } end
DEDICATED_SERVER = false

local module = dofile("scripts/mods/TertiumFixes/modules/training_grounds_danger_index_guard.lua")
module:install()
check(available ~= false and type(hook) == "function", "the installed danger schema leaves the shooting-range guard available")

local function selector(parent_name, mode)
	local parent = setmetatable({
		training_grounds_settings = mode or "shooting_range",
		_ui_scenegraph = { difficulty_stepper = { size = { 400, 50 } } },
	}, { __class_name = parent_name or "TrainingGroundsOptionsView" })
	local value = setmetatable({
		_parent = parent,
		_widgets_by_name = { difficulty_stepper = { content = {} } },
		parent = function(self) return self._parent end,
	}, selector_class)
	return value
end

local invalid = selector()
local vanilla_ok = pcall(selector_class.initialize_data, invalid, #levels + 20)
check(not vanilla_ok, "the installed selector reproduces an out-of-range saved danger error")

local cases = {
	{ name = "existing level", value = 2, expected = 2 },
	{ name = "high saved index", value = #levels + 20, expected = #levels },
	{ name = "low saved index", value = -20, expected = 1 },
	{ name = "fractional saved index", value = 2.9, expected = 2 },
	{ name = "numeric string", value = "2", expected = 2 },
	{ name = "missing saved index", expected = 3 },
	{ name = "invalid string", value = "broken", expected = 3 },
	{ name = "boolean", value = false, expected = 3 },
	{ name = "not-a-number", value = 0/0, expected = 3 },
	{ name = "infinity", value = math.huge, expected = 3 },
}
for _, case in ipairs(cases) do
	local view = selector()
	local before = hits
	local ok = pcall(hook, selector_class.initialize_data, view, case.value)
	local content = view._widgets_by_name.difficulty_stepper.content
	check(ok and view._initialized and view:get_current_selected_difficulty() == case.expected
		and content.danger == case.expected and content.difficulty_text == levels[case.expected].display_name,
		"the installed selector opens with " .. case.name)
	local selected = 0
	for _, indicator in ipairs(view._difficulty_indicator_widgets or {}) do
		if indicator.content.active then selected = selected + 1 end
	end
	check(selected == 1 and #view._difficulty_indicator_widgets == #levels,
		"the installed selector highlights one valid level for " .. case.name)
	check(hits == before + (case.value == case.expected and 0 or 1) and actions == hits,
		"danger repair counts match " .. case.name)
end

for _, scope in ipairs({
	{ name = "mission board", parent = "MissionBoardView", mode = "shooting_range" },
	{ name = "basic training", parent = "TrainingGroundsOptionsView", mode = "basic" },
}) do
	local view, captured = selector(scope.parent, scope.mode), nil
	local before = hits
	hook(function(_, value) captured = value end, view, 900)
	check(captured == 900 and hits == before, scope.name .. " does not inherit the shooting-range repair")
end

active = false
local captured
hook(function(_, value) captured = value end, selector(), 800)
check(captured == 800, "disabled shooting-range repair keeps the original argument")
active = true
deferred({ danger_levels = {} })
check(available == false, "an empty named danger list disables the guard")
hook(function(_, value) captured = value end, selector(), 700)
check(captured == 700, "an unavailable schema cannot reuse an earlier level list")

print(string.format("training_grounds_source_behavior: %d passed, %d failed", checks - failures, failures))
if failures > 0 then os.exit(1) end
