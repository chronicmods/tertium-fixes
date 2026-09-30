local root = arg[1] or os.getenv("DARKTIDE_SOURCE_ROOT")
if not root then print("SKIP graphics controller source checks") return end
local factory = dofile(root .. "/scripts/settings/options/settings_utils.lua")
local profiles = dofile("scripts/mods/TertiumFixes/graphics_profiles.lua")
local module_path = "scripts/mods/TertiumFixes/modules/graphics_presets.lua"
local checks, failures = 0, 0

local function check(ok, message)
	checks = checks + 1
	if ok then print("PASS " .. message) else failures = failures + 1 io.stderr:write("FAIL " .. message .. "\n") end
end
local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = clone(item) end
	return result
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end

local function setup(enabled, saved, native, storage)
	local ctx = { saved = saved or {}, native = native or {}, storage = storage or {}, writes = {}, events = {}, saves = 0, applies = 0, bakes = 0, options = { graphics_presets_enabled = enabled, graphics_preset = "performance" } }
	if not saved then
		for _, profile in pairs(profiles) do
			for location, values in pairs(profile.values) do
				ctx.saved[location] = ctx.saved[location] or {}
				for key, value in pairs(values) do
					local original
					if type(value) == "boolean" then original = not value
					elseif type(value) == "number" then original = value + 1
					elseif type(value) == "table" then original = { 128, 128 } if #value == 3 then original[3] = 48 end
					else original = "old_" .. tostring(value) end
					ctx.saved[location][key] = clone(original)
					if location == "render_settings" then ctx.native[key] = clone(original) end
				end
			end
		end
	end
	ctx.saved.render_settings = ctx.saved.render_settings or {}
	ctx.saved.master_render_settings = ctx.saved.master_render_settings or {}
	ctx.saved.render_settings.vertical_fov = 85
	ctx.saved.render_settings.upscaling_quality = "performance"
	ctx.saved.screen_resolution = { 5120, 1440 }
	ctx.original = clone(ctx.saved)
	ctx.native_original = clone(ctx.native)
	ctx.active = true
	DEDICATED_SERVER, WINDOW_RECT_OVERRIDE = false, nil
	Log = { info = function() end }
	Managers = { event = { trigger = function(_, name)
		ctx.events[#ctx.events + 1] = name
		if ctx.on_apply then ctx.on_apply() end
	end } }
	Application = {
		query_performance_counter = function() return 0 end,
		time_since_query = function() return 0 end,
		user_setting = function(location, key)
			if ctx.fail_render_table and location == "render_settings" and key == nil then return nil end
			if ctx.fail_read and ctx.fail_read == key then error("read failed") end
			if key == nil then return clone(ctx.saved[location]) end
			return ctx.saved[location] and clone(ctx.saved[location][key])
		end,
		set_user_setting = function(location, key, value)
			if ctx.fail_saved_write and ctx.fail_saved_write(location, key, value) then error("saved setting failed") end
			ctx.writes[#ctx.writes + 1] = { location, key, clone(value) }
			if value == nil then ctx.saved[location] = clone(key)
			else ctx.saved[location] = ctx.saved[location] or {} ctx.saved[location][key] = clone(value) end
		end,
		render_config = function(_, key) return clone(ctx.native[key]) end,
		set_render_setting = function(key, value)
			if ctx.fail_native == key then ctx.fail_native = nil error("native setting failed") end
			if ctx.fail_native_always == key then error("native setting still failing") end
			if value == "true" then value = true elseif value == "false" then value = false else value = tonumber(value) or value end
			ctx.native[key] = value
		end,
		apply_user_settings = function()
			ctx.applies = ctx.applies + 1
			if ctx.fail_apply then ctx.fail_apply = false error("apply failed") end
			for key, value in pairs(ctx.saved.render_settings) do ctx.native[key] = clone(value) end
		end,
		save_user_settings = function() end,
	}
	Renderer = { bake_static_shadows = function() ctx.bakes = ctx.bakes + 1 end }
	local runtime = {}
	function runtime:is_active() return ctx.active and ctx.options.graphics_presets_enabled end
	function runtime:mod_is_enabled() return ctx.active end
	function runtime:get(key) return ctx.options[key] end
	function runtime:record_hit() ctx.hits = (ctx.hits or 0) + 1 end
	function runtime:record_action(_, amount) ctx.actions = (ctx.actions or 0) + amount end
	function runtime:set_available(_, available) ctx.available = available end
	function runtime:defer_file(_, _, callback) callback(factory) return true end
	local mod = { _tf_runtime = runtime }
	function mod:io_dofile() return clone(profiles) end
	function mod:get(key) return clone(ctx.storage[key]) end
	function mod:set(key, value) ctx.storage[key] = clone(value) end
	function mod:info() end
	local dmf = { save_unsaved_settings_to_file = function()
		ctx.saves = ctx.saves + 1
		ctx.events[#ctx.events + 1] = "save"
		if ctx.saves == ctx.fail_save then error("save failed") end
		ctx.saved.mods_settings = { TertiumFixes = clone(ctx.storage) }
	end }
	function get_mod(name) if name == "DMF" then return dmf else return mod end end
	ctx.mod = mod
	ctx.module = dofile(module_path)
	ctx.module:install()
	return ctx
end

local ctx = setup(false)
ctx.module:on_all_mods_loaded()
check(ctx.saves == 0 and #ctx.writes == 0 and ctx.applies == 0, "disabled graphics with no prior ownership changes nothing")
check(ctx.module.update == nil, "graphics presets add no per-frame settings loop")

ctx = setup(true)
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.ao_enabled == false and ctx.native.ao_enabled == false, "Performance turns real AO flags off")
check(ctx.saved.render_settings.local_lights_shadows_enabled == false and ctx.native.sun_shadows == false, "Performance disables shadow passes")
check(ctx.native.volumetric_volumes_enabled == true and ctx.native.volumetric_lighting_local_lights == false, "Performance retains low fog volumes without extra fog lighting")
check(ctx.applies == 1 and ctx.bakes == 1, "one preset uses one native apply and shadow bake")
check(ctx.events[1] == "save" and ctx.events[#ctx.events] == "save", "originals are saved before changes and the finished state is saved afterwards")
check(ctx.native.vertical_fov == 85 and same(ctx.saved.screen_resolution, {5120, 1440}) and ctx.native.upscaling_quality == "performance", "resolution, FOV and upscaling choices are retained")
local owned = ctx.mod:get("graphics_restore_data").entries
check(owned["render_settings/ao_enabled"].pending == false, "a completed batch is no longer marked pending")

ctx.options.graphics_preset = "quality"
ctx.module:on_setting_changed("graphics_preset")
check(ctx.native.local_lights_shadows_enabled == true and same(ctx.native.local_lights_shadow_atlas_size, {1024, 1024}), "Quality applies the stock medium lighting payload")
ctx.options.graphics_preset = "performance"
ctx.module:on_setting_changed("graphics_preset")
check(same(ctx.saved.render_settings.local_lights_shadow_atlas_size, ctx.original.render_settings.local_lights_shadow_atlas_size), "switching to Performance restores omitted shadow-map dimensions")
check(ctx.mod:get("graphics_restore_data").entries["render_settings/local_lights_shadow_atlas_size"] == nil, "an omitted and restored field releases ownership")
ctx.options.graphics_preset = "ultra_performance"
ctx.module:on_setting_changed("graphics_preset")
check(ctx.native.volumetric_volumes_enabled == false, "Ultra Performance disables the actual fog-volume flag")
ctx.options.graphics_presets_enabled = false
ctx.module:on_setting_changed("graphics_presets_enabled")
check(same(ctx.saved.render_settings.ao_enabled, ctx.original.render_settings.ao_enabled), "disable restores the original AO value")
check(same(ctx.saved.master_render_settings, ctx.original.master_render_settings), "disable restores original master labels, including non-stock labels")
check(next(ctx.mod:get("graphics_restore_data").entries) == nil, "completed restoration clears ownership")

ctx = setup(true)
ctx.saved.render_settings.ao_enabled = false
ctx.native.ao_enabled = false
ctx.options.graphics_preset = "quality"
ctx.module:on_all_mods_loaded()
ctx.options.graphics_preset = "balanced"
ctx.module:on_setting_changed("graphics_preset")
ctx.module:on_disabled()
check(ctx.saved.render_settings.ao_enabled == false and ctx.native.ao_enabled == false, "an original false survives multiple enabled profiles and restoration")

ctx = setup(true)
ctx.saved.render_settings.ao_enabled = true
ctx.native.ao_enabled = false
ctx.options.graphics_preset = "quality"
ctx.module:on_all_mods_loaded()
ctx.module:on_disabled()
check(ctx.saved.render_settings.ao_enabled == true and ctx.native.ao_enabled == false, "different saved and effective originals are restored independently")

ctx = setup(true)
ctx.module:on_all_mods_loaded()
ctx.saved.render_settings.bloom_enabled = true
ctx.native.bloom_enabled = true
ctx.module:on_disabled()
check(ctx.saved.render_settings.bloom_enabled == true and ctx.native.bloom_enabled == true, "a later external graphics change survives disable")

ctx = setup(true)
ctx.native.vertical_fov = 100
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.vertical_fov == 85 and ctx.native.vertical_fov == 100,
	"global apply retains a live override outside the preset keys")
ctx.module:on_disabled()
check(ctx.saved.render_settings.vertical_fov == 85 and ctx.native.vertical_fov == 100,
	"global restoration retains a live override outside the preset keys")

ctx = setup(true)
ctx.saved.render_settings.gtao_quality = 0
ctx.native.gtao_quality = 0
ctx.options.graphics_preset = "quality"
ctx.module:on_all_mods_loaded()
ctx.native.gtao_quality = 9
ctx.module:on_unload()
local reload_saved, reload_native, reload_storage = clone(ctx.saved), clone(ctx.native), clone(ctx.storage)
ctx = setup(false, reload_saved, reload_native, reload_storage)
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.gtao_quality == 0 and ctx.native.gtao_quality == 9,
	"unload and disabled reload preserve a later live override of an owned key")

ctx = setup(true)
ctx.native.vertical_fov = 100
ctx.fail_saved_write = function(location, key, value)
	return location == "render_settings" and key == "vertical_fov" and value == 85
end
local staged_ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
local staged = ctx.mod:get("graphics_restore_data").passthrough or {}
check(not staged_ok and staged["render_settings/vertical_fov"] ~= nil,
	"a failed temporary-value restore retains the durable passthrough record")
reload_saved, reload_native, reload_storage = clone(ctx.saved), clone(ctx.native), clone(ctx.storage)
ctx = setup(false, reload_saved, reload_native, reload_storage)
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.vertical_fov == 85 and ctx.native.vertical_fov == 100
	and next(ctx.mod:get("graphics_restore_data").passthrough or {}) == nil,
	"a new instance recovers the saved value left by an interrupted passthrough restore")

ctx = setup(true)
ctx.saved.render_settings.viewport_size = { 1600, 900 }
ctx.native.viewport_size = { 1920, 1080 }
ctx.module:on_all_mods_loaded()
check(same(ctx.saved.render_settings.viewport_size, { 1600, 900 }) and same(ctx.native.viewport_size, { 1920, 1080 }),
	"temporary pass-through retains a numeric array outside the preset keys")
ctx.module:on_disabled()
check(same(ctx.saved.render_settings.viewport_size, { 1600, 900 }) and same(ctx.native.viewport_size, { 1920, 1080 }),
	"numeric arrays outside the preset keys retain separate saved and live values after disable")

ctx = setup(false)
ctx.saved.render_settings.vertical_fov = 100
ctx.native.vertical_fov = 100
ctx.mod:set("graphics_restore_data", { version = 1, entries = {}, passthrough = {
	["render_settings/vertical_fov"] = { location = "render_settings", key = "vertical_fov", saved = 85, effective = 100 },
} })
ctx.fail_render_table = true
local unavailable_ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not unavailable_ok and #ctx.writes == 0 and ctx.saves == 0
	and ctx.mod:get("graphics_restore_data").passthrough["render_settings/vertical_fov"] ~= nil,
	"unreadable renderer settings leave interrupted passthrough recovery intact")
ctx.fail_render_table = false
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.vertical_fov == 85 and ctx.native.vertical_fov == 100,
	"interrupted passthrough recovery retries when the renderer table is readable")

