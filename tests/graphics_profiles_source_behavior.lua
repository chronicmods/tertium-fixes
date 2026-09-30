local source_root = arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT")
if not source_root or source_root == "" then
	print("SKIP graphics profile source checks: set DARKTIDE_SOURCE_ROOT")
	return
end

local checks, failures = 0, 0
local function check(condition, message)
	checks = checks + 1
	if condition then
		print("PASS " .. message)
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function count(value)
	local total = 0
	for _ in pairs(value) do total = total + 1 end
	return total
end

PLATFORM, BUILD = "win32", "release"
IS_WINDOWS, IS_XBS, IS_PLAYSTATION, DEDICATED_SERVER = false, false, false, false
local user_values, native_values = {}, {}
local apply_count, bake_count, save_count, event_count = 0, 0, 0, 0
Application = {
	query_performance_counter = function () return 0 end,
	time_since_query = function () return 0 end,
	render_caps = function () return true end,
	user_setting = function (location, key)
		if key then return user_values[location] and user_values[location][key] end
		return user_values[location]
	end,
	set_user_setting = function (location, key, value)
		if value == nil then
			user_values[location] = key
		else
			user_values[location] = user_values[location] or {}
			user_values[location][key] = value
		end
	end,
	set_render_setting = function (key, value) native_values[key] = value end,
	apply_user_settings = function () apply_count = apply_count + 1 end,
	save_user_settings = function () save_count = save_count + 1 end,
}
Renderer = { bake_static_shadows = function () bake_count = bake_count + 1 end }
Managers = { event = { trigger = function (_, name)
	assert(name == "event_on_render_settings_applied")
	event_count = event_count + 1
end } }
Log = { info = function () end }
local dependencies = {
	["scripts/foundation/utilities/parameters/default_game_parameters"] = dofile(source_root .. "/scripts/foundation/utilities/parameters/default_game_parameters.lua"),
	["scripts/settings/options/settings_utils"] = dofile(source_root .. "/scripts/settings/options/settings_utils.lua"),
	["scripts/utilities/ui/options"] = { create_value_slider_template = function (params) return params end },
	["scripts/settings/region/region_constants"] = { restrictions = {} },
}
local original_require = require
function require(name)
	assert(dependencies[name], "unexpected game dependency: " .. name)
	return dependencies[name]
end
local options = dofile(source_root .. "/scripts/settings/options/render_settings.lua")
require = original_require
local utilities = options.settings_utilities

local profiles = dofile("scripts/mods/TertiumFixes/graphics_profiles.lua")
local ids = { "ultra_performance", "performance", "balanced", "quality" }
local labels = { "Ultra Performance", "Performance", "Balanced", "Quality" }
check(count(profiles) == 4, "graphics profiles contain exactly the four requested presets")

