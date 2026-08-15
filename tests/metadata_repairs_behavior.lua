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

local deferred = {}
local availability = {}
local reasons = {}
local hits = {}
local actions = {}

local runtime = {}

function runtime:defer_file(module_id, path, callback)
	deferred[path] = deferred[path] or {}
	deferred[path][#deferred[path] + 1] = {
		callback = callback,
		module_id = module_id,
	}

	return true
end

function runtime:is_active()
	return true
end

function runtime:mod_is_enabled()
	return true
end

function runtime:get()
	return true
end

function runtime:set_available(module_id, value, reason)
	availability[module_id] = value
	reasons[module_id] = reason
end

function runtime:record_hit(module_id, count)
	hits[module_id] = (hits[module_id] or 0) + (count or 1)
end

function runtime:record_action(module_id, count)
	actions[module_id] = (actions[module_id] or 0) + (count or 1)
end

local mod = {
	_tf_runtime = runtime,
}

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	end
end

local function reset_world()
	deferred = {}
	availability = {}
	reasons = {}
	hits = {}
	actions = {}
end

local function deliver(path, value)
	local entries = deferred[path] or {}

	for index = 1, #entries do
		entries[index].callback(value)
	end
end

local veteran_path = "scripts/settings/buff/archetype_buff_templates/veteran_buff_templates"

reset_world()
local veteran = dofile("scripts/mods/TertiumFixes/modules/veteran_redirect_tooltip.lua")
local original_a = {
	"veteran_improved_tag_dead_bonus",
}
local original_b = {
	"veteran_improved_tag_dead_bonus",
}
local veteran_templates = {
	veteran_improved_tag_allied_buff = {
		related_talents = original_a,
	},
	veteran_improved_tag_allied_buff_increased_stacks = {
		related_talents = original_b,
	},
}

veteran:install()
deliver(veteran_path, veteran_templates)

check(
	veteran_templates.veteran_improved_tag_allied_buff.related_talents[1]
		== "veteran_improved_tag_dead_coherency_bonus"
		and veteran_templates.veteran_improved_tag_allied_buff_increased_stacks.related_talents[1]
			== "veteran_improved_tag_dead_coherency_bonus"
		and veteran_templates.veteran_improved_tag_allied_buff.related_talents ~= original_a
		and hits.veteran_redirect_tooltip == 2
		and actions.veteran_redirect_tooltip == 2,
	"legacy Redirect Fire metadata is measurably replaced on both templates"
)

veteran:on_disabled()

check(
	veteran_templates.veteran_improved_tag_allied_buff.related_talents == original_a
		and veteran_templates.veteran_improved_tag_allied_buff_increased_stacks.related_talents == original_b,
	"Redirect Fire metadata restores exact original identities"
)

reset_world()
veteran = dofile("scripts/mods/TertiumFixes/modules/veteran_redirect_tooltip.lua")
local fixed_a = {
	"veteran_improved_tag_dead_coherency_bonus",
}
local fixed_b = {
	"veteran_improved_tag_dead_coherency_bonus",
}
veteran_templates = {
	veteran_improved_tag_allied_buff = {
		related_talents = fixed_a,
	},
	veteran_improved_tag_allied_buff_increased_stacks = {
		related_talents = fixed_b,
	},
}

veteran:install()
deliver(veteran_path, veteran_templates)

check(
	veteran_templates.veteran_improved_tag_allied_buff.related_talents == fixed_a
		and veteran_templates.veteran_improved_tag_allied_buff_increased_stacks.related_talents == fixed_b
		and availability.veteran_redirect_tooltip == false
		and type(reasons.veteran_redirect_tooltip) == "string"
		and string.find(reasons.veteran_redirect_tooltip, "fixed upstream", 1, true) ~= nil
		and veteran:runtime_status() == "fixed upstream"
		and hits.veteran_redirect_tooltip == nil
		and actions.veteran_redirect_tooltip == nil,
	"Darktide 1.12.4 Redirect Fire fix is detected without a placebo mutation"
)

reset_world()
local prime = dofile("scripts/mods/TertiumFixes/modules/zealot_prime_target_tooltip.lua")
local prime_effect = {
	class_name = "buff",
	duration = 8,
	max_stacks = 3,
	predicted = false,
	refresh_duration_on_stack = true,
}

prime:install()
deliver("scripts/settings/buff/archetype_buff_templates/zealot_buff_templates", {
	zealot_elite_kills_empowers = {},
	zealot_elite_kills_empowers_effect = prime_effect,
})
deliver("scripts/settings/ability/archetype_talents/talents/zealot_talents", {
	talents = {
		zealot_elite_kills_empowers = {
			passive = {
				buff_template_name = "zealot_elite_kills_empowers",
			},
		},
	},
})

check(
	type(prime_effect.related_talents) == "table"
		and prime_effect.related_talents[1] == "zealot_elite_kills_empowers"
		and hits.zealot_prime_target_tooltip == 1
		and actions.zealot_prime_target_tooltip == 1,
	"Prime Target repair adds the exact missing tactical-overlay link"
)

prime:on_disabled()

check(prime_effect.related_talents == nil, "Prime Target repair restores the unmodified template")

reset_world()
local overload = dofile("scripts/mods/TertiumFixes/modules/power_overload_hud.lua")
local overload_target = {
	class_name = "buff",
	duration = 8,
	max_stacks = 1,
	max_stacks_cap = 1,
	predicted = false,
	refresh_duration_on_stack = true,
}
local overload_source = {
	hud_icon = "power-overload-icon",
	hud_icon_gradient_map = "keystone-gradient",
	hud_priority = 12,
	related_talents = {
		"cryptic_overload_keystone",
	},
}

overload:install()
deliver("scripts/settings/buff/archetype_buff_templates/cryptic_buff_templates", {
	cryptic_overload_keystone_allies_buff = overload_target,
	cryptic_overload_keystone_stack = overload_source,
})

check(
	overload_target.always_show_in_hud == true
		and overload_target.hud_icon == overload_source.hud_icon
		and overload_target.hud_icon_gradient_map == overload_source.hud_icon_gradient_map
		and overload_target.hud_priority == overload_source.hud_priority
		and overload_target.related_talents[1] == "cryptic_overload_keystone"
		and overload_target.related_talents ~= overload_source.related_talents
		and hits.power_overload_hud == 1
		and actions.power_overload_hud == 1,
	"Power Overload repair populates all five presentation fields"
)

overload:on_disabled()

check(
	overload_target.always_show_in_hud == nil
		and overload_target.hud_icon == nil
		and overload_target.hud_icon_gradient_map == nil
		and overload_target.hud_priority == nil
		and overload_target.related_talents == nil,
	"Power Overload repair restores all original presentation fields"
)

io.write(string.format("metadata_repairs_behavior: %d passed, %d failed\n", checks - failures, failures))

if failures > 0 then
	os.exit(1)
end
