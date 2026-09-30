local source_root = assert(arg[1], "pass the extracted game source directory")
local checks, failures = 0, 0

local function check(condition, message)
	checks = checks + 1
	if condition then
		print("PASS " .. message)
	else
		failures = failures + 1
		print("FAIL " .. message)
	end
end

local function count_entries(values)
	local count = 0
	for _ in pairs(values) do
		count = count + 1
	end
	return count
end

table.clear = function (values)
	for key in pairs(values) do
		values[key] = nil
	end
end
table.find = function (values, value)
	for i = 1, #values do
		if values[i] == value then
			return i
		end
	end
end
table.enum = function (...)
	local values = {}
	for _, value in ipairs({ ... }) do values[value] = value end
	return values
end
table.clone_instance = function (values)
	local copy = {}
	for key, value in pairs(values) do
		copy[key] = type(value) == "table" and table.clone_instance(value) or value
	end
	return copy
end
local next_uuid = 0
math.uuid = function ()
	next_uuid = next_uuid + 1
	return "uuid" .. next_uuid
end
Application = { rendering_enabled = function () return true end }
GameParameters = {}
ResourceReferenceContext = { push = function () end, pop = function () end }
function settings(_, values) return values end
function Localize(key) return key end

local packages, next_package = {}, 0
Managers = {
	player = { local_player = function () return nil end },
	data_service = { social = {} },
	save = { character_data = function () return {} end },
	package = {
		load = function (_, name, reference, callback)
			next_package = next_package + 1
			packages[next_package] = { name = name, reference = reference, callback = callback, releases = 0 }
			return next_package
		end,
		release = function (_, id)
			packages[id].releases = packages[id].releases + 1
		end,
	},
}

local source_files = {
	["scripts/ui/render_target_icon_generator_base"] = true,
	["scripts/ui/portrait_ui"] = true,
	["scripts/ui/weapon_icon_ui"] = true,
	["scripts/ui/item_icon_loader_ui"] = true,
	["scripts/managers/ui/ui_manager"] = true,
	["scripts/ui/views/social_menu_roster_view/social_menu_roster_view"] = true,
	["scripts/ui/views/social_menu_roster_view/social_menu_roster_view_settings"] = true,
	["scripts/ui/views/group_finder_view/group_finder_view"] = true,
}
local party_players = {}
local loaded = {
	["scripts/foundation/managers/package/utilities/item_package"] = {
		compile_item_instance_dependencies = function (item)
			return { ["icons/" .. item.gear_id] = true }
		end,
	},
	["scripts/backend/master_items"] = { get_cached = function () return {} end },
	["scripts/ui/views/views"] = {
		inventory_view = { package = { "inventory/ui", "inventory/items" } },
		empty_view = {},
	},
	["scripts/ui/views/social_menu_roster_view/social_menu_roster_view_styles"] = {
		default_frame_material = "default-frame",
		default_insignia_material = "default-insignia",
	},
	["scripts/settings/ui/ui_settings"] = { portrait_frame_default_material = "default-material" },
	["scripts/utilities/players/player_compositions"] = { players = function () return party_players end },
	["scripts/utilities/profile_utils"] = {
		character_archetype_title = function () return "Veteran" end,
		character_title = function () return nil end,
	},
	["scripts/managers/ui/ui_widget"] = {
		set_visible = function (widget, _, visible)
			widget.visible = visible
		end,
	},
}

function require(path)
	if loaded[path] == nil then
		loaded[path] = source_files[path] and dofile(source_root .. "/" .. path .. ".lua") or {}
	end
	return loaded[path]
end

-- Use the game's class copier and callback binder as well as its UI classes.
dofile(source_root .. "/scripts/foundation/utilities/class.lua")
dofile(source_root .. "/scripts/foundation/utilities/callback.lua")
local BaseView = class("BaseView")
BaseView.on_exit = function () end
local Base = require("scripts/ui/render_target_icon_generator_base")
local Portrait = require("scripts/ui/portrait_ui")
local Weapon = require("scripts/ui/weapon_icon_ui")
local ItemLoader = require("scripts/ui/item_icon_loader_ui")
local UIManager = require("scripts/managers/ui/ui_manager")
local Roster = require("scripts/ui/views/social_menu_roster_view/social_menu_roster_view")
local RosterSettings = require("scripts/ui/views/social_menu_roster_view/social_menu_roster_view_settings")
local GroupFinder = require("scripts/ui/views/group_finder_view/group_finder_view")

