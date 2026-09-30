local source_root = assert(arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT"), "pass the extracted game source directory")
package.path = source_root .. "/?.lua;" .. package.path
BUILD = "release"
unpack = table.unpack or unpack
Log = { info = function() end, warning = function() end }
Application = {}
dofile(source_root .. "/scripts/foundation/utilities/table.lua")
dofile(source_root .. "/scripts/foundation/utilities/class.lua")
dofile(source_root .. "/scripts/foundation/utilities/callback.lua")
table.dump = function() end
function settings(_, value) return value end
Color = setmetatable({}, { __index = function() return function() return { 255, 255, 255, 255 } end end })

local checks, failures = 0, 0
local function check(value, message)
	checks = checks + 1
	if not value then failures = failures + 1 end
	print((value and "PASS " or "FAIL ") .. message)
end
local messages = {}
function Log.error(tag, message, ...) messages[#messages + 1] = tag .. ": " .. string.format(message, ...) end
local settings_path = "scripts/ui/views/social_menu_view/social_menu_view_settings"
local styles_path = "scripts/ui/views/social_menu_roster_view/social_menu_roster_view_styles"
local definitions_path = "scripts/ui/views/social_menu_roster_view/social_menu_roster_view_definitions"
local roster_path = "scripts/ui/views/social_menu_roster_view/social_menu_roster_view"
local localization_path = "scripts/managers/localization/localization_manager"
local source_files = { [settings_path] = true, [styles_path] = true, [definitions_path] = true, [roster_path] = true }
local font = { font_type = "test", font_size = 16 }
local loaded = {
	["scripts/managers/ui/ui_font_settings"] = { body = font, body_small = font, header_3 = font },
	["scripts/ui/default_pass_styles"] = { hotspot = {} },
	["scripts/settings/ui/ui_workspace_settings"] = { screen = {} },
	["scripts/ui/pass_templates/button_pass_templates"] = { tab_menu_button = { {}, { style = { offset = { 0, 0 } } } } },
	["scripts/ui/pass_templates/scrollbar_pass_templates"] = { terminal_scrollbar = { default_width = 8 } },
	["scripts/managers/ui/ui_widget"] = { create_definition = function(passes, _, content)
		content = table.clone(content or {})
		for _, pass in ipairs(passes) do if pass.value_id then content[pass.value_id] = pass.value end end
		return { content = content, passes = passes }
	end },
}
local deferred, require_calls = {}, 0
function require(path)
	require_calls = require_calls + 1
	if loaded[path] then return loaded[path] end
	if source_files[path] then
		loaded[path] = dofile(source_root .. "/" .. path .. ".lua")
		if deferred[path] then deferred[path](loaded[path]) end
		return loaded[path]
	end
	return {}
end
local Localization = dofile(source_root .. "/" .. localization_path .. ".lua")
local party_key = "loc_social_menu_party_header"
local manager = setmetatable({ _string_cache = {}, _status = "ready", _lookup = function(_, key)
	if key == party_key then return "Party {num_party_members}/{max_num_party_members}" end
	return "Other {missing_value}"
end }, Localization)
Managers = { localization = manager, data_service = { social = {} } }
function Localize(...) return manager:localize(...) end

local definition = require(definitions_path)
check(#messages == 2 and messages[1]:find("num_party_members", 1, true) and messages[2]:find("max_num_party_members", 1, true),
	"the installed Social definition reproduces both missing-context errors")
check(definition.widget_definitions.party_panel.content.header:find("undefined", 1, true) ~= nil,
	"the stock initial header contains the missing-value markers")
check(definition.widget_definitions.party_panel.content.num_party_members == 0
	and definition.widget_definitions.party_panel.content.max_num_party_members == loaded[settings_path].max_num_party_members,
	"the same stock definition supplies the missing initial values in widget content")

local active, hits, actions = true, 0, 0
local runtime = {}
function runtime:is_active() return active end
function runtime:get() return "placeholder" end
function runtime:record_hit() hits = hits + 1 end
function runtime:record_action() actions = actions + 1 end
function runtime:set_available(_, value, reason) assert(value, reason) end
function runtime:defer_file(_, path, callback)
	deferred[path] = callback
	if loaded[path] then callback(loaded[path]) end
	return true
end
function runtime:install_hook(_, path, method, kind, callback)
	assert(path == localization_path and kind == "normal")
	local original = Localization[method]
	Localization[method] = function(...) return callback(original, ...) end
	return true
end
function get_mod() return { _tf_runtime = runtime } end
local module = dofile("scripts/mods/TertiumFixes/modules/localization_guard.lua")
local before = require_calls
module:install()
check(require_calls == before, "the localization guard adds no eager game require")
manager._string_cache, messages = {}, {}
definition = dofile(source_root .. "/" .. definitions_path .. ".lua")
loaded[definitions_path] = definition
check(#messages == 0 and definition.widget_definitions.party_panel.content.header == "Party 0/4",
	"the installed initial header receives the stock empty-party context")
check(manager._string_cache[party_key] == nil, "the initial empty-party header is not left in the localization cache")
check(hits == 1 and actions == 1, "the initial party-context repair records one change")
if deferred[settings_path] then
	deferred[settings_path](nil)
	loaded[settings_path], loaded[styles_path] = nil, nil
	manager._string_cache, messages = {}, {}
	definition = dofile(source_root .. "/" .. definitions_path .. ".lua")
	loaded[definitions_path] = definition
	check(#messages == 0 and definition.widget_definitions.party_panel.content.header == "Party 0/4",
		"deferred party settings arrive through the real definition dependencies before localization")
end

local supplied = { num_party_members = 2, max_num_party_members = 4, extra = "kept" }
local previous_hits = hits
check(Localize(party_key, true, supplied) == "Party 2/4" and supplied.num_party_members == 2 and supplied.extra == "kept"
	and hits == previous_hits, "valid supplied context and unrelated fields pass through unchanged")
definition = dofile(source_root .. "/" .. definitions_path .. ".lua")
check(definition.widget_definitions.party_panel.content.header == "Party 0/4" and manager._string_cache[party_key] == "Party 2/4",
	"opening another definition preserves a real cached party count")

local Roster = require(roster_path)
local view = setmetatable({
	_party_widgets = {},
	_widgets_by_name = { party_panel = table.clone(definition.widget_definitions.party_panel) },
	_grids = { { force_update_list_size = function() end } },
	_add_to_party = function(self, id, info)
		self._party_widgets[#self._party_widgets + 1] = { content = { unique_id = id, player_info = info } }
	end,
	_unload_widget_avatar = function() end,
	_unload_widget_portrait = function() end,
	_on_navigation_input_changed = function() end,
}, Roster)
local members = {}
for count = 1, 4 do
	members[tostring(count)] = { party_status = function() return "in_party" end, online_status = function() return "online" end }
	view:_update_party_list(members, true)
	check(view._widgets_by_name.party_panel.content.header == "Party " .. count .. "/4"
		and manager._string_cache[party_key] == "Party " .. count .. "/4",
		"the installed roster refresh shows " .. count .. " real party members")
end
view:_update_party_list({}, true)
check(view._widgets_by_name.party_panel.content.header == "Party 0/4", "the installed roster refresh can return to an empty party")

messages = {}
Localize(party_key, true, {})
check(#messages == 2, "supplied incomplete context keeps the game's diagnostics")
messages = {}
Localize("loc_unrelated_text", true)
check(#messages == 1 and messages[1]:find("missing_value", 1, true), "unrelated missing localization context is still reported")
active = false
manager._string_cache, messages = {}, {}
Localize(party_key)
check(#messages == 2, "a disabled guard retains the original missing-context behavior")
active = true
if deferred[settings_path] then
	deferred[settings_path]({ max_num_party_members = 6 })
	manager._string_cache, messages = {}, {}
	check(Localize(party_key) == "Party 0/6" and #messages == 0, "initial capacity comes from the game settings rather than a hard-coded four")
	deferred[settings_path]({ max_num_party_members = 0/0 })
	manager._string_cache, messages = {}, {}
	Localize(party_key)
	check(#messages == 2, "invalid game capacity does not introduce a guessed party context")
else
	check(false, "the guard defers the stock party capacity")
end

print(string.format("localization_source_behavior: %d passed, %d failed", checks - failures, failures))
if failures > 0 then os.exit(1) end
