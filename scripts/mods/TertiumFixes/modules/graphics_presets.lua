local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime
local profiles = mod:io_dofile("TertiumFixes/scripts/mods/TertiumFixes/graphics_profiles")
local SAVE_KEY = "graphics_restore_data"
local UTILS_PATH = "scripts/settings/options/settings_utils"

local module = {
	id = "graphics_presets",
	label = "Graphics presets",
	setting_id = "graphics_presets_enabled",
	_ready = false,
	_busy = false,
	_changed = 0,
	_skipped = 0,
}

local allowed = {}
for _, profile in pairs(profiles) do
	for location, values in pairs(profile.values) do
		for key in pairs(values) do allowed[location .. "/" .. key] = true end
	end
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for i = 1, #value do result[i] = value[i] end
	return result
end

local function or_default(value, fallback)
	if value == nil then return fallback end
	return value
end

local function valid(value)
	local kind = type(value)
	if kind == "boolean" or kind == "string" then return true end
	if kind == "number" then return value == value and value ~= math.huge and value ~= -math.huge end
	if kind ~= "table" or #value < 1 or #value > 4 then return false end
	for i = 1, #value do if type(value[i]) ~= "number" or not valid(value[i]) then return false end end
	for key, item in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > #value or key % 1 ~= 0
			or type(item) ~= "number" or not valid(item) then return false end
	end
	return true
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for i = 1, #a do if a[i] ~= b[i] then return false end end
	return true
end

local function entries_copy(entries)
	local result = {}
	for id, entry in pairs(entries) do
		local clone = {}
		for key, value in pairs(entry) do clone[key] = copy(value) end
		result[id] = clone
	end
	return result
end

function module:_journal()
	local saved = mod:get(SAVE_KEY)
	local result = {}
	if type(saved) ~= "table" or saved.version ~= 1 or type(saved.entries) ~= "table" then return result end
	for id, entry in pairs(saved.entries) do
		if allowed[id] and type(entry) == "table"
			and (entry.location == "render_settings" or entry.location == "master_render_settings")
			and type(entry.key) == "string" and id == entry.location .. "/" .. entry.key
			and valid(entry.original) and valid(entry.applied)
			and (entry.previous == nil or valid(entry.previous))
			and (entry.original_effective == nil or valid(entry.original_effective))
			and (entry.applied_effective == nil or valid(entry.applied_effective))
			and (entry.previous_effective == nil or valid(entry.previous_effective)) then
			result[id] = {
				location = entry.location, key = entry.key, original = copy(entry.original),
				applied = copy(entry.applied), previous = copy(entry.previous), pending = entry.pending == true,
				original_effective = copy(entry.original_effective), applied_effective = copy(entry.applied_effective),
				previous_effective = copy(entry.previous_effective),
			}
		end
	end
	return result
end

function module:_persist(entries, passthrough)
	local dmf = get_mod("DMF")
	if not dmf or type(dmf.save_unsaved_settings_to_file) ~= "function" then
		error("Mod Framework cannot save the graphics backup")
	end
	local data = { version = 1, entries = entries_copy(entries), passthrough = entries_copy(passthrough or {}) }
	mod:set(SAVE_KEY, data)
	dmf.save_unsaved_settings_to_file()
	local settings = Application.user_setting("mods_settings")
	local saved = type(settings) == "table" and settings.TertiumFixes
	saved = type(saved) == "table" and saved[SAVE_KEY]
	if type(saved) ~= "table" or type(saved.entries) ~= "table" then error("Graphics backup was not saved") end
	for id, entry in pairs(data.entries) do
		local row = saved.entries[id]
		if type(row) ~= "table" or not same(row.original, entry.original) or not same(row.applied, entry.applied)
			or not same(row.previous, entry.previous) or row.pending ~= entry.pending
			or not same(row.original_effective, entry.original_effective)
			or not same(row.applied_effective, entry.applied_effective)
			or not same(row.previous_effective, entry.previous_effective) then
			error("Graphics backup differs from the requested values")
		end
	end
	for id in pairs(saved.entries) do if not data.entries[id] then error("Graphics backup retained an old entry") end end
	local stored_passthrough = saved.passthrough or {}
	for id, entry in pairs(data.passthrough) do
		local row = stored_passthrough[id]
		if type(row) ~= "table" or row.location ~= entry.location or row.key ~= entry.key
			or not same(row.saved, entry.saved) or not same(row.effective, entry.effective) then
			error("Graphics backup did not retain a live override")
		end
	end
	for id in pairs(stored_passthrough) do if not data.passthrough[id] then error("Graphics backup retained an old live override") end end
end

function module:_effective(location, key)
	if location == "render_settings" and type(Application.render_config) == "function" then
		local ok, effective = pcall(Application.render_config, "settings", key)
		if ok and valid(effective) then return copy(effective) end
	end
end

function module:_current(location, key)
	local value = self._utils.get_user_setting(location, key)
	if valid(value) then return copy(value) end
	return self:_effective(location, key)
end