ctx = setup(false)
ctx.saved.master_render_settings.unrelated_setting = 2
ctx.saved.render_settings.holey_array = { 1, 2, 3 }
ctx.mod:set("graphics_restore_data", { version = 1, entries = {
	["render_settings/vertical_fov"] = { location = "render_settings", key = "vertical_fov", original = 70, applied = 85 },
}, passthrough = {
	["master_render_settings/unrelated_setting"] = { location = "master_render_settings", key = "unrelated_setting", saved = 1, effective = 2 },
	["render_settings/missing_key"] = { location = "render_settings", key = "missing_key", saved = 1, effective = 2 },
	["render_settings/wrong_key"] = { location = "render_settings", key = "vertical_fov", saved = 70, effective = 85 },
	["render_settings/vertical_fov"] = { location = "render_settings", key = "vertical_fov", saved = {}, effective = 85 },
	["render_settings/holey_array"] = { location = "render_settings", key = "holey_array", saved = { [1] = 1, [3] = 3 }, effective = { 1, 2, 3 } },
} })
ctx.module:on_all_mods_loaded()
check(#ctx.writes == 0 and ctx.saved.master_render_settings.unrelated_setting == 2
	and ctx.saved.render_settings.missing_key == nil and ctx.saved.render_settings.vertical_fov == 85
	and same(ctx.saved.render_settings.holey_array, { 1, 2, 3 }),
	"recovery rejects other namespaces, absent keys, mismatched names and invalid values")