local function render_instance(class_table)
	local instance = setmetatable({}, class_table)
	local freed = {}
	Base.init(instance, {
		width = 100,
		height = 100,
		render_target_atlas_generator = {
			free_atlas_grid_index = function (_, atlas, index)
				freed[#freed + 1] = { atlas, index }
			end,
			get_atlas_render_target = function () return "texture", 5, 5 end,
		},
	})
	return instance, freed
end

local function item_instance()
	return ItemLoader:new()
end

local function ui_instance(loader)
	local never_loaded = { has_request = function () return false end }
	local ui = setmetatable({
		_views_loading_data = {},
		_package_unload_list = {},
		_packages_to_remove = {},
		_back_buffer_render_handlers = {
			icon = loader,
			portraits = render_instance(Portrait),
			weapons = never_loaded,
			weapon_skin = never_loaded,
			companion = never_loaded,
			cosmetics = never_loaded,
		},
	}, UIManager)
	Managers.ui = ui
	return ui
end

local function finish_item_load(loader)
	loader:_handle_request_queue()
	local request = loader._active_request
	if request then
		for _, id in ipairs(request.package_ids or {}) do
			packages[id].callback(id)
		end
	end
	loader:_handle_request_queue()
end

local function frame_item(name)
	return { gear_id = name, name = name, icon = "texture/" .. name, item_type = "PORTRAIT_FRAME", slots = { "slot_portrait_frame" } }
end

local function roster_widget(item)
	local profile = { character_id = "player", loadout = { slot_portrait_frame = item } }
	local widget = {
		content = {
			player_info = { profile = function () return profile end },
			portrait_renderer = {},
		},
		style = { portrait = { material_values = {} }, character_insignia = { material_values = {} } },
	}
	return widget, profile
end

local function group_instance()
	local widgets = {}
	for i = 1, 4 do
		widgets["team_member_" .. i] = {
			content = {},
			style = {
				character_name = { offset = {} },
				character_archetype_title = { offset = {} },
				character_portrait = { material_values = {} },
				character_insignia = { material_values = {}, color = {} },
			},
		}
	end
	return setmetatable({
		_widgets_by_name = widgets,
		_own_group_visualization = { members = {} },
		_ui_renderer = {},
		_player = function () return { character_id = function () return "local" end } end,
	}, GroupFinder)
end

local function party_player(name)
	local insignia = frame_item(name .. "-insignia")
	insignia.slots = { "slot_insignia" }
	local profile = {
		character_id = name,
		current_level = 30,
		archetype = { name = "veteran", archetype_icon_selection_large_unselected = "class-icon" },
		loadout = { slot_portrait_frame = frame_item(name .. "-frame"), slot_insignia = insignia },
	}
	return {
		profile = function () return profile end,
		name = function () return name end,
		account_id = function () return name end,
	}, profile
end

Managers.data_service.social.get_player_info_by_account_id = function ()
	return { platform = function () return "steam" end, _presence = { havoc_rank_cadence_high = function () return 1 end } }
end

local function limited_resume(instance, method)
	local generate = instance._generate_icon_request
	local calls = 0
	instance._generate_icon_request = function (self, ...)
		calls = calls + 1
		assert(calls <= 16, "render toggle keeps creating requests")
		return generate(self, ...)
	end
	local ok, err = pcall(instance[method], instance, true)
	instance._generate_icon_request = nil
	return ok, calls, err
end

local raw_portrait = render_instance(Portrait)
local raw_ref = raw_portrait:_generate_icon_request("profile", {}, nil)
raw_portrait:unload_request_reference(raw_ref)
check(not pcall(raw_portrait.unload_request_reference, raw_portrait, raw_ref), "stock render release crashes on a stale reference")

raw_portrait = render_instance(Portrait)
raw_portrait:_generate_icon_request("profile", {}, nil)
raw_portrait:change_render_portrait_status(false)
local raw_resume_ok, raw_resume_calls = limited_resume(raw_portrait, "change_render_portrait_status")
check(count_entries(raw_portrait._requests_by_size["100x100"]) > 1,
	"stock portrait re-enable creates new size-suffixed requests while traversing the same table")
print("stock portrait resume: " .. tostring(raw_resume_ok) .. ", generation calls=" .. raw_resume_calls)

raw_portrait = render_instance(Portrait)
local raw_first_owner = raw_portrait:_generate_icon_request("shared", {}, nil)
local raw_second_owner = raw_portrait:_generate_icon_request("shared", {}, nil)
raw_portrait:change_render_portrait_status(false)
raw_portrait:unload_request_reference(raw_first_owner)
check(not raw_portrait:has_request(raw_second_owner), "stock release while rendering is disabled drops another widget's surviving owner")

local raw_loader = item_instance()
local raw_ui = ui_instance(raw_loader)
local raw_id = raw_ui:load_item_icon(frame_item("raw"), function () end)
finish_item_load(raw_loader)
raw_ui:unload_item_icon(raw_id)
raw_ui:unload_item_icon(raw_id)
check(#raw_loader._requests_to_unload == 2, "stock UI routing admits a second item release during the frame delay")
check(not pcall(raw_loader._handle_icon_unloads, raw_loader, true), "stock delayed item queue crashes after releasing the same reference twice")

raw_ui:load_view("inventory_view", "test")
raw_ui:unload_view("inventory_view", "test", 1)
check(not pcall(raw_ui.unload_view, raw_ui, "inventory_view", "test", 1), "stock view release crashes after its owner was already removed")

local raw_roster_loader = item_instance()
ui_instance(raw_roster_loader)
local raw_roster = setmetatable({ _icon_unload_queue = {} }, Roster)
local raw_widget, raw_profile = roster_widget(frame_item("equipped"))
raw_roster:_update_portrait_frame(raw_widget, raw_profile)
finish_item_load(raw_roster_loader)
raw_roster:_update_portrait_frame(raw_widget, raw_profile)
check(raw_widget.style.portrait.material_values.portrait_frame_texture == "texture/equipped", "stock cached frame replacement resolves synchronously")
raw_roster:_unload_icons()
check(raw_widget.style.portrait.material_values.portrait_frame_texture == "default-frame", "stock old-frame callback overwrites the cached replacement on the next update")

local raw_party_loader = item_instance()
local raw_party_ui = ui_instance(raw_party_loader)
local raw_party = group_instance()
party_players = { (party_player("departing")) }
raw_party:_update_listed_group()
local raw_slot = raw_party._widgets_by_name.team_member_1.content
local raw_portrait_id, raw_frame_id, raw_insignia_id = raw_slot.icon_load_id, raw_slot.frame_load_id, raw_slot.insignia_load_id
party_players = {}
raw_party:_update_listed_group()
check(raw_slot.slot_filled == false and raw_slot.icon_load_id == raw_portrait_id
	and raw_slot.frame_load_id == raw_frame_id and raw_slot.insignia_load_id == raw_insignia_id,
	"stock Party Finder abandons all three icon owners when a member leaves")
raw_party:on_exit()
check(raw_party_ui._back_buffer_render_handlers.portraits:has_request(raw_portrait_id)
	and raw_party_loader:has_request(raw_frame_id) and raw_party_loader:has_request(raw_insignia_id),
	"stock Party Finder exit skips the now-empty slot and leaves its resources loaded")

local active, errors, hits = true, 0, 0
local runtime = {}
function runtime:is_active() return active end
function runtime:run(_, fn, ...)
	local result = table.pack(pcall(fn, ...))
	if not result[1] then errors = errors + 1 end
	return table.unpack(result, 1, result.n)
end
function runtime:record_hit() hits = hits + 1 end
function runtime:record_action() end
function runtime:set_available(_, available, reason)
	assert(available ~= false, reason)
end
function runtime:install_hook(_, path, method, kind, handler)
	assert(kind == "normal")
	local class_table = require(path)
	local original = assert(class_table[method], path .. "." .. method)
	class_table[method] = function (...)
		return handler(original, ...)
	end
	return true
end
function get_mod() return { _tf_runtime = runtime } end

local cleanup = dofile("scripts/mods/TertiumFixes/modules/ui_resource_cleanup.lua")
cleanup:install()
local social = dofile("scripts/mods/TertiumFixes/modules/social_roster_portrait.lua")
social:install()
check(Portrait._generate_icon_request ~= Base._generate_icon_request and Weapon._generate_icon_request ~= Base._generate_icon_request,
	"hooks reach copied subclass methods even after both classes were loaded")

for _, entry in ipairs({
	{ Portrait, "change_render_portrait_status", "portrait" },
	{ Weapon, "change_render_weapon_icon_status", "weapon" },
}) do
	local generator, freed = render_instance(entry[1])
	local loaded_count, unloaded_count = 0, 0
	local function on_load() loaded_count = loaded_count + 1 end
	local function on_unload() unloaded_count = unloaded_count + 1 end
	local first = generator:_generate_icon_request("same", {}, on_load, nil, nil, on_unload)
	local second = generator:_generate_icon_request("same", {}, on_load, nil, nil, on_unload)
	local request = generator:_request_by_reference_id(first)
	request.spawned, request.grid_index, request.atlas_id = true, 4, "atlas"
	for i = #generator._requests_queue_order, 1, -1 do table.remove(generator._requests_queue_order, i) end
	for cycle = 1, 5 do
		generator[entry[2]](generator, false)
		check(#request.references_array == 0 and request.references_lookup[first] and request.references_lookup[second], entry[3] .. " keeps both owners while rendering is disabled, cycle " .. cycle)
		local ok, calls = limited_resume(generator, entry[2])
		check(ok and calls == 2 and count_entries(generator._requests_by_size["100x100"]) == 1
			and generator:_request_by_reference_id(first) == request and #request.references_array == 2
			and #generator._requests_queue_order == 1, entry[3] .. " reuses one request and one render job, cycle " .. cycle)
	end
	check(#freed == 1 and unloaded_count == 10, entry[3] .. " frees its old atlas slot once and preserves every real unload callback")
	generator[entry[2]](generator, true, true)
	check(#request.references_array == 2 and #generator._requests_queue_order == 1, entry[3] .. " forced resume does not duplicate owners or render jobs")
	request.spawned, request.grid_index, request.atlas_id = true, 7, "new-atlas"
	generator[entry[2]](generator, true, true)
	check(loaded_count == 2 and #request.references_array == 2, entry[3] .. " preserves immediate callbacks for an already rendered request")
	generator:unload_request_reference(first)
	check(generator:has_request(second) and not generator:has_request(first) and #freed == 1, entry[3] .. " releasing one owner keeps the other owner and atlas slot")
	check(pcall(generator.unload_request_reference, generator, first) and generator:has_request(second), entry[3] .. " ignores a stale owner without changing its neighbour")
	generator:unload_request_reference(second)
	check(not generator:has_request(second) and #freed == 2 and #generator._requests_queue_order == 0, entry[3] .. " final owner releases the atlas and queue entry once")
	check(pcall(generator.unload_request_reference, generator, second), entry[3] .. " repeated final release is harmless")

	generator = render_instance(entry[1])
	first = generator:_generate_icon_request("suspended", {}, nil)
	second = generator:_generate_icon_request("suspended", {}, nil)
	generator[entry[2]](generator, false)
	generator:unload_request_reference(first)
	check(not generator:has_request(first) and generator:has_request(second), entry[3] .. " releasing a suspended owner preserves the other widget's request")
	local resumed = limited_resume(generator, entry[2])
	request = generator:_request_by_reference_id(second)
	check(resumed and request and #request.references_array == 1 and #generator._requests_queue_order == 1,
		entry[3] .. " resumes its surviving suspended owner once")
	generator[entry[2]](generator, false)
	generator:unload_request_reference(second)
	check(not generator:has_request(second) and count_entries(generator._requests_by_size["100x100"]) == 0,
		entry[3] .. " removes the whole request when its final suspended owner leaves")

	generator = render_instance(entry[1])
	first = generator:_generate_icon_request("profile_100x100", {}, nil)
	second = generator:_generate_icon_request("profile_100x100", {}, nil, { size = { 50, 60 } })
	generator[entry[2]](generator, false)
	resumed = limited_resume(generator, entry[2])
	check(resumed and generator:_request_by_reference_id(first).id == "profile_100x100_100x100"
		and generator:_request_by_reference_id(second).id == "profile_100x100_50x60" and #generator._requests_queue_order == 2,
		entry[3] .. " distinct render sizes and size-like profile names keep their own request IDs")
end

local loader = item_instance()
local ui = ui_instance(loader)
local callbacks = 0
local item = frame_item("shared")
local first = ui:load_item_icon(item, function () end, nil, nil, nil, function () callbacks = callbacks + 1 end)
local second = ui:load_item_icon(item, function () end, nil, nil, nil, function () callbacks = callbacks + 1 end)
finish_item_load(loader)
local request = loader:_request_by_id(first)
local package_id = request.package_ids[1]
ui:unload_item_icon(first)
ui:unload_item_icon(first)
check(callbacks == 1 and #loader._requests_to_unload == 1, "repeated item unload does not repeat callbacks or add another delayed release")
loader:_handle_icon_unloads()
loader:_handle_icon_unloads()
check(loader:has_request(first) and packages[package_id].releases == 0, "item packages retain the stock two-frame grace period")
loader:_handle_icon_unloads()
check(not loader:has_request(first) and loader:has_request(second) and packages[package_id].releases == 0, "delayed release removes only its owner")
loader._requests_to_unload[#loader._requests_to_unload + 1] = { id = first, frame_delay_counter = 0 }
check(pcall(loader._handle_icon_unloads, loader) and #loader._requests_to_unload == 0, "stale entries queued before enabling the fix drain safely")
ui:unload_item_icon(second)
loader:destroy()
check(callbacks == 2 and packages[package_id].releases == 1 and not loader:has_request(second), "forced teardown releases the final item packages and callback once")
check(pcall(loader.unload_icon, loader, first) and pcall(loader._unload_icon, loader, second), "direct stale item releases are harmless")

local view_callback_count = 0
ui:load_view("inventory_view", "owner-a", function () view_callback_count = view_callback_count + 1 end)
ui:load_view("inventory_view", "owner-b")
local view_a = ui._views_loading_data.inventory_view["UIManager_owner-a"]
local view_b = ui._views_loading_data.inventory_view["UIManager_owner-b"]
local view_package_ids = {}
for _, info in ipairs(view_a.packages_load_data) do
	view_package_ids[#view_package_ids + 1] = info.package_id
end
ui:unload_view("inventory_view", "owner-a", 1)
ui:unload_view("inventory_view", "owner-a", 1)
check(#ui._package_unload_list == 2 and ui._views_loading_data.inventory_view["UIManager_owner-b"] == view_b, "repeated view release leaves the other owner and original package delay intact")
for _, id in ipairs(view_package_ids) do packages[id].callback(id) end
check(view_callback_count == 0, "a released view cannot call its old load-complete callback")
ui:_update_package_unload_delay()
ui:release_packages()
check(packages[view_package_ids[1]].releases == 0, "view package delay still waits the original first frame")
ui:_update_package_unload_delay()
ui:release_packages()
check(packages[view_package_ids[1]].releases == 1 and packages[view_package_ids[2]].releases == 1, "view packages release once after the original delay")
ui:load_view("inventory_view", "owner-a")
ui:unload_view("inventory_view", "owner-a")
ui:release_packages()
check(ui._views_loading_data.inventory_view["UIManager_owner-a"] == nil, "a reused view owner name receives an independent valid release")
check(pcall(ui.unload_view, ui, "empty_view", "no-packages"), "views without packages retain their stock no-op")

local roster_loader = item_instance()
ui_instance(roster_loader)
local roster = setmetatable({ _icon_unload_queue = {} }, Roster)
local widget, profile = roster_widget(frame_item("current"))
roster:_update_portrait_frame(widget, profile)
finish_item_load(roster_loader)
local old_id = widget.content.frame_load_id
local old_package = roster_loader:_request_by_id(old_id).package_ids[1]
roster:_update_portrait_frame(widget, profile)
roster:_unload_icons()
check(widget.style.portrait.material_values.portrait_frame_texture == "texture/current", "cached replacement keeps its equipped frame after the roster queue drains")
check(#roster._icon_unload_queue == 0 and #roster_loader._requests_to_unload == 1
	and packages[old_package].releases == 0, "roster repair preserves the loader's delayed package release")
roster_loader:_handle_icon_unloads(true)
check(packages[old_package].releases == 0 and roster_loader:has_request(widget.content.frame_load_id), "refreshing the same frame retains its package for the new owner")

profile.loadout.slot_portrait_frame = frame_item("different")
roster:_update_portrait_frame(widget, profile)
check(widget.style.portrait.material_values.portrait_frame_texture == "default-frame" and widget.content.awaiting_frame_callback,
	"an uncached replacement clears the old texture while waiting")
finish_item_load(roster_loader)
roster:_unload_icons()
check(widget.style.portrait.material_values.portrait_frame_texture == "texture/different", "uncached replacement applies its own frame when ready")
roster_loader:_handle_icon_unloads(true)
check(packages[old_package].releases == 1, "changing frames releases the old package once the new frame owns the widget")

local pending_id = widget.content.frame_load_id
profile.loadout.slot_portrait_frame = frame_item("last")
roster:_update_portrait_frame(widget, profile)
roster:_queue_icons_for_unload(widget)
finish_item_load(roster_loader)
roster_loader:_handle_icon_unloads(true)
check(widget.content.frame_load_id == nil and widget.style.portrait.material_values.portrait_frame_texture == "default-frame"
	and not roster_loader:has_request(pending_id), "closing a roster entry while its next frame loads cancels the callback and releases its owner")

local delayed_widget, delayed_profile = roster_widget(frame_item("delayed"))
roster:_update_portrait_frame(delayed_widget, delayed_profile)
finish_item_load(roster_loader)
RosterSettings.icon_unload_frame_delay = 3
roster:_queue_icons_for_unload(delayed_widget)
check(#roster._icon_unload_queue == 1 and roster._icon_unload_queue[1].delay == 3, "nonzero roster delays set by another mod are preserved")
RosterSettings.icon_unload_frame_delay = 0
roster:_unload_icons(true)

local party_loader = item_instance()
local party_ui = ui_instance(party_loader)
local party_portraits = party_ui._back_buffer_render_handlers.portraits
local party = group_instance()
local member = party_player("member")
party_players = { member }
party:_update_listed_group()
local slot = party._widgets_by_name.team_member_1.content
local portrait_id, frame_id, insignia_id = slot.icon_load_id, slot.frame_load_id, slot.insignia_load_id
check(slot.slot_filled and party_portraits:has_request(portrait_id) and party_loader:has_request(frame_id), "filled Party Finder slots keep their normal icon owners")
party_players = {}
party:_update_listed_group()
check(slot.slot_filled == false and slot.icon_load_id == nil and slot.frame_load_id == nil and slot.insignia_load_id == nil
	and not party_portraits:has_request(portrait_id) and #party_loader._requests_to_unload == 2,
	"departing Party Finder members release their portrait, frame and insignia through normal cleanup")
party_loader:_handle_icon_unloads(true)
check(not party_loader:has_request(frame_id) and not party_loader:has_request(insignia_id), "departed member item references finish their delayed release")
party_players = { member }
party:_update_listed_group()
local next_frame_id = slot.frame_load_id
check(slot.slot_filled and next_frame_id ~= frame_id and party_loader:has_request(next_frame_id), "a new occupant receives independent owners instead of overwriting leaked IDs")
local saved_profile = member.profile
member.profile = function () return nil end
party:_update_listed_group()
check(slot.slot_filled == false and slot.frame_load_id == nil and party._update_listed_group_on_update == true,
	"a temporarily unavailable profile releases old icons and retains the game's refresh request")
member.profile = saved_profile
party:_update_listed_group()
check(slot.slot_filled and slot.frame_load_id ~= nil, "a returning profile reloads its icons normally")
active = false
party_players = {}
party:_update_listed_group()
local exit_portrait_id = slot.icon_load_id
check(exit_portrait_id ~= nil, "disabled cleanup leaves the original Party Finder behaviour in place")
active = true
party:on_exit()
party_loader:_handle_icon_unloads(true)
check(not party_portraits:has_request(exit_portrait_id) and slot.frame_load_id == nil and slot.insignia_load_id == nil,
	"Party Finder exit also clears empty slots left before the fix was enabled")

active = false
local disabled_loader = item_instance()
local disabled_ui = ui_instance(disabled_loader)
local disabled_id = disabled_ui:load_item_icon(frame_item("disabled"), function () end)
disabled_ui:unload_item_icon(disabled_id)
disabled_ui:unload_item_icon(disabled_id)
check(#disabled_loader._requests_to_unload == 2, "disabled cleanup delegates unchanged to the game")
check(errors == 0 and hits > 0, "all enabled repairs run without protected callback errors")

print(string.format("ui_source_behavior: %d passed, %d failed", checks - failures, failures))
if failures > 0 then os.exit(1) end