function module:_needs_write(location, key, value, effective, saved_only)
	if not same(self._utils.get_user_setting(location, key), value) then return true end
	if not saved_only then
		local current = self:_effective(location, key)
		if current ~= nil and effective ~= nil and not same(current, effective) then return true end
	end
	return false
end

local function owns(entry, current, effective, saved_only)
	if not entry then return false end
	local saved_matches = same(current, entry.applied)
		or entry.pending and (same(current, entry.previous)
			or entry.applied_effective ~= nil and same(current, entry.applied_effective)
			or entry.previous_effective ~= nil and same(current, entry.previous_effective))
	if not saved_matches or saved_only or effective == nil then return saved_matches end
	return same(effective, or_default(entry.applied_effective, entry.applied))
		or entry.pending and same(effective, or_default(entry.previous_effective, entry.previous))
end

function module:_passthrough()
	local saved = mod:get(SAVE_KEY)
	local held = type(saved) == "table" and saved.version == 1 and saved.passthrough
	local result = {}
	if type(held) ~= "table" or next(held) == nil then return result end
	local settings = self._utils.get_user_setting("render_settings")
	if type(settings) ~= "table" then error("Renderer settings unavailable") end
	for id, row in pairs(held) do
		if type(row) == "table" and row.location == "render_settings"
			and type(row.key) == "string" and row.key ~= "" and id == row.location .. "/" .. row.key
			and valid(settings[row.key]) and valid(row.saved) and valid(row.effective) then
			result[id] = { location = row.location, key = row.key, saved = copy(row.saved), effective = copy(row.effective) }
		end
	end
	return result
end

function module:_recover_staged()
	local held = self:_passthrough()
	if next(held) == nil then return end
	for _, row in pairs(held) do
		if same(self._utils.get_user_setting(row.location, row.key), row.effective) then
			Application.set_user_setting(row.location, row.key, copy(row.saved))
		end
	end
	self:_persist(self:_journal())
end

function module:_apply_batch(plan, operations, rollback)
	local writing = {}
	local any_write = false
	for _, operation in ipairs(operations) do
		if operation.write and (not rollback or operation.rollback) then writing[operation.id] = true any_write = true end
	end
	if not any_write then return end
	self:_recover_staged()

	-- Applying the saved renderer table also touches keys outside this batch.
	-- Keep another owner's live override in place, then put its saved value back.
	local held = {}
	local settings = self._utils.get_user_setting("render_settings")
	if type(settings) ~= "table" then error("Renderer settings unavailable") end
	for key, current in pairs(settings) do
		local id = type(key) == "string" and "render_settings/" .. key
		if id and key ~= "" and not writing[id] then
			local effective = self:_effective("render_settings", key)
			if valid(current) and effective ~= nil and not same(current, effective) then
				held[id] = { location = "render_settings", key = key, saved = copy(current), effective = copy(effective) }
			end
		end
	end
	if next(held) ~= nil then self:_persist(plan, held) end
	local ok, err = pcall(function()
		for _, row in pairs(held) do Application.set_user_setting(row.location, row.key, copy(row.effective)) end
		self._utils.apply_user_settings()
	end)
	local restore_error
	for _, row in pairs(held) do
		local restored, reason = pcall(function()
			if same(self._utils.get_user_setting(row.location, row.key), row.effective) then
				Application.set_user_setting(row.location, row.key, copy(row.saved))
			end
		end)
		if not restored then restore_error = reason end
	end
	if restore_error then error(restore_error) end
	if not ok then error(err) end
end

function module:_write(entry, value, saved_only)
	if saved_only then
		Application.set_user_setting(entry.location, entry.key, copy(value))
	else
		self._utils.set_user_setting(entry.location, entry.key, copy(value))
	end
end