check(ctx.saves == 0 and ctx.applies == 0,
	"an unapproved baseline key cannot acquire ownership from a stored record")

ctx = setup(true)
ctx.saved.render_settings.ao_enabled = nil
ctx.native.ao_enabled = true
ctx.module:on_all_mods_loaded()
ctx.module:on_disabled()
check(ctx.saved.render_settings.ao_enabled == true and ctx.native.ao_enabled == true, "a missing saved key can restore a readable effective original")
ctx = setup(true)
ctx.saved.render_settings.ao_enabled = nil
ctx.native.ao_enabled = nil
ctx.module:on_all_mods_loaded()
check(ctx.saved.render_settings.ao_enabled == nil and ctx.module._skipped > 0, "an unreadable original is skipped rather than guessed")

ctx = setup(true)
ctx.fail_save = 1
local ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and #ctx.writes == 0 and ctx.applies == 0 and not ctx.module._busy, "backup-save failure cannot change renderer settings or strand the busy flag")

ctx = setup(true)
ctx.saved.render_settings.ao_enabled = true
ctx.native.ao_enabled = true
ctx.original = clone(ctx.saved)
ctx.native_original = clone(ctx.native)
ctx.fail_native = "ao_enabled"
ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and same(ctx.saved.render_settings, ctx.original.render_settings), "a partial native setter failure rolls back saved values")
check(ctx.native.ao_enabled == ctx.native_original.ao_enabled and not ctx.module._busy, "a partial native setter failure restores the effective value")

