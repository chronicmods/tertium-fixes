local checks, failures = 0, 0
local hooks, deferred, available = {}, {}, {}
local active, fail_run, fail_hook = true, false, nil
local settings = { servo_skull_scroll_enabled = true }
local hits, actions = 0, 0

local function check(condition, message)
	checks = checks + 1
	if condition then
		print("PASS " .. message)
	else
		failures = failures + 1
		print("FAIL " .. message)
	end
end

local runtime = {}
function runtime:is_active(id)
	return active and available[id] ~= false
end
function runtime:mod_is_enabled() return active end
function runtime:get(id) return settings[id] end
function runtime:run(_, fn, ...)
	if fail_run then return false end
	return pcall(fn, ...)
end
function runtime:record_hit() hits = hits + 1 end
function runtime:record_action() actions = actions + 1 end
function runtime:set_available(id, value) available[id] = value end
function runtime:install_hook(_, path, method, kind, fn)
	assert(kind == "normal")
	hooks[path .. ":" .. method] = fn
	return method ~= fail_hook
end
function runtime:defer_file(_, path, fn)
	deferred[path] = fn
	return true
end
function get_mod() return { _tf_runtime = runtime } end

local cleanup = dofile("scripts/mods/TertiumFixes/modules/ui_resource_cleanup.lua")
cleanup:install()
local social = dofile("scripts/mods/TertiumFixes/modules/social_roster_portrait.lua")
social:install()
local item_release = hooks["scripts/ui/item_icon_loader_ui:unload_icon"]
local item_finish = hooks["scripts/ui/item_icon_loader_ui:_unload_icon"]
local portrait_release = hooks["scripts/ui/portrait_ui:unload_request_reference"]
local portrait_generate = hooks["scripts/ui/portrait_ui:_generate_icon_request"]
local view_release = hooks["scripts/managers/ui/ui_manager:unload_view"]
local party_update = hooks["scripts/ui/views/group_finder_view/group_finder_view:_update_listed_group"]
local party_exit = hooks["scripts/ui/views/group_finder_view/group_finder_view:on_exit"]
local social_queue = hooks["scripts/ui/views/social_menu_roster_view/social_menu_roster_view:_queue_icons_for_unload"]
check(type(item_release) == "function" and type(item_finish) == "function"
	and type(portrait_release) == "function" and type(portrait_generate) == "function"
	and type(hooks["scripts/ui/weapon_icon_ui:_generate_icon_request"]) == "function"
	and type(hooks["scripts/ui/weapon_icon_ui:unload_request_reference"]) == "function", "resource hooks include both concrete render classes and delayed item release")