function module:_plan(values, saved_only)
	local previous = self:_journal()
	local plan, desired, operations = {}, {}, {}
	local skipped = 0
	for location, settings in pairs(values) do
		for key, value in pairs(settings) do
			local id = location .. "/" .. key
			if not allowed[id] or not valid(value) then error("Invalid graphics profile entry: " .. id) end
			desired[id] = { location = location, key = key, value = value }
		end
	end
	local ids = {}
	for id in pairs(desired) do ids[#ids + 1] = id end
	for id in pairs(previous) do if not desired[id] then ids[#ids + 1] = id end end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local target, old = desired[id], previous[id]
		local location, key = (target or old).location, (target or old).key
		local current = self:_current(location, key)
		local effective = self:_effective(location, key)
		local still_owned = owns(old, current, effective, saved_only)
		if current == nil then
			skipped = skipped + 1
			if old then plan[id] = old end
		elseif target or still_owned then
			local original, original_effective = current, effective
			if still_owned then
				original, original_effective = old.original, old.original_effective
				if saved_only and not owns(old, current, effective, false) then original_effective = effective end
			end
			local value, native_value
			if target then
				value, native_value = target.value, target.value
			else
				value, native_value = original, or_default(original_effective, original)
			end
			local entry = {
				location = location, key = key, original = copy(original),
				applied = copy(value), previous = copy(current), pending = true,
				original_effective = copy(original_effective), applied_effective = copy(native_value),
				previous_effective = copy(effective),
			}
			plan[id] = entry
			operations[#operations + 1] = {
				id = id, entry = entry, value = copy(value), before = copy(current),
				effective = copy(native_value), before_effective = copy(effective),
				release = target == nil,
				write = self:_needs_write(location, key, value, native_value, saved_only),
			}
		end
	end
	return previous, plan, operations, skipped
end

function module:_change(values, saved_only)
	if self._busy then return false, "A graphics change is already running" end
	if not self._utils then return false, "Waiting for graphics settings" end
	if not saved_only and rawget(_G, "WINDOW_RECT_OVERRIDE") then return false, "Graphics apply is disabled by the launch window override" end
	self._busy = true
	local previous, plan, operations, skipped
	local changed = 0
	local started = false
	local ok, err = pcall(function()
		self:_recover_staged()
		previous, plan, operations, skipped = self:_plan(values, saved_only)
		if next(previous) == nil and next(plan) == nil then return end
		-- Save originals before touching the renderer so a later launch can recover.
		self:_persist(plan)
		started = true
		for _, operation in ipairs(operations) do
			if operation.write then
				local value = operation.effective
				if saved_only then value = operation.value end
				self:_write(operation.entry, value, saved_only)
				changed = changed + 1
			end
		end
		if changed > 0 and not saved_only then self:_apply_batch(plan, operations, false) end
		local completed = entries_copy(plan)
		for _, operation in ipairs(operations) do
			if operation.write and not saved_only and not same(operation.value, operation.effective) then
				self:_write(operation.entry, operation.value, true)
			end
			if saved_only then
				-- The saved value is restored, but the old renderer may still be live
				-- during a mod reload. Keep its recovery record for the next instance.
			elseif operation.release then
				completed[operation.id] = nil
			else
				completed[operation.id].pending = false
				completed[operation.id].previous = nil
				completed[operation.id].previous_effective = nil
			end
		end
		self:_persist(completed)
	end)

	if not ok and started then
		local restored = true
		for i = #operations, 1, -1 do
			local operation = operations[i]
			if operation.write then
				local readable, current = pcall(self._current, self, operation.entry.location, operation.entry.key)
				if not readable then
					restored = false
				elseif owns(operation.entry, current, self:_effective(operation.entry.location, operation.entry.key), saved_only) then
					operation.rollback = true
					local value = operation.before_effective
					if saved_only or value == nil then value = operation.before end
					local restore_ok = pcall(self._write, self, operation.entry, value, saved_only)
					restored = restore_ok and restored
				end
			end
		end
		if not saved_only then restored = pcall(self._apply_batch, self, plan, operations, true) and restored end
		for _, operation in ipairs(operations) do
			if operation.rollback then
				local restore_ok = pcall(self._write, self, operation.entry, operation.before, true)
				restored = restore_ok and restored
			end
		end
		-- If native rollback failed, keep both possible values in the saved journal.
		pcall(function() self:_persist(restored and previous or plan, self:_passthrough()) end)
	end
	self._busy = false
	if not ok then return false, tostring(err) end
	self._changed, self._skipped = changed, skipped
	if changed > 0 then runtime:record_hit(self.id) runtime:record_action(self.id, changed) end
	return true, changed, skipped
end

function module:_apply()
	if not self._ready or not self._utils then return end
	local enabled = runtime:is_active(self.id)
	local id = runtime:get("graphics_preset")
	local profile = profiles[id]
	if enabled and not profile then error("Unknown graphics preset: " .. tostring(id)) end
	local ok, changed, skipped = self:_change(enabled and profile.values or {})
	if not ok then error(changed) end
	self._selected = enabled and id or nil
	if enabled or changed > 0 then
		mod:info("Graphics %s: %d settings changed, %d left without a readable original", enabled and profile.label or "restored", changed, skipped)
	end
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") then
		runtime:set_available(self.id, false, "dedicated server")
		return
	end
	runtime:defer_file(self.id, UTILS_PATH, function(factory)
		if type(factory) ~= "function" then
			runtime:set_available(self.id, false, "Graphics settings helpers unavailable")
			return
		end
		self._utils = factory({})
		runtime:set_available(self.id, true)
		if self._ready then self:_apply() end
	end)
end

function module:on_all_mods_loaded()
	self._ready = true
	self:_apply()
end

function module:on_enabled() self:_apply() end

function module:on_setting_changed(id)
	if id == self.setting_id or id == "graphics_preset" then self:_apply() end
end

function module:on_disabled()
	if self._utils then
		local ok, err = self:_change({})
		if not ok then error(err) end
		self._selected = nil
	end
end

function module:on_unload()
	-- World teardown may already have started. Restore saved values without baking.
	if self._utils then
		local ok, err = self:_change({}, true)
		if not ok then error(err) end
	end
end

function module:reset() self:_apply() end

function module:runtime_status()
	return self._selected and profiles[self._selected].label or "disabled"
end

function module:describe()
	return string.format("%d settings changed; %d originals unreadable", self._changed, self._skipped)
end

return module
