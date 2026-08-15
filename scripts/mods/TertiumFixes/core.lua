local mod = get_mod("TertiumFixes")

local Runtime = {}

Runtime.__index = Runtime
Runtime.version = "0.5.1"
local _unpack = unpack or table.unpack
Runtime.defaults = {
	auto_quarantine_enabled = true,
	auto_quarantine_threshold = 3,
	cursor_stack_enabled = true,
	input_device_handoff_enabled = true,
	rumble_apply_enabled = true,
	veteran_redirect_tooltip_enabled = true,
	zealot_prime_target_tooltip_enabled = true,
	power_overload_hud_enabled = true,
	chain_smoke_cleanup_enabled = false,
	servo_skull_scroll_enabled = false,
	notification_dedupe_enabled = true,
	notification_dedupe_window_seconds = 2,
	notification_include_mission = false,
	localization_guard_enabled = true,
	localization_fallback_mode = "diagnostic",
	gc_enabled = true,
	gc_cleaning_permitted = true,
	gc_capacity_fallback_mb = 1024,
	gc_convenient_cleanup_enabled = true,
	gc_periodic_cleanup_enabled = false,
	gc_notifications_enabled = true,
	gc_hud_enabled = true,
	gc_hud_x_percent = 5,
	gc_hud_y_percent = 65,
	gc_shutdown_diagnostic_enabled = true,
	campaign_vox_cleanup_enabled = true,
	player_buff_removal_enabled = true,
	penance_carousel_scroll_enabled = true,
	path_of_trust_black_screen_enabled = true,
	gas_outline_recovery_enabled = true,
	player_fx_lifecycle_enabled = true,
	effect_template_safety_enabled = true,
	event_listener_cleanup_enabled = true,
	audio_source_cleanup_enabled = true,
	fx_handler_integrity_enabled = true,
	fx_handler_local_rewrite_enabled = false,
	fx_handler_rpc_idempotence_enabled = false,
	stimm_field_deleted_extension_guard_enabled = true,
	hive_scum_stimm_chime_enabled = true,
	training_grounds_danger_index_guard_enabled = true,
	diagnostic_logging = true,
}

local function _clean_error(err)
	local text = tostring(err or "unknown error")

	text = string.gsub(text, "[\r\n]+", " ")

	if #text > 300 then
		text = string.sub(text, 1, 300) .. "..."
	end

	return text
end

local function _clean_traceback(value)
	local text = tostring(value or "")

	if #text > 4000 then
		text = string.sub(text, 1, 4000) .. "..."
	end

	return text
end

local function _pack(...)
	return {
		n = select("#", ...),
		...,
	}
end

local function _error_payload(err)
	local message = _clean_error(err)
	local traceback = message

	if debug and type(debug.traceback) == "function" then
		local ok_traceback, result = pcall(debug.traceback, tostring(err), 2)

		if ok_traceback and result ~= nil then
			traceback = _clean_traceback(result)
		end
	end

	return {
		message = message,
		traceback = traceback,
	}
end

local function _contains_module(path_entry, module_id)
	for i = 1, #path_entry.callbacks do
		if path_entry.callbacks[i].module_id == module_id then
			return true
		end
	end

	for i = 1, #path_entry.hooks do
		if path_entry.hooks[i].module_id == module_id then
			return true
		end
	end

	return false
end

function Runtime:_query_mod_enabled()
	if type(mod.is_enabled) == "function" then
		local ok, enabled = pcall(mod.is_enabled, mod)

		if ok then
			return enabled == true
		end
	end

	return false
end

function Runtime:invalidate_setting(setting_id)
	self._settings_known[setting_id] = nil
	self._settings_cache[setting_id] = nil
end

function Runtime:invalidate_all_settings()
	self._settings_known = {}
	self._settings_cache = {}
end

function Runtime:get(setting_id)
	if self._settings_known[setting_id] then
		return self._settings_cache[setting_id]
	end

	local ok, value = pcall(mod.get, mod, setting_id)

	if not ok or value == nil then
		value = self.defaults[setting_id]
	end

	self._settings_known[setting_id] = true
	self._settings_cache[setting_id] = value

	return value
end

function Runtime:_compute_module_active(module)
	if not self._mod_enabled
		or not module.state.available
		or module.state.quarantined then
		return false
	end

	return not module.setting_id or self:get(module.setting_id) == true
end