local calls = {}
local function original(...)
	calls[#calls + 1] = table.pack(...)
	return "first", nil, "third", false, 5, nil
end
local function complete_result(result)
	return result.n == 6 and result[1] == "first" and result[2] == nil
		and result[3] == "third" and result[4] == false and result[5] == 5 and result[6] == nil
end

local loader = {
	_requests = {},
	_requests_to_unload = {},
	_request_by_id = function (self, id) return self._requests[id] end,
}
loader._requests.one = {}
local result = table.pack(item_release(original, loader, "one", "extra", nil))
check(complete_result(result) and calls[#calls].n == 4 and calls[#calls][3] == "extra", "live item release preserves arguments and all return values")
loader._requests_to_unload[1] = { id = "one", frame_delay_counter = 2 }
local before = #calls
item_release(original, loader, "one")
check(#calls == before and hits == 1 and actions == 1, "a queued release is skipped once without changing its owner")
item_finish(original, loader, "one")
check(#calls == before + 1, "the queue's real release still reaches the game")
loader._requests.one = nil
before = #calls
item_finish(original, loader, "one")
check(#calls == before, "an already released delayed item does not reach the game")

local generator = {
	_requests_by_size = {},
	_request_by_reference_id = function () return nil end,
}
before = #calls
portrait_release(original, generator, "stale", true)
check(#calls == before, "an absent render owner is ignored")
generator._request_by_reference_id = function () return {} end
result = table.pack(portrait_release(original, generator, "live", true, "extra"))
check(complete_result(result) and calls[#calls][3] == true and calls[#calls][4] == "extra", "keep-reference releases are delegated unchanged")

local ui = { _views_loading_data = { inventory = { UIManager_other = {} } } }
before = #calls
view_release(original, ui, "inventory", "missing", 2)
check(#calls == before and ui._views_loading_data.inventory.UIManager_other ~= nil, "missing view owners leave other owners untouched")
result = table.pack(view_release(original, ui, "inventory", "other", 2, "extra"))
check(complete_result(result) and calls[#calls][4] == 2 and calls[#calls][5] == "extra", "valid view releases preserve the package delay and return values")

before = #calls
portrait_release(original, nil, "id")
item_release(original, {}, "id")
view_release(original, ui, "inventory", nil)
check(#calls == before + 3, "unrecognised manager shapes and invalid view arguments keep the original behaviour")
fail_run = true
before = #calls
item_release(original, loader, "missing")
view_release(original, ui, "inventory", "missing")
check(#calls == before + 2, "failed checks delegate without swallowing the original call")
fail_run = false

local request = { id = "profile_100x100", references_lookup = { owner = true }, references_array = { "owner", "neighbour" } }
generator._requests_by_size = { ["100x100"] = { [request.id] = request } }
generator._default_size = { 100, 100 }
generator._get_key_by_size = function (_, size) return size[1] .. "x" .. size[2] end
generator._requests_queue_order = { "other-job", request.id }
local function resume_original(self, prefix, data, load_cb, context, priority, unload_cb, ref, ...)
	check(prefix == "profile" and data == "data" and priority == true and ref == "owner", "resume strips one proven size suffix and retains request arguments")
	self._requests_queue_order[#self._requests_queue_order + 1] = request.id
	request.references_array[#request.references_array + 1] = ref
	return "first", nil, "third", false, 5, nil
end
result = table.pack(portrait_generate(resume_original, generator, request.id, "data", nil, nil, true, nil, "owner"))
check(complete_result(result) and #request.references_array == 2
	and #generator._requests_queue_order == 2 and generator._requests_queue_order[1] == "other-job", "resume preserves other jobs, owner order and all return values")
before = #calls
portrait_generate(original, generator, "new-profile", {}, nil, nil, nil, nil, nil)
portrait_generate(original, generator, request.id, {}, nil, { size = { 50, 50 } }, nil, nil, "owner")
portrait_generate(original, generator, request.id, {}, nil, nil, nil, nil, "other-owner")
check(#calls == before + 3 and calls[before + 1][2] == "new-profile"
	and calls[before + 2][2] == request.id and calls[before + 3][2] == request.id, "new requests, different sizes and unknown owners bypass the resume repair")

local unloads = {}
Managers = { ui = { unload_item_icon = function (_, id) unloads[#unloads + 1] = id end } }
local widget = { content = { frame_load_id = "frame" } }
local queue = { { widget = {}, load_id = "existing", delay = 0 } }
local view = { _icon_unload_queue = queue }
local function enqueue(self, w, delay, extra)
	self._icon_unload_queue[#self._icon_unload_queue + 1] = { widget = w, load_id = w.content.frame_load_id, delay = delay }
	w.content.frame_load_id = nil
	self._icon_unload_queue[#self._icon_unload_queue + 1] = { widget = w, load_id = "insignia", delay = 0 }
	return "first", nil, "third", false, 5, nil
end
result = table.pack(social_queue(enqueue, view, widget, 0, "extra"))
check(complete_result(result) and #unloads == 1 and unloads[1] == "frame"
	and #queue == 2 and queue[1].load_id == "existing" and queue[2].load_id == "insignia", "roster repair releases only its newly queued old frame and preserves the call's return values")
widget.content.frame_load_id = "delayed"
social_queue(enqueue, view, widget, 3)
check(#unloads == 1 and queue[3].load_id == "delayed" and queue[3].delay == 3, "roster repair keeps custom delays and unrelated icon entries")
widget.content.frame_load_id = "failed-check"
fail_run = true
social_queue(enqueue, view, widget, 0)
fail_run = false
check(queue[#queue - 1].load_id == "failed-check" and #unloads == 1, "failed roster checks leave the original queue available to the game")

active = false
before = #calls
item_release(original, loader, "missing")
portrait_release(original, generator, "missing")
view_release(original, ui, "inventory", "missing")
portrait_generate(original, generator, request.id, {}, nil, nil, nil, nil, "owner")
widget.content.frame_load_id = "disabled"
social_queue(enqueue, view, widget, 0)
check(#calls == before + 4 and #unloads == 1 and queue[#queue - 1].load_id == "disabled", "disabled modules preserve all original calls and queue behaviour")
active = true

local party_releases = {}
local empty_slot = { content = { slot_filled = false, icon_load_id = "portrait", frame_load_id = "frame", insignia_load_id = "insignia" } }
local filled_slot = { content = { slot_filled = true, icon_load_id = "keep" } }
local party = {
	_widgets_by_name = { team_member_1 = empty_slot, team_member_2 = filled_slot },
	_unload_portrait_icon = function (_, target)
		party_releases[#party_releases + 1] = target
		target.content.icon_load_id, target.content.frame_load_id, target.content.insignia_load_id = nil, nil, nil
	end,
}
result = table.pack(party_update(original, party, "extra"))
check(complete_result(result) and #party_releases == 1 and party_releases[1] == empty_slot
	and filled_slot.content.icon_load_id == "keep", "Party Finder cleanup releases only empty slots and preserves the update's return values")
party_update(original, party)
check(#party_releases == 1, "clean Party Finder slots need no repeated release")
empty_slot.content.frame_load_id = "late-frame"
result = table.pack(party_exit(function (...)
	check(empty_slot.content.frame_load_id == nil, "orphaned Party Finder slots clear before the game's exit runs")
	return original(...)
end, party))
check(complete_result(result) and #party_releases == 2, "Party Finder exit preserves all return values")
empty_slot.content.frame_load_id = "disabled-frame"
active = false
party_update(original, party)
party_exit(original, party)
active = true
check(empty_slot.content.frame_load_id == "disabled-frame" and #party_releases == 2, "disabled Party Finder cleanup leaves existing owners alone")

local template_path = "scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point"
local constants_path = "scripts/settings/player_character/player_character_constants"
local function wield_inputs()
	return { { input = "wield_scroll_up" }, { input = "keyboard_weapon_one" }, { input = "wield_scroll_down" }, { input = "controller_weapon_one" } }
end
local function template(inputs)
	local step = { inputs = inputs }
	return { not_scroll_wieldable = true, action_inputs = { wield = { input_sequence = { step } } } }, step
end
local servo = dofile("scripts/mods/TertiumFixes/modules/servo_skull_scroll.lua")
servo:install()
servo:on_enabled()
check(available.servo_skull_scroll ~= false, "enabling before template loading does not mark Servo-Skull unavailable")
local inputs = wield_inputs()
local constants = { wield_inputs = inputs }
local first_template, first_step = template(inputs)
deferred[template_path](first_template)
deferred[constants_path](constants)
local first_replacement = first_step.inputs
check(first_replacement ~= inputs and #first_replacement == 2 and #inputs == 4, "Servo-Skull edits its own input list")
deferred[template_path](first_template)
deferred[constants_path](constants)
check(first_step.inputs == first_replacement and available.servo_skull_scroll == true, "repeat template callbacks recognise the module's existing replacement")
local second_template, second_step = template(inputs)
deferred[template_path](second_template)
check(first_step.inputs == inputs and second_step.inputs ~= inputs and #second_step.inputs == 2, "template reload restores the previous target and repairs the new one")
local foreign = { { input = "foreign" } }
second_step.inputs = foreign
servo:on_disabled()
check(second_step.inputs == foreign, "disabling preserves a replacement written by another mod")

local new_inputs = wield_inputs()
local third_template, third_step = template(new_inputs)
deferred[constants_path]({ wield_inputs = new_inputs })
deferred[template_path](third_template)
check(available.servo_skull_scroll == true and third_step.inputs ~= new_inputs and #third_step.inputs == 2, "new matching constants and template recover after the temporary reload mismatch")
settings.servo_skull_scroll_enabled = false
servo:on_setting_changed("servo_skull_scroll_enabled")
check(third_step.inputs == new_inputs, "turning the setting off restores the latest template's original list")
settings.servo_skull_scroll_enabled = true
servo:on_setting_changed("servo_skull_scroll_enabled")
servo:reset()
check(third_step.inputs ~= new_inputs and #third_step.inputs == 2, "reset reapplies the enabled Servo-Skull fix without forgetting the original list")
local third_replacement = third_step.inputs
third_template.action_inputs.wield.input_sequence[1] = { inputs = foreign }
servo:on_unload()
check(third_step.inputs == new_inputs and third_template.action_inputs.wield.input_sequence[1].inputs == foreign,
	"unload restores the exact edited step even after another mod replaces the template's step")

fail_hook = "_unload_icon"
local missing_cleanup = dofile("scripts/mods/TertiumFixes/modules/ui_resource_cleanup.lua")
missing_cleanup:install()
check(available.ui_resource_cleanup == false, "an unavailable resource method disables the module")
fail_hook = nil
DEDICATED_SERVER = true
available.ui_resource_cleanup = nil
missing_cleanup:install()
check(available.ui_resource_cleanup == false, "UI resource cleanup stays unavailable on dedicated servers")

print(string.format("ui_cleanup_behavior: %d passed, %d failed", checks - failures, failures))
if failures > 0 then os.exit(1) end