local native_allowed = {}
for _, option in ipairs(options.settings) do
	if option.save_location == "render_settings" then
		native_allowed[option.id] = native_allowed[option.id] or {}
	end
	for _, choice in ipairs(option.options or {}) do
		for key, value in pairs(choice.values and choice.values.render_settings or {}) do
			local values = native_allowed[key] or {}
			values[#values + 1] = value
			native_allowed[key] = values
		end
	end
end

local preserved_keys = {
	resolution = true, vertical_fov = true, gameplay_fov = true,
	dlss = true, dlss_g = true, dlss_master = true, dlss_models = true,
	dlss_enabled = true, dlss_g_enabled = true, dlss_model = true,
	fsr = true, fsr2 = true, xess = true, ffx_frame_gen = true,
	upscaling_enabled = true, upscaling_mode = true, upscaling_quality = true,
	texture_quality = true, outline_enabled = true, particles_capacity_multiplier = true,
	particles_simulation_lod = true, decals_enabled = true, display_noise_enabled = true,
	lod_object_multiplier = true, lod_scatter_density = true,
	max_ragdolls = true, max_impact_decals = true, max_blood_decals = true,
	max_footstep_decals = true, decal_lifetime = true,
}

for index, id in ipairs(ids) do
	local preset = profiles[id]
	check(preset.id == id and preset.label == labels[index] and type(preset.description) == "string",
		id .. " has its expected name and description")
	local native = preset.values.render_settings
	local masters = preset.values.master_render_settings
	local selectors_valid = true
	for key, value in pairs(masters) do
		local source_option = options.settings_by_id[key]
		local found = false
		for _, choice in ipairs(source_option and source_option.options or {}) do
			if choice.id == value then found = true end
		end
		selectors_valid = selectors_valid and found
	end
	check(selectors_valid and masters.graphics_quality == "custom",
		id .. " uses real stock master selectors rather than invented very-low or fog-off values")

	local controls_valid = true
	for key, value in pairs(native) do
		local allowed = native_allowed[key]
		local source_option = options.settings_by_id[key]
		local found = allowed ~= nil and #allowed == 0 and type(value) == "boolean"
			and source_option and source_option.save_location == "render_settings" and source_option.type ~= "slider"
		for _, source_value in ipairs(allowed or {}) do
			if same(source_value, value) or type(source_value) == "boolean" and type(value) == "boolean" then found = true end
		end
		controls_valid = controls_valid and found
	end
	check(controls_valid, id .. " uses current renderer keys and stock numeric, array and string values")

	local no_unrelated_writes = count(preset.values) == 2
	for _, settings in pairs(preset.values) do
		for key in pairs(settings) do no_unrelated_writes = no_unrelated_writes and not preserved_keys[key] end
	end
	check(no_unrelated_writes, id .. " preserves resolution, scaling, texture, gameplay and existing scene limits")
	check(native.dxr == false and native.rt_reflections_enabled == false and native.rtxgi_enabled == false
		and native.ssr_enabled == false and native.bloom_enabled == false and native.dof_enabled == false
		and native.motion_blur_enabled == false and native.lens_quality_enabled == false
		and native.skin_material_enabled == false and native.baked_ddgi == true,
		id .. " disables costly optional passes without removing baked scene lighting")

	user_values, native_values = {}, {}
	apply_count, bake_count, save_count, event_count = 0, 0, 0, 0
	for location, settings in pairs(preset.values) do
		for key, value in pairs(settings) do utilities.set_user_setting(location, key, value) end
	end
	utilities.apply_user_settings()
	utilities.save_user_settings()
	check(same(user_values, preset.values) and apply_count == 1 and bake_count == 1
		and save_count == 1 and event_count == 1,
		id .. " goes through the stock setting, apply, shadow-bake, event and save helpers")
	check(native_values.dxr == "false" and native_values.baked_ddgi == "true"
		and native_values.volumetric_data_size == nil,
		id .. " sends scalar render values as strings and leaves arrays for the apply step")
end

local function stock_values(option_id, value)
	for _, option in ipairs(options.settings_by_id[option_id].options) do
		if option.id == value then return option.values.render_settings end
	end
	error("stock option was not found")
end
local function includes(actual, expected)
	for key, value in pairs(expected) do if not same(actual[key], value) then return false end end
	return true
end

check(includes(profiles.balanced.values.render_settings, stock_values("light_quality", "low"))
	and includes(profiles.quality.values.render_settings, stock_values("light_quality", "medium")),
	"Balanced and Quality use the complete installed Low and Medium shadow settings")
check(includes(profiles.performance.values.render_settings, stock_values("volumetric_fog_quality", "low"))
	and includes(profiles.balanced.values.render_settings, stock_values("volumetric_fog_quality", "low"))
	and includes(profiles.quality.values.render_settings, stock_values("volumetric_fog_quality", "medium")),
	"Performance, Balanced and Quality preserve the installed fog grids and lighting controls")
check(profiles.ultra_performance.values.render_settings.volumetric_volumes_enabled == false
	and profiles.performance.values.render_settings.volumetric_volumes_enabled == true,
	"only Ultra Performance removes general fog volumes")
check(profiles.ultra_performance.description:find("gas", 1, true) ~= nil,
	"Ultra Performance states that the fog change can affect gas appearance")
for _, id in ipairs({ "ultra_performance", "performance" }) do
	local native = profiles[id].values.render_settings
	check(native.local_lights_shadows_enabled == false and native.static_sun_shadows == false
		and native.sun_shadows == false and native.local_lights_shadow_atlas_size == nil
		and native.static_sun_shadow_map_size == nil and native.sun_shadow_map_size == nil,
		id .. " does not enlarge shadow resources while disabling their passes")
end
local original_size = profiles.balanced.values.render_settings.volumetric_data_size[1]
profiles.ultra_performance.values.render_settings.volumetric_data_size[1] = 1
check(profiles.balanced.values.render_settings.volumetric_data_size[1] == original_size,
	"profile arrays are independent and cannot change another preset")

print(string.format("\nGraphics profile source checks: %d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