function Runtime:_rebuild_update_modules()
	local update_modules = self._update_modules

	for i = #update_modules, 1, -1 do
		update_modules[i] = nil
	end

	for i = 1, #self.module_order do
		local module = self.modules[self.module_order[i]]

		if module.state.active and type(module.update) == "function" then
			update_modules[#update_modules + 1] = module
		end
	end
end

function Runtime:_refresh_all_module_activation()
	for i = 1, #self.module_order do
		local module = self.modules[self.module_order[i]]
		local active = self:_compute_module_active(module)

		if module.state.active ~= active then
			module.state.active = active
			module.state.update_accumulator = 0
		end
	end

	self:_rebuild_update_modules()
end

function Runtime:set_mod_enabled(enabled)
	self._mod_enabled = enabled == true

	if self._mod_enabled then
		self:invalidate_all_settings()
	end

	self:_refresh_all_module_activation()
end

function Runtime:setting_changed(setting_id)
	self:invalidate_setting(setting_id)
	self:_refresh_all_module_activation()
	self:dispatch("on_setting_changed", setting_id)
end

function Runtime:add_module(module)
	if self.modules[module.id] then
		mod:warning("Duplicate Tertium Fixes module id ignored: %s", module.id)

		return false
	end

	module.runtime = self
	module.mod = mod
	module.state = {
		active = false,
		actions = 0,
		available = true,
		consecutive_errors = 0,
		errors = 0,
		first_error = nil,
		hits = 0,
		last_error = nil,
		latest_error = nil,
		quarantined = false,
		reason = nil,
		update_accumulator = 0,
	}
	self.modules[module.id] = module
	self.module_order[#self.module_order + 1] = module.id
	module.state.active = self:_compute_module_active(module)
	self:_rebuild_update_modules()

	return true
end

function Runtime:get_module(module_id)
	return self.modules[module_id]
end

function Runtime:mod_is_enabled()
	return self._mod_enabled
end

function Runtime:set_available(module_id, available, reason)
	local module = self.modules[module_id]

	if not module then
		return
	end

	module.state.available = available and true or false
	module.state.reason = reason
	module.state.active = self:_compute_module_active(module)
	module.state.update_accumulator = 0
	self:_rebuild_update_modules()
end

function Runtime:is_active(module_id)
	local module = self.modules[module_id]

	return module ~= nil and module.state.active == true
end

function Runtime:record_hit(module_id, amount)
	local module = self.modules[module_id]

	if module then
		module.state.hits = module.state.hits + (amount or 1)
	end
end

function Runtime:record_action(module_id, amount)
	local module = self.modules[module_id]

	if module then
		module.state.actions = module.state.actions + (amount or 1)
	end
end

function Runtime:_new_error_record(module_id, err, context)
	context = type(context) == "table" and context or {}

	local payload = type(err) == "table" and err or nil
	local message = payload and payload.message or _clean_error(err)
	local traceback = payload and payload.traceback or context.traceback

	self._error_sequence = self._error_sequence + 1

	return {
		clock = tonumber(self.clock) or 0,
		file_path = context.file_path,
		message = _clean_error(message),
		method_name = context.method_name,
		module_id = module_id,
		operation_kind = context.operation_kind,
		phase = context.phase or "runtime",
		sequence = self._error_sequence,
		traceback = traceback and _clean_traceback(traceback) or nil,
	}
end

function Runtime:record_error(module_id, err, context)
	local module = self.modules[module_id]

	if not module then
		return nil
	end

	local state = module.state
	local record = self:_new_error_record(module_id, err, context)

	state.errors = state.errors + 1
	state.consecutive_errors = state.consecutive_errors + 1
	state.first_error = state.first_error or record
	state.latest_error = record
	state.last_error = record.message
	pcall(mod.error, mod, "[%s/%s] %s", module_id, record.phase, record.message)

	local threshold = tonumber(self:get("auto_quarantine_threshold")) or 3

	if self:get("auto_quarantine_enabled")
		and state.consecutive_errors >= threshold
		and not state.quarantined then
		state.quarantined = true
		state.active = false
		state.update_accumulator = 0
		state.reason = string.format(
			"auto-quarantined after %d consecutive errors (%d lifetime)",
			state.consecutive_errors,
			state.errors
		)
		self:_rebuild_update_modules()
		pcall(
			mod.echo,
			mod,
			"[Tertium Fixes] %s was auto-quarantined after %d consecutive errors (%d lifetime). Use /tf_reset %s after investigating.",
			module.label or module_id,
			state.consecutive_errors,
			state.errors,
			module_id
		)
	end

	return record
end

function Runtime:record_success(module_id)
	local module = self.modules[module_id]

	if module then
		module.state.consecutive_errors = 0
	end
end

function Runtime:_protected_call(callback, ...)
	local arguments = _pack(...)
	local function invoke()
		return callback(_unpack(arguments, 1, arguments.n))
	end
	local function on_error(err)
		return _error_payload(err)
	end
	local results = _pack(xpcall(invoke, on_error))

	if not results[1] then
		return false, results[2]
	end

	return true, _unpack(results, 2, results.n)
end

function Runtime:run_phase(module_id, phase, callback, ...)
	local ok, a, b, c, d = self:_protected_call(callback, ...)

	if not ok then
		self:record_error(module_id, a, { phase = phase })

		return false
	end

	self:record_success(module_id)

	return true, a, b, c, d
end

function Runtime:run(module_id, callback, ...)
	return self:run_phase(module_id, "callback", callback, ...)
end

function Runtime:log(module_id, message, ...)
	if self:get("diagnostic_logging") then
		mod:info("[%s] " .. message, module_id, ...)
	end
end

function Runtime:_ensure_deferred_path(file_path)
	local path_entry = self._deferred_paths[file_path]

	if not path_entry then
		path_entry = {
			callbacks = {},
			error_count = 0,
			first_error = nil,
			hooks = {},
			latest_error = nil,
			reason = nil,
			registered = false,
			registration_attempted = false,
			state = "pending",
			state_changed_at = tonumber(self.clock) or 0,
			target_states = setmetatable({}, { __mode = "k" }),
		}
		self._deferred_paths[file_path] = path_entry
		self._deferred_path_order[#self._deferred_path_order + 1] = file_path
	end

	return path_entry
end

function Runtime:_set_deferred_state(file_path, state_name, reason)
	local path_entry = self._deferred_paths[file_path]

	if not path_entry then
		return nil
	end

	path_entry.state = state_name
	path_entry.reason = reason
	path_entry.state_changed_at = tonumber(self.clock) or 0

	return path_entry
end

function Runtime:_append_deferred_error(path_entry, record)
	if not path_entry or not record then
		return
	end

	path_entry.error_count = path_entry.error_count + 1
	path_entry.first_error = path_entry.first_error or record
	path_entry.latest_error = record
end

function Runtime:_record_deferred_error(file_path, module_id, err, context)
	local path_entry = self._deferred_paths[file_path]

	if not path_entry then
		return nil
	end

	context = type(context) == "table" and context or {}
	context.file_path = file_path
	context.phase = context.phase or "deferred"

	local record = module_id and self:record_error(module_id, err, context)
		or self:_new_error_record(nil, err, context)

	self:_append_deferred_error(path_entry, record)

	return record
end

function Runtime:_mark_deferred_path_unavailable(file_path, reason, state_name, context)
	local path_entry = self:_set_deferred_state(
		file_path,
		state_name or "failed",
		_clean_error(reason)
	)

	if not path_entry then
		return
	end

	local seen = {}
	local recorded = false

	for i = 1, #path_entry.callbacks do
		local module_id = path_entry.callbacks[i].module_id

		if not seen[module_id] then
			seen[module_id] = true
			recorded = true
			self:_record_deferred_error(file_path, module_id, reason, context)
			self:set_available(module_id, false, _clean_error(reason))
		end
	end

	for i = 1, #path_entry.hooks do
		local module_id = path_entry.hooks[i].module_id

		if not seen[module_id] then
			seen[module_id] = true
			recorded = true
			self:_record_deferred_error(file_path, module_id, reason, context)
			self:set_available(module_id, false, _clean_error(reason))
		end
	end

	if not recorded then
		self:_record_deferred_error(file_path, nil, reason, context)
	end

	self:_refresh_all_module_activation()
end

function Runtime:_fail_deferred_operation(file_path, module_id, reason, context)
	self:_record_deferred_error(file_path, module_id, reason, context)
	self:set_available(module_id, false, _clean_error(reason))
end

function Runtime:_apply_deferred_path(file_path, loaded_value)
	local path_entry = self._deferred_paths[file_path]

	if not path_entry then
		return
	end

	if path_entry.state == "failed" or path_entry.state == "restart-required" then
		return false
	end

	if loaded_value == nil then
		self:_mark_deferred_path_unavailable(
			file_path,
			"game file returned no value",
			"failed",
			{ phase = "deferred-load", operation_kind = "load-result" }
		)

		return false
	end

	-- A target is terminal as soon as it has begun applying. This blocks both
	-- duplicate delivery and re-entrant replay after a partially applied patch.
	if path_entry.target_states[loaded_value] then
		return path_entry.target_states[loaded_value] == "applied"
	end

	if path_entry.state == "applying" then
		return false
	end

	self:_set_deferred_state(file_path, "applying")
	path_entry.target_states[loaded_value] = "applying"

	local clean_failure = false

	for i = 1, #path_entry.callbacks do
		local callback = path_entry.callbacks[i]
		local ok_callback, callback_error = self:_protected_call(
			callback.handler,
			loaded_value
		)

		if not ok_callback then
			local reason = "deferred game-file callback failed: "
				.. _clean_error(callback_error and callback_error.message or callback_error)

			self:_mark_deferred_path_unavailable(
				file_path,
				reason,
				"restart-required",
				{
					file_path = file_path,
					operation_kind = "callback",
					phase = "deferred-apply",
					traceback = callback_error and callback_error.traceback,
				}
			)
			path_entry.target_states[loaded_value] = "restart-required"

			return false
		end

		self:record_success(callback.module_id)
	end

	for i = 1, #path_entry.hooks do
		local hook = path_entry.hooks[i]
		local hook_function = hook.hook_kind == "safe" and mod.hook_safe or mod.hook
		local reason = nil

		if type(loaded_value) ~= "table" then
			reason = "class unavailable after game load"
		elseif type(loaded_value[hook.method_name]) ~= "function" then
			reason = "method unavailable after game load: " .. hook.method_name
		elseif type(hook_function) ~= "function" then
			reason = "DMF hook API unavailable"
		end

		if reason then
			clean_failure = true
			self:_fail_deferred_operation(
				file_path,
				hook.module_id,
				reason,
				{
					method_name = hook.method_name,
					operation_kind = "hook-preflight",
					phase = "deferred-preflight",
				}
			)
		else
			local ok_hook, hook_error = self:_protected_call(
				hook_function,
				mod,
				loaded_value,
				hook.method_name,
				hook.handler
			)

			if not ok_hook then
				local hook_reason = "hook failed after game load: "
					.. _clean_error(hook_error and hook_error.message or hook_error)

				self:_mark_deferred_path_unavailable(
					file_path,
					hook_reason,
					"restart-required",
					{
						method_name = hook.method_name,
						operation_kind = "hook-apply",
						phase = "deferred-apply",
						traceback = hook_error and hook_error.traceback,
					}
				)
				path_entry.target_states[loaded_value] = "restart-required"

				return false
			end

			self:record_success(hook.module_id)
		end
	end

	if clean_failure then
		path_entry.target_states[loaded_value] = "failed"
		self:_set_deferred_state(
			file_path,
			"failed",
			"one or more deferred operations failed compatibility preflight"
		)
	else
		path_entry.target_states[loaded_value] = "applied"
		self:_set_deferred_state(file_path, "applied")
	end

	self:_refresh_all_module_activation()

	return not clean_failure
end

function Runtime:_register_deferred_paths()
	if type(mod.hook_require) ~= "function" then
		for i = 1, #self._deferred_path_order do
			local file_path = self._deferred_path_order[i]
			local path_entry = self._deferred_paths[file_path]

			if path_entry then
				path_entry.registration_attempted = true
				path_entry.registered = false
			end

			self:_mark_deferred_path_unavailable(
				file_path,
				"DMF deferred file-hook API unavailable",
				"failed",
				{ phase = "deferred-registration", operation_kind = "hook-require" }
			)
		end

		return
	end

	for i = 1, #self._deferred_path_order do
		local file_path = self._deferred_path_order[i]
		local path_entry = self._deferred_paths[file_path]

		if path_entry and not path_entry.registration_attempted then
			-- Keep a distinct local for Lua 5.1 closure semantics.
			local registered_path = file_path

			-- hook_require may synchronously invoke the callback for a value that
			-- Darktide already loaded, so publish both facts before calling DMF.
			path_entry.registration_attempted = true
			path_entry.registered = true
			self:_set_deferred_state(registered_path, "registered")

			local ok_register, register_error = pcall(
				mod.hook_require,
				mod,
				registered_path,
				function (loaded_value)
					-- This callback executes inside DMF's wrapped require *after* the
					-- original game require. Nothing is allowed to escape it.
					local ok_barrier, barrier_error = pcall(function ()
						local ok_apply, apply_error = self:_protected_call(
							self._apply_deferred_path,
							self,
							registered_path,
							loaded_value
						)

						if not ok_apply then
							self:_mark_deferred_path_unavailable(
								registered_path,
								"deferred loader callback escaped internally: "
									.. _clean_error(apply_error and apply_error.message or apply_error),
								"restart-required",
								{
									phase = "deferred-loader-barrier",
									operation_kind = "loader-callback",
									traceback = apply_error and apply_error.traceback,
								}
							)
						end
					end)

					if not ok_barrier then
						pcall(
							self._mark_deferred_path_unavailable,
							self,
							registered_path,
							"deferred loader safety barrier failed: " .. _clean_error(barrier_error),
							"restart-required",
							{ phase = "deferred-loader-barrier", operation_kind = "safety-barrier" }
						)
						pcall(
							mod.error,
							mod,
							"[Tertium Fixes] deferred loader safety barrier failed for %s: %s",
							registered_path,
							_clean_error(barrier_error)
						)
					end
				end
			)

			if not ok_register then
				path_entry.registered = false
				pcall(
					self._mark_deferred_path_unavailable,
					self,
					registered_path,
					"deferred hook registration failed: " .. _clean_error(register_error),
					"restart-required",
					{ phase = "deferred-registration", operation_kind = "hook-require" }
				)
			end
		end
	end
end

function Runtime:defer_file(module_id, file_path, handler)
	if type(file_path) ~= "string" or file_path == ""
		or type(handler) ~= "function" then
		self:set_available(module_id, false, "invalid deferred game-file callback")

		return false
	end

	local path_entry = self:_ensure_deferred_path(file_path)

	if path_entry.registration_attempted then
		self:set_available(module_id, false, "deferred path was already registered")

		return false
	end

	path_entry.callbacks[#path_entry.callbacks + 1] = {
		handler = handler,
		module_id = module_id,
	}

	return true
end

function Runtime:install_hook(module_id, class_path, method_name, hook_kind, handler)
	if type(class_path) ~= "string" or class_path == ""
		or type(method_name) ~= "string" or method_name == ""
		or type(handler) ~= "function" then
		self:set_available(module_id, false, "invalid deferred hook specification")

		return false
	end

	local path_entry = self:_ensure_deferred_path(class_path)

	if path_entry.registration_attempted then
		self:set_available(module_id, false, "deferred path was already registered")

		return false
	end

	path_entry.hooks[#path_entry.hooks + 1] = {
		handler = handler,
		hook_kind = hook_kind,
		method_name = method_name,
		module_id = module_id,
	}

	return true
end

function Runtime:get_deferred_status(module_id)
	local priorities = {
		["applied"] = 1,
		["pending"] = 2,
		["registered"] = 3,
		["applying"] = 4,
		["failed"] = 5,
		["restart-required"] = 6,
	}
	local result = {
		counts = {},
		paths = {},
		state = "none",
	}
	local selected_priority = 0

	for i = 1, #self._deferred_path_order do
		local file_path = self._deferred_path_order[i]
		local path_entry = self._deferred_paths[file_path]

		if path_entry and _contains_module(path_entry, module_id) then
			local state_name = path_entry.state or "pending"
			local priority = priorities[state_name] or 0

			result.counts[state_name] = (result.counts[state_name] or 0) + 1
			result.paths[#result.paths + 1] = {
				file_path = file_path,
				first_error = path_entry.first_error,
				latest_error = path_entry.latest_error,
				reason = path_entry.reason,
				state = state_name,
			}

			if priority > selected_priority then
				selected_priority = priority
				result.state = state_name
			end
		end
	end

	return result
end

function Runtime:install_modules()
	for i = 1, #self.module_order do
		local module_id = self.module_order[i]
		local module = self.modules[module_id]

		if type(module.install) == "function" then
			local ok = self:run_phase(module_id, "install", module.install, module)

			if not ok then
				self:set_available(module_id, false, "installation failed")
			end
		end
	end

	-- Register one aggregated callback per game file after every module has had
	-- a chance to queue its methods. This never calls require() itself, avoiding
	-- partial-load sentinels when engine prerequisites are not initialized yet.
	self:_register_deferred_paths()

	self:_refresh_all_module_activation()
end

function Runtime:update(dt)
	dt = tonumber(dt) or 0

	if dt < 0 or dt > 5 then
		dt = 0
	end

	self.clock = self.clock + dt

	if not self._mod_enabled then
		return
	end

	for i = 1, #self._update_modules do
		local module = self._update_modules[i]

		if module and module.state.active then
			local interval = tonumber(module.update_interval) or 0

			if interval > 0 then
				local accumulated = module.state.update_accumulator + dt

				if accumulated >= interval then
					module.state.update_accumulator = accumulated % interval
					self:run_phase(module.id, "update", module.update, module, accumulated)
				else
					module.state.update_accumulator = accumulated
				end
			else
				self:run_phase(module.id, "update", module.update, module, dt)
			end
		end
	end
end

function Runtime:dispatch(event_name, ...)
	local cleanup_event = event_name == "on_disabled" or event_name == "on_unload"
	local mod_enabled = self._mod_enabled

	for i = 1, #self.module_order do
		local module_id = self.module_order[i]
		local module = self.modules[module_id]
		local callback = module[event_name]

		-- Cleanup must remain reachable even after a partial installation or
		-- quarantine. All other lifecycle work stays inert while the whole mod
		-- is disabled.
		if type(callback) == "function"
			and (
				cleanup_event
				or (mod_enabled and module.state.available and not module.state.quarantined)
			) then
			self:run_phase(module_id, event_name, callback, module, ...)
		end
	end
end

local function _status_word(runtime, module)
	local deferred = runtime:get_deferred_status(module.id)

	if not runtime:mod_is_enabled() then
		return "disabled"
	elseif deferred.state == "restart-required" then
		return "restart-required"
	elseif deferred.state == "failed" then
		return "failed"
	elseif not module.state.available then
		return "unavailable"
	elseif module.state.quarantined then
		return "quarantined"
	elseif module.setting_id and runtime:get(module.setting_id) ~= true then
		return "disabled"
	elseif deferred.state == "applying" then
		return "applying"
	elseif deferred.state == "registered" then
		return "registered"
	elseif deferred.state == "pending" then
		return "pending"
	elseif type(module.runtime_status) == "function" then
		local ok, status = pcall(module.runtime_status, module)

		if ok and type(status) == "string" then
			return status
		end
	end

	return "active"
end

function Runtime:print_status(only_module_id)
	mod:echo("[Tertium Fixes] v%s | client-side guards only", self.version)

	for i = 1, #self.module_order do
		local module_id = self.module_order[i]
		local module = self.modules[module_id]

		if not only_module_id or only_module_id == module_id then
			local state = module.state
			local detail = ""

			if type(module.describe) == "function" then
				local ok, result = pcall(module.describe, module)

				if ok and type(result) == "string" and result ~= "" then
					detail = " | " .. result
				end
			end

			if state.reason then
				detail = detail .. " | " .. state.reason
			end

			if state.first_error then
				detail = detail .. string.format(
					" | first=%s:%s",
					state.first_error.phase,
					state.first_error.message
				)
			end

			if state.latest_error and state.latest_error ~= state.first_error then
				detail = detail .. string.format(
					" | latest=%s:%s",
					state.latest_error.phase,
					state.latest_error.message
				)
			end

			mod:echo(
				"%s (%s): hits=%d actions=%d errors=%d streak=%d%s",
				module.label or module_id,
				_status_word(self, module),
				state.hits,
				state.actions,
				state.errors,
				state.consecutive_errors,
				detail
			)
		end
	end
end

function Runtime:reset(module_id)
	local reset_count = 0

	for i = 1, #self.module_order do
		local id = self.module_order[i]
		local module = self.modules[id]

		if not module_id or module_id == "" or module_id == "all" or module_id == id then
			module.state.errors = 0
			module.state.consecutive_errors = 0
			module.state.first_error = nil
			module.state.last_error = nil
			module.state.latest_error = nil
			module.state.quarantined = false

			if module.state.available then
				module.state.reason = nil
			end

			if type(module.reset) == "function" then
				self:run_phase(id, "reset", module.reset, module)
			end

			reset_count = reset_count + 1
		end
	end

	self:_refresh_all_module_activation()

	if reset_count == 0 then
		mod:echo("[Tertium Fixes] Unknown module '%s'. Use /tf_status for ids.", tostring(module_id))
	else
		mod:echo("[Tertium Fixes] Reset %d module(s).", reset_count)
	end
end

local runtime = setmetatable({
	_clock = 0,
	_error_sequence = 0,
	_mod_enabled = false,
	_settings_cache = {},
	_settings_known = {},
	_deferred_path_order = {},
	_deferred_paths = {},
	_update_modules = {},
	clock = 0,
	module_order = {},
	modules = {},
}, Runtime)

runtime._mod_enabled = runtime:_query_mod_enabled()

return runtime