ctx = setup(true)
ctx.fail_apply = true
ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and same(ctx.saved.render_settings, ctx.original.render_settings), "a failed apply rolls the batch back")

ctx = setup(true)
ctx.fail_save = 2
ctx.options.graphics_preset = "quality"
ctx.on_apply = function()
	ctx.on_apply = nil
	ctx.saved.render_settings.local_lights_shadow_atlas_size = {2048, 2048}
	ctx.native.local_lights_shadow_atlas_size = {2048, 2048}
end
ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and same(ctx.saved.render_settings.local_lights_shadow_atlas_size, {2048, 2048})
	and same(ctx.native.local_lights_shadow_atlas_size, {2048, 2048}), "rollback preserves an external edit made by an apply-event callback")

ctx = setup(true)
ctx.saved.render_settings.ao_enabled = true
ctx.native.ao_enabled = true
ctx.original = clone(ctx.saved)
ctx.native_original = clone(ctx.native)
ctx.fail_native_always = "ao_enabled"
ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and next(ctx.mod:get("graphics_restore_data").entries) ~= nil, "failed native rollback retains a recovery journal")
ctx.fail_native_always = nil
ctx.module:on_disabled()
check(ctx.saved.render_settings.ao_enabled == ctx.original.render_settings.ao_enabled, "later cleanup can recover after native calls work again")

ctx = setup(true)
ctx.options.graphics_preset = "quality"
ctx.module:on_all_mods_loaded()
local old_applies, old_bakes = ctx.applies, ctx.bakes
ctx.module:on_unload()
check(ctx.applies == old_applies and ctx.bakes == old_bakes, "unload never applies renderer settings or bakes into a closing world")
check(same(ctx.saved.render_settings, ctx.original.render_settings), "unload restores saved originals")
check(next(ctx.mod:get("graphics_restore_data").entries) ~= nil, "unload retains the live renderer's unfinished recovery record")
local saved, native, storage, original_native = clone(ctx.saved), clone(ctx.native), clone(ctx.storage), clone(ctx.native_original)
ctx = setup(false, saved, native, storage)
ctx.module:on_all_mods_loaded()
check(same(ctx.native.ao_enabled, original_native.ao_enabled) and next(ctx.mod:get("graphics_restore_data").entries) == nil, "a disabled reload completes native restoration instead of inheriting the preset")

ctx = setup(true)
WINDOW_RECT_OVERRIDE = true
ok = pcall(ctx.module.on_all_mods_loaded, ctx.module)
check(not ok and #ctx.writes == 0 and ctx.saves == 0, "a launch-window override cannot claim an unapplied graphics preset")
WINDOW_RECT_OVERRIDE = nil

ctx = setup(true)
ctx.active = false
ctx.module:on_all_mods_loaded()
check(#ctx.writes == 0, "an inactive or quarantined module cannot apply a preset through a deferred callback")

print(string.format("graphics_presets_source_behavior: %d passed, %d failed", checks - failures, failures))
if failures > 0 then os.exit(1) end
