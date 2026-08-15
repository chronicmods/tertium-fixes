local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "gc_pressure",
	label = "Lua heap controller",
	setting_id = "gc_enabled",
	update_interval = 0.05,
	_active_controllers = {},
	_clock = 0,
	_conflict = nil,
	_conflict_id = nil,
	_conflict_timer = 0,
	_current_state = nil,
	_dual_controller_warned = false,
	_heap_capacity_mb = 1024,
	_capacity_source = "fallback",
	_last_heap_mb = nil,
	_last_percent = nil,
	_sample_timer = 0,
	_growth_samples = {},
	_high_dwell = 0,
	_pressure = false,
	_pressure_seconds = 0,
	_pressure_last_sample_mb = nil,
	_pressure_no_drop_seconds = 0,
	_tuning_owned = false,
	_original_pause = nil,
	_original_stepmul = nil,
	_tuning_level = 0,
	_cleaned_90 = false,
	_cleaned_95 = false,
	_warned_85 = false,
	_warned_post_clean = false,
	_post_clean_warning_timer = nil,
	_periodic_timer = 0,
	_manual_ready_at = 0,
	_scheduled = {},
	_hud_user_visible = nil,
	_force_meter = false,
	_persist_timer = 0,
	_previous_unclean_reported = false,
	_metrics = {
		full_collections = 0,
		incremental_steps = 0,
		rapid_growth_collections = 0,
		transition_collections = 0,
		manual_collections = 0,
		reclaimed_mb = 0,
	},
	_meter = {
		visible = false,
		x = 5,
		y = 65,
		percent = 0,
		heap_mb = 0,
		capacity_mb = 1024,
		severity = "normal",
		label = "Lua heap: not sampled",
	},
}

local SAMPLE_SECONDS = 1
local GROWTH_WINDOW_SECONDS = 30
local PRESSURE_PERCENT = 80
local PRESSURE_DWELL_SECONDS = 5
local WARNING_PERCENT = 85
local CRITICAL_PERCENT = 90
local EMERGENCY_PERCENT = 95
local PRESSURE_CLEAR_PERCENT = 80
local STEP_EFFORT_KB = 32
local MAX_STEPS_PER_UPDATE = 16
local STEP_BUDGET_MS = 1
local ESCALATE_SECONDS = 30
local MANUAL_COOLDOWN_SECONDS = 3
local PERIODIC_SECONDS = 10 * 60
local HUB_DELAY_SECONDS = 30
local TRANSITION_DELAY_SECONDS = 1

local function _name_from_bytes(bytes)
	local characters = {}

	for index = 1, #bytes do
		characters[index] = string.char(bytes[index])
	end

	return table.concat(characters)
end

local CONTROLLER_GROUPS = {
	{
		key = "cleanup_owner_primary",
		label = "another Lua cleanup controller",
		names = {
			_name_from_bytes({ 83, 77, 79, 71 }),
		},
	},
	{
		key = "cleanup_owner_secondary",
		label = "another Lua cleanup controller",
		names = {
			_name_from_bytes({ 77, 101, 109, 76, 101, 97, 107, 70, 105, 120 }),
		},
	},
	{
		key = "cleanup_owner_legacy",
		label = "another Lua cleanup controller",
		names = {
			_name_from_bytes({ 70, 112, 115, 68, 111, 99, 116, 111, 114 }),
		},
	},
}

local function _clamp(value, low, high)
	value = tonumber(value)

	if not value then
		return low
	elseif value < low then
		return low
	elseif value > high then
		return high
	end

	return value
end

local function _mod_is_active(candidate)
	if type(candidate) ~= "table" then
		return false
	end

	if type(candidate.is_enabled) == "function" then
		local ok, enabled = pcall(candidate.is_enabled, candidate)

		if ok then
			return enabled == true
		end
	end

	return true
end

local function _safe_method(owner, method_name)
	if type(owner) ~= "table" or type(owner[method_name]) ~= "function" then
		return nil
	end

	local ok, value = pcall(owner[method_name], owner)

	if ok then
		return value
	end

	return nil
end

function module:_collector_call(operation, argument)
	if type(collectgarbage) ~= "function" then
		return false, "collectgarbage() unavailable"
	end

	local ok, value

	if argument == nil then
		ok, value = pcall(collectgarbage, operation)
	else
		ok, value = pcall(collectgarbage, operation, argument)
	end

	if not ok then
		runtime:log(self.id, "collectgarbage(%s) failed: %s", tostring(operation), tostring(value))

		return false, value
	end

	return true, value
end

function module:_detect_heap_capacity()
	local fallback = _clamp(runtime:get("gc_capacity_fallback_mb") or 1024, 128, 65536)
	local detected = nil

	if type(Application) == "table" and type(Application.argv) == "function" then
		local ok, arguments = pcall(function ()
			return {
				Application.argv(),
			}
		end)

		if ok and type(arguments) == "table" then
			for i = 1, #arguments do
				local argument = tostring(arguments[i] or "")
				local inline = string.match(argument, "^%-+lua%-heap%-mb%-size=(%d+)$")

				if inline then
					detected = tonumber(inline)
					break
				elseif (argument == "--lua-heap-mb-size" or argument == "-lua-heap-mb-size")
					and arguments[i + 1] ~= nil then
					detected = tonumber(arguments[i + 1])
					break
				end
			end
		end
	end

	if detected and detected >= 128 and detected <= 65536 then
		self._heap_capacity_mb = detected
		self._capacity_source = "command line"
	else
		self._heap_capacity_mb = fallback
		self._capacity_source = "fallback setting"
	end

	self._meter.capacity_mb = self._heap_capacity_mb

	if self._last_heap_mb then
		self._last_percent = self._heap_capacity_mb > 0 and self._last_heap_mb / self._heap_capacity_mb * 100 or 0
	end

	return self._heap_capacity_mb
end

function module:_drop_tuning_ownership()
	-- Cleanup ownership may change at runtime. Do not make a restoration call
	-- that could overwrite tuning now owned elsewhere.
	self._tuning_owned = false
	self._original_pause = nil
	self._original_stepmul = nil
	self._tuning_level = 0
end

function module:_restore_tuning(reason)
	if not self._tuning_owned then
		return true
	end

	-- Ownership can change between the sample/update that requested restoration
	-- and the restoration itself. Re-scan at the last safe point before making
	-- any collector call. A newly claimed owner deliberately drops our saved
	-- values through _scan_conflicts() and receives zero collector calls here.
	self:_scan_conflicts()

	if self._conflict then
		return false
	end

	local restored = true

	if type(self._original_pause) == "number" then
		local pause_ok = self:_collector_call("setpause", self._original_pause)

		if pause_ok then
			self._original_pause = nil
		else
			restored = false
		end
	end

	if type(self._original_stepmul) == "number" then
		local stepmul_ok = self:_collector_call("setstepmul", self._original_stepmul)

		if stepmul_ok then
			self._original_stepmul = nil
		else
			restored = false
		end
	end

	self._tuning_owned = type(self._original_pause) == "number"
		or type(self._original_stepmul) == "number"

	if not self._tuning_owned then
		self._tuning_level = 0
		runtime:log(self.id, "Restored prior Lua collector tuning (%s).", tostring(reason or "pressure cleared"))

		return true
	end

	runtime:log(self.id, "Lua collector tuning restoration remains pending (%s).", tostring(reason or "pressure cleared"))

	return restored and not self._tuning_owned
end

function module:_clear_pressure_state(preserve_meter_pressure)
	self._high_dwell = 0
	self._pressure = false
	self._pressure_seconds = 0
	self._pressure_last_sample_mb = nil
	self._pressure_no_drop_seconds = 0
	self._cleaned_90 = false
	self._cleaned_95 = false
	self._warned_post_clean = false
	self._post_clean_warning_timer = nil

	if preserve_meter_pressure ~= true then
		self._warned_85 = false
		self._force_meter = false
	end
end

function module:_clear_pressure(reason, may_restore, preserve_meter_pressure)
	if may_restore ~= false then
		self:_restore_tuning(reason)
	else
		self:_drop_tuning_ownership()
	end

	-- Keep collector ownership separate from the pressure-state reset. A failed
	-- restoration must retain its remaining original value so a later lifecycle
	-- call can retry it exactly.
	self:_clear_pressure_state(preserve_meter_pressure)
end

function module:_cancel_scheduled()
	for reason in pairs(self._scheduled) do
		self._scheduled[reason] = nil
	end
end

function module:_stand_down(may_restore)
	self:_clear_pressure("controller stand-down", may_restore)
	self._last_heap_mb = nil
	self._last_percent = nil
	self._sample_timer = 0
	self._growth_samples = {}
	self:_cancel_scheduled()
	self._meter.percent = 0
	self._meter.heap_mb = 0
	self._meter.severity = "normal"
	self._meter.label = "Lua heap: not sampled"
end

function module:_scan_conflicts()
	local previous_conflict = self._conflict

	self._conflict = nil
	self._conflict_id = nil

	for group_index = 1, #CONTROLLER_GROUPS do
		self._active_controllers[CONTROLLER_GROUPS[group_index].key] = nil
	end

	if type(get_mod) == "function" then
		for group_index = 1, #CONTROLLER_GROUPS do
			local group = CONTROLLER_GROUPS[group_index]

			for name_index = 1, #group.names do
				local name = group.names[name_index]
				local ok, candidate = pcall(get_mod, name)

				if ok and _mod_is_active(candidate) then
					-- Retain only the generic ownership slot after lookup so the
					-- resolved identifier cannot flow into reporting paths.
					self._active_controllers[group.key] = true
					self._conflict = self._conflict or group.label
					self._conflict_id = self._conflict_id or group.key

					break
				end
			end
		end
	end

	if self._conflict and (not previous_conflict or self._tuning_owned) then
		-- Zero collector calls are permitted after ownership changes. Discard our
		-- saved tuning rather than risking an overwrite of the new controller.
		self:_stand_down(false)
	elseif not self._conflict and previous_conflict then
		-- Ownership is normally already empty after a real controller hand-off.
		-- Restoring here also recovers safely from stale lifecycle state where our
		-- originals survived but the previously recorded controller did not.
		self:_stand_down(self._tuning_owned)
	end

	local active_count = 0

	for _, controller_name in pairs(self._active_controllers) do
		if controller_name then
			active_count = active_count + 1
		end
	end

	if active_count > 1 and not self._dual_controller_warned then
		self._dual_controller_warned = true
		mod:warning("[gc_pressure] Multiple Lua cleanup controllers are active. Enable only one automatic cleanup controller.")
		mod:echo("[Tertium Fixes] Multiple Lua cleanup controllers were detected. Enable only one automatic cleanup controller.")
	end

	if previous_conflict ~= self._conflict then
		if self._conflict then
			runtime:log(self.id, "Automatic cleanup is on standby because cleanup is owned elsewhere.")
		elseif previous_conflict then
			runtime:log(self.id, "Cleanup ownership is available; monitoring will restart from a fresh sample.")
		end

		-- Conflict transitions are rare and materially change the HUD text. Refresh
		-- here rather than rebuilding an unchanged label on every 20 Hz update.
		self:_refresh_meter()
	end

	return self._conflict == nil
end

function module:_guard_mutation()
	if runtime:get("gc_cleaning_permitted") ~= true then
		return false, "cleaning disabled"
	end

	self:_scan_conflicts()

	if self._conflict then
		return false, "conflict"
	end

	return true, nil
end

function module:_set_tuning(level)
	local allowed = self:_guard_mutation()

	if not allowed then
		return false
	end

	local pause = level >= 2 and 70 or 80
	local stepmul = level >= 2 and 650 or 500

	if not self._tuning_owned then
		local pause_ok, old_pause = self:_collector_call("setpause", pause)

		if not pause_ok then
			return false
		end

		-- Record restoration ownership immediately after the first successful
		-- mutation. If the second setter fails, _restore_tuning() keeps and
		-- retries any value that could not be restored.
		self._original_pause = type(old_pause) == "number" and old_pause or nil
		self._original_stepmul = nil
		self._tuning_owned = self._original_pause ~= nil
		self._tuning_level = level

		local step_ok, old_stepmul = self:_collector_call("setstepmul", stepmul)

		if not step_ok then
			self:_restore_tuning("initial tuning failure")

			return false
		end

		self._original_stepmul = type(old_stepmul) == "number" and old_stepmul or nil
		self._tuning_owned = self._original_pause ~= nil or self._original_stepmul ~= nil
		self._tuning_level = level
	elseif level > self._tuning_level then
		local pause_ok = self:_collector_call("setpause", pause)
		local step_ok = self:_collector_call("setstepmul", stepmul)

		if not pause_ok or not step_ok then
			self:_restore_tuning("retune failure")

			return false
		end

		self._tuning_level = level
	end

	return true
end

function module:_performance_timer_start()
	if type(Application) == "table" and type(Application.query_performance_counter) == "function" then
		local ok, handle = pcall(Application.query_performance_counter)

		if ok and handle ~= nil then
			return "application", handle
		end
	end

	if type(os) == "table" and type(os.clock) == "function" then
		return "clock", os.clock()
	end

	return nil, nil
end

function module:_performance_timer_ms(kind, handle)
	if kind == "application"
		and type(Application) == "table"
		and type(Application.time_since_query) == "function" then
		local ok, elapsed = pcall(Application.time_since_query, handle)

		if ok and type(elapsed) == "number" then
			return elapsed
		end
	elseif kind == "clock" and type(os) == "table" and type(os.clock) == "function" then
		return (os.clock() - handle) * 1000
	end

	return nil
end

function module:_run_incremental_budget()
	local allowed, reason = self:_guard_mutation()

	if not allowed then
		return false, reason
	end

	local timer_kind, timer_handle = self:_performance_timer_start()
	local steps = 0

	for _ = 1, MAX_STEPS_PER_UPDATE do
		local ok, cycle_finished = self:_collector_call("step", STEP_EFFORT_KB)

		if not ok then
			self:_restore_tuning("incremental step failure")

			return false, "error"
		end

		steps = steps + 1

		if cycle_finished == true then
			break
		end

		local elapsed_ms = self:_performance_timer_ms(timer_kind, timer_handle)

		if elapsed_ms and elapsed_ms >= STEP_BUDGET_MS then
			break
		end
	end

	if steps > 0 then
		self._metrics.incremental_steps = self._metrics.incremental_steps + steps
		runtime:record_hit(self.id)
		runtime:record_action(self.id)
	end

	return steps > 0, nil
end

function module:_notify(message, important)
	if runtime:get("gc_notifications_enabled") ~= true then
		return
	end

	if important then
		mod:warning("[gc_pressure] %s", tostring(message))
	end

	if type(mod.notify) == "function" then
		local ok = pcall(mod.notify, mod, message)

		if ok then
			return
		end
	end

	mod:echo("[Tertium Fixes] %s", tostring(message))
end

function module:_full_collect(reason, source, silent)
	local allowed, blocked_reason = self:_guard_mutation()

	if not allowed then
		return false, blocked_reason
	end

	local before_ok, before_kb = self:_collector_call("count")

	if not before_ok or type(before_kb) ~= "number" then
		return false, "count failed"
	end

	local collect_ok = self:_collector_call("collect")

	if not collect_ok then
		return false, "collection failed"
	end

	local after_ok, after_kb = self:_collector_call("count")
	local before_mb = before_kb / 1024
	local after_mb = after_ok and type(after_kb) == "number" and after_kb / 1024 or before_mb
	local reclaimed_mb = math.max(0, before_mb - after_mb)

	self._last_heap_mb = after_mb
	self._last_percent = self._heap_capacity_mb > 0 and after_mb / self._heap_capacity_mb * 100 or 0
	self._metrics.full_collections = self._metrics.full_collections + 1
	self._metrics.reclaimed_mb = self._metrics.reclaimed_mb + reclaimed_mb

	if source == "manual" then
		self._metrics.manual_collections = self._metrics.manual_collections + 1
	elseif source == "transition" then
		self._metrics.transition_collections = self._metrics.transition_collections + 1
	elseif source == "growth" then
		self._metrics.rapid_growth_collections = self._metrics.rapid_growth_collections + 1
	end

	runtime:record_hit(self.id)
	runtime:record_action(self.id)
	runtime:log(
		self.id,
		"Full Lua collection (%s): %.1f MB -> %.1f MB (%.1f MB reclaimed).",
		tostring(reason),
		before_mb,
		after_mb,
		reclaimed_mb
	)

	if not silent then
		mod:echo(
			"[Tertium Fixes] Lua heap cleaned: %.1f MB -> %.1f MB (%.1f MB reclaimed; %s).",
			before_mb,
			after_mb,
			reclaimed_mb,
			tostring(reason)
		)
	end

	self._growth_samples = {
		{
			t = self._clock,
			percent = self._last_percent,
		},
	}
	self:_refresh_meter()

	return true, {
		before_mb = before_mb,
		after_mb = after_mb,
		reclaimed_mb = reclaimed_mb,
	}
end

function module:_queue_collect(reason, delay, source)
	if runtime:get("gc_convenient_cleanup_enabled") ~= true then
		return
	end

	local existing = self._scheduled[reason]
	local due = self._clock + math.max(0, tonumber(delay) or 0)

	if not existing or due < existing.due then
		self._scheduled[reason] = {
			due = due,
			source = source or "transition",
		}
	end
end

function module:_classify_activity()
	local managers = rawget(_G, "Managers")

	if type(managers) ~= "table" then
		return "gameplay"
	end

	local data_service = managers.data_service
	local social = type(data_service) == "table" and data_service.social or nil

	if _safe_method(social, "is_in_hub") == true then
		return "hub"
	elseif _safe_method(social, "is_in_training_grounds") == true then
		return "training"
	end

	local state = managers.state
	local game_mode = type(state) == "table" and state.game_mode or nil

	if _safe_method(game_mode, "is_social_hub") == true or _safe_method(game_mode, "is_prologue_hub") == true then
		return "hub"
	end

	local mechanism = managers.mechanism
	local mechanism_name = _safe_method(mechanism, "mechanism_name")

	if mechanism_name == "expedition" then
		return "expedition"
	end

	local game_mode_name = _safe_method(game_mode, "game_mode_name")

	if type(game_mode_name) == "string" then
		local lowered = string.lower(game_mode_name)

		if string.find(lowered, "training", 1, true) then
			return "training"
		elseif string.find(lowered, "survival", 1, true) then
			return "survival"
		end
	end

	return "gameplay"
end

function module:_process_scheduled()
	-- A transition cleanup may already have been queued when the option is
	-- switched off. Re-check at execution time so disabling the option is an
	-- immediate cancellation boundary, not merely a gate on future queues.
	if runtime:get("gc_convenient_cleanup_enabled") ~= true then
		self:_cancel_scheduled()

		return
	end

	for reason, entry in pairs(self._scheduled) do
		if entry.due <= self._clock then
			self._scheduled[reason] = nil

			if reason == "classify-entry" then
				local activity = self:_classify_activity()

				if activity == "hub" then
					self:_queue_collect("hub-settled", HUB_DELAY_SECONDS, "transition")
				else
					self:_full_collect(activity .. " entry", "transition", true)
				end
			else
				self:_full_collect(reason, entry.source, true)
			end
		end
	end
end

function module:_push_growth_sample(percent)
	local samples = self._growth_samples

	samples[#samples + 1] = {
		t = self._clock,
		percent = percent,
	}

	while #samples > 1 and samples[2].t <= self._clock - GROWTH_WINDOW_SECONDS do
		table.remove(samples, 1)
	end

	local oldest = samples[1]

	if oldest
		and self._clock - oldest.t >= GROWTH_WINDOW_SECONDS
		and percent >= 30
		and percent - oldest.percent >= 15 then
		local cleaned = self:_full_collect("rapid 30-second heap growth", "growth", true)

		if cleaned then
			self:_notify("Lua heap grew by at least 15 percentage points in 30 seconds; a full cleanup was completed.", false)

			return true
		end
	end

	return false
end

function module:_severity(percent)
	if percent >= EMERGENCY_PERCENT then
		return "emergency"
	elseif percent >= CRITICAL_PERCENT then
		return "critical"
	elseif percent >= WARNING_PERCENT then
		return "warning"
	elseif percent >= PRESSURE_PERCENT then
		return "pressure"
	elseif percent >= 65 then
		return "watch"
	end

	return "normal"
end

function module:_refresh_meter()
	local percent = tonumber(self._last_percent) or 0
	local configured_visible = runtime:get("gc_hud_enabled") == true

	if self._hud_user_visible == nil then
		self._hud_user_visible = configured_visible
	end

	self._meter.visible = self._hud_user_visible or self._force_meter
	self._meter.x = _clamp(runtime:get("gc_hud_x_percent") or 5, 0, 100)
	self._meter.y = _clamp(runtime:get("gc_hud_y_percent") or 65, 0, 100)
	self._meter.percent = percent
	self._meter.heap_mb = tonumber(self._last_heap_mb) or 0
	self._meter.capacity_mb = self._heap_capacity_mb
	self._meter.severity = self:_severity(percent)

	if self._last_heap_mb then
		self._meter.label = string.format(
			"Lua heap %.1f / %.0f MB (%.1f%%)",
			self._last_heap_mb,
			self._heap_capacity_mb,
			percent
		)
	elseif self._conflict then
		self._meter.label = "Lua heap cleanup is on standby"
	else
		self._meter.label = "Lua heap: not sampled"
	end
end

function module:_sample_heap()
	-- Re-check before count as well as mutations. This preserves strict zero-call
	-- stand-down whenever this module does not own cleanup.
	self:_scan_conflicts()

	if self._conflict then
		return false, "conflict"
	end

	local ok, heap_kb = self:_collector_call("count")

	if not ok or type(heap_kb) ~= "number" then
		return false, "error"
	end

	self._last_heap_mb = heap_kb / 1024
	self._last_percent = self._heap_capacity_mb > 0 and self._last_heap_mb / self._heap_capacity_mb * 100 or 0

	local percent = self._last_percent

	local growth_cleaned = self:_push_growth_sample(percent)

	if growth_cleaned then
		percent = tonumber(self._last_percent) or percent
	end

	if percent < PRESSURE_CLEAR_PERCENT then
		if self._pressure or self._tuning_owned then
			runtime:log(self.id, "Lua heap pressure cleared at %.1f%% (%.1f MB).", percent, self._last_heap_mb)
		end

		self:_clear_pressure("heap below 80 percent", true)
	else
		self._high_dwell = self._high_dwell + SAMPLE_SECONDS

		if self._high_dwell >= PRESSURE_DWELL_SECONDS then
			if not self._pressure then
				self._pressure = true
				self._pressure_seconds = 0
				self._pressure_no_drop_seconds = 0
				self._pressure_last_sample_mb = self._last_heap_mb
				runtime:log(self.id, "Sustained Lua heap pressure entered at %.1f%% (%.1f MB).", percent, self._last_heap_mb)
			else
				if self._pressure_last_sample_mb
					and self._last_heap_mb < self._pressure_last_sample_mb - 0.1 then
					self._pressure_no_drop_seconds = 0
				else
					self._pressure_no_drop_seconds = self._pressure_no_drop_seconds + SAMPLE_SECONDS
				end

				self._pressure_last_sample_mb = self._last_heap_mb
			end
		end

		if percent >= WARNING_PERCENT and not self._warned_85 then
			self._warned_85 = true
			self._force_meter = true

			if runtime:get("gc_cleaning_permitted") == true then
				self:_notify("Lua heap is above 85% of its configured capacity. The heap meter will remain visible until pressure clears.", true)
			end
		end

		if runtime:get("gc_cleaning_permitted") == true then
			if percent >= EMERGENCY_PERCENT and not self._cleaned_95 then
				local was_90_cleaned = self._cleaned_90
				local cleaned = self:_full_collect("95% emergency threshold", "emergency", true)

				if cleaned then
					self._cleaned_95 = true
					self._cleaned_90 = true
					self._post_clean_warning_timer = 2
					percent = tonumber(self._last_percent) or percent
					self:_notify(
						was_90_cleaned and "Lua heap reached 95%; the second emergency cleanup was completed."
							or "Lua heap reached 95%; an emergency cleanup was completed.",
						true
					)
				end
			elseif percent >= CRITICAL_PERCENT and not self._cleaned_90 then
				local cleaned = self:_full_collect("90% critical threshold", "emergency", true)

				if cleaned then
					self._cleaned_90 = true
					self._post_clean_warning_timer = 2
					percent = tonumber(self._last_percent) or percent
					self:_notify("Lua heap reached 90%; one emergency cleanup was completed.", true)
				end
			end
		end

		if percent < PRESSURE_CLEAR_PERCENT then
			self:_clear_pressure("heap below 80 percent after cleanup", true)
		end
	end

	self:_refresh_meter()

	return true, nil
end

function module:_update_post_clean_warning(dt)
	if not self._post_clean_warning_timer then
		return
	end

	self._post_clean_warning_timer = self._post_clean_warning_timer - dt

	if self._post_clean_warning_timer <= 0 then
		self._post_clean_warning_timer = nil

		if not self._warned_post_clean and (tonumber(self._last_percent) or 0) >= PRESSURE_PERCENT then
			self._warned_post_clean = true
			self:_notify("Lua heap remains above 80% after emergency cleanup. Memory is still retained by live client state.", true)
		end
	end
end

function module:_flush_shutdown_marker()
	if type(get_mod) ~= "function" then
		return false
	end

	local dmf_ok, dmf = pcall(get_mod, "DMF")

	if not dmf_ok
		or type(dmf) ~= "table"
		or type(dmf.save_unsaved_settings_to_file) ~= "function" then
		return false
	end

	-- DMF exposes this as a dot function. Keeping it inside pcall also makes the
	-- diagnostic best-effort on older framework versions.
	local save_ok, save_error = pcall(dmf.save_unsaved_settings_to_file)

	if not save_ok then
		runtime:log(self.id, "Could not flush Lua heap shutdown diagnostic: %s", tostring(save_error))
	end

	return save_ok
end

function module:_write_shutdown_marker(clean, force)
	if (force ~= true and runtime:get("gc_shutdown_diagnostic_enabled") ~= true)
		or type(mod.set) ~= "function" then
		return
	end

	local desired_clean = clean == true
	local changed = false
	local clean_ok, current_clean = false, nil

	if type(mod.get) == "function" then
		clean_ok, current_clean = pcall(mod.get, mod, "tf_gc_previous_shutdown_clean")
	end

	if not clean_ok or current_clean ~= desired_clean then
		local set_ok = pcall(mod.set, mod, "tf_gc_previous_shutdown_clean", desired_clean)

		changed = changed or set_ok
	end

	if not desired_clean then
		local percent = tonumber(self._last_percent) or 0
		local band = percent >= 90 and "critical" or percent >= 80 and "high" or "normal"
		local band_ok, current_band = false, nil

		if type(mod.get) == "function" then
			band_ok, current_band = pcall(mod.get, mod, "tf_gc_last_heap_band")
		end

		if not band_ok or current_band ~= band then
			local set_ok = pcall(mod.set, mod, "tf_gc_last_heap_band", band)

			changed = changed or set_ok
		end
	end

	-- Persist only meaningful state transitions: the initial unclean marker, a
	-- broad heap-band change, or a clean shutdown. The 30-second heartbeat below
	-- therefore performs no disk write while the marker is unchanged.
	if changed then
		self:_flush_shutdown_marker()
	end
end

function module:_read_shutdown_marker()
	if runtime:get("gc_shutdown_diagnostic_enabled") ~= true
		or self._previous_unclean_reported
		or type(mod.get) ~= "function" then
		return
	end

	self._previous_unclean_reported = true

	local clean_ok, clean = pcall(mod.get, mod, "tf_gc_previous_shutdown_clean")
	local band_ok, band = pcall(mod.get, mod, "tf_gc_last_heap_band")

	if clean_ok and clean == false and band_ok and (band == "high" or band == "critical") then
		mod:warning(
			"[gc_pressure] The previous session did not record a clean unload and its last saved Lua heap band was %s. This is diagnostic context, not proof that memory caused the exit.",
			tostring(band)
		)
	end
end

function module:install()
	if type(collectgarbage) ~= "function" then
		runtime:set_available(self.id, false, "collectgarbage() unavailable")

		return
	end

	self:_detect_heap_capacity()
	self:_read_shutdown_marker()

	if runtime:mod_is_enabled() then
		self:_scan_conflicts()
		self:_write_shutdown_marker(false)
	end
end

function module:update(dt)
	self._clock = self._clock + dt
	self._conflict_timer = self._conflict_timer + dt

	if self._conflict_timer >= 1 then
		self._conflict_timer = 0
		self:_scan_conflicts()
	end

	if self._conflict then
		return
	end

	self._sample_timer = self._sample_timer + dt
	self._periodic_timer = self._periodic_timer + dt
	self._persist_timer = self._persist_timer + dt
	local sampled = false

	if self._sample_timer >= SAMPLE_SECONDS then
		self._sample_timer = self._sample_timer % SAMPLE_SECONDS

		if not self:_sample_heap() then
			return
		end

		sampled = true
	end

	-- The marker is diagnostic-only and remains useful in monitor-only mode, so
	-- persist it before the collector-permission early return below.
	if self._persist_timer >= 30 then
		self._persist_timer = 0
		self:_write_shutdown_marker(false)
	end

	if runtime:get("gc_cleaning_permitted") ~= true then
		self._periodic_timer = 0
		self:_cancel_scheduled()

		-- Monitoring remains useful, but it must not retain dwell/tuning state
		-- that could cause an immediate mutation if cleaning is enabled later.
		-- Retry a failed exact restoration only at the one-second sample cadence.
		if sampled then
			if self._tuning_owned then
				self:_restore_tuning("monitor-only restoration retry")
			end

			self:_clear_pressure_state((tonumber(self._last_percent) or 0) >= PRESSURE_CLEAR_PERCENT)
		end

		return
	end

	if self._pressure then
		self._pressure_seconds = self._pressure_seconds + dt

		if self._pressure_no_drop_seconds >= ESCALATE_SECONDS then
			self:_set_tuning(2)
		else
			self:_set_tuning(1)
		end

		self:_run_incremental_budget()
	end

	self:_update_post_clean_warning(dt)
	self:_process_scheduled()

	if runtime:get("gc_periodic_cleanup_enabled") == true and self._periodic_timer >= PERIODIC_SECONDS then
		self._periodic_timer = self._periodic_timer % PERIODIC_SECONDS
		self:_full_collect("10-minute periodic cleanup", "periodic", true)
	elseif runtime:get("gc_periodic_cleanup_enabled") ~= true then
		self._periodic_timer = 0
	end
end

function module:on_all_mods_loaded()
	self:_scan_conflicts()
end

function module:on_game_state_changed(status, state_name)
	if status == "enter" then
		self._current_state = state_name

		if state_name == "StateIngame" then
			self:_queue_collect("classify-entry", TRANSITION_DELAY_SECONDS, "transition")
		end
	elseif status == "exit" and self._current_state == state_name then
		self._current_state = nil

		if state_name == "StateIngame" then
			self:_queue_collect("gameplay exit", TRANSITION_DELAY_SECONDS, "transition")
		end
	end
end

function module:on_setting_changed(setting_id)
	if setting_id == "gc_enabled" then
		if runtime:get("gc_enabled") == true then
			self:on_enabled()
		else
			self:on_disabled()
		end

		return
	elseif setting_id == "gc_capacity_fallback_mb" then
		self:_detect_heap_capacity()
	elseif setting_id == "gc_hud_enabled" then
		self._hud_user_visible = runtime:get("gc_hud_enabled") == true
	elseif setting_id == "gc_cleaning_permitted" and runtime:get("gc_cleaning_permitted") ~= true then
		-- Re-scan immediately because cleanup ownership can change between update
		-- ticks and must receive strict zero-call stand-down treatment.
		self:_scan_conflicts()
		self:_clear_pressure(
			"cleaning disabled",
			not self._conflict,
			(tonumber(self._last_percent) or 0) >= PRESSURE_CLEAR_PERCENT
		)
		self:_cancel_scheduled()
		self._periodic_timer = 0
	elseif setting_id == "gc_convenient_cleanup_enabled"
		and runtime:get("gc_convenient_cleanup_enabled") ~= true then
		self:_cancel_scheduled()
	elseif setting_id == "gc_periodic_cleanup_enabled"
		and runtime:get("gc_periodic_cleanup_enabled") ~= true then
		self._periodic_timer = 0
	elseif setting_id == "gc_shutdown_diagnostic_enabled" then
		if runtime:get("gc_shutdown_diagnostic_enabled") == true then
			self:_read_shutdown_marker()
			self:_write_shutdown_marker(false)
		else
			-- Clear any stale abnormal-exit marker even though the setting has
			-- already changed to false.
			self:_write_shutdown_marker(true, true)
		end
	end

	self:_refresh_meter()
end

function module:on_enabled()
	self._hud_user_visible = runtime:get("gc_hud_enabled") == true
	self._conflict_timer = 0
	self._clock = 0
	self._periodic_timer = 0
	self._persist_timer = 0
	self._manual_ready_at = 0
	self:_stand_down(true)
	self:_detect_heap_capacity()
	self:_scan_conflicts()
	self:_read_shutdown_marker()
	self:_write_shutdown_marker(false)
	self:_refresh_meter()
end

function module:on_disabled()
	-- Re-scan before restoring because cleanup ownership can change between
	-- update ticks and strict zero-call stand-down takes precedence.
	self:_scan_conflicts()

	-- Restore only while this module still owns the collector.
	if not self._conflict then
		self:_restore_tuning("module disabled")
	else
		self:_drop_tuning_ownership()
	end

	self:_write_shutdown_marker(true)
	self._conflict = nil
	self._conflict_id = nil
	self._conflict_timer = 0
	self._current_state = nil
	self._dual_controller_warned = false
	self:_cancel_scheduled()
	self._last_heap_mb = nil
	self._last_percent = nil
	self._sample_timer = 0
	self._periodic_timer = 0
	self._persist_timer = 0
	self._manual_ready_at = 0
	self._growth_samples = {}
	self:_clear_pressure_state(false)
	self._meter.visible = false
	self._meter.percent = 0
	self._meter.heap_mb = 0
	self._meter.severity = "normal"
	self._meter.label = "Lua heap: not sampled"

	for group_index = 1, #CONTROLLER_GROUPS do
		self._active_controllers[CONTROLLER_GROUPS[group_index].key] = nil
	end
end

function module:on_unload()
	self:on_disabled()
end

function module:manual_step()
	if not runtime:is_active(self.id) then
		mod:echo("[Tertium Fixes] Lua heap controller is disabled, unavailable, or quarantined.")

		return false
	end

	local stepped, reason = self:_run_incremental_budget()

	if stepped then
		mod:echo("[Tertium Fixes] Completed a bounded incremental Lua GC slice.")
	elseif reason == "conflict" then
		mod:echo("[Tertium Fixes] GC step blocked because this feature does not own Lua cleanup.")
	else
		mod:echo("[Tertium Fixes] GC step blocked: %s.", tostring(reason or "collector unavailable"))
	end

	return stepped
end

function module:manual_collect()
	if not runtime:is_active(self.id) then
		mod:echo("[Tertium Fixes] Lua heap controller is disabled, unavailable, or quarantined.")

		return false
	elseif self._clock < self._manual_ready_at then
		mod:echo("[Tertium Fixes] Manual Lua cleanup is cooling down for %.1f more seconds.", self._manual_ready_at - self._clock)

		return false
	end

	local cleaned, result = self:_full_collect("manual request", "manual", false)

	if cleaned then
		self._manual_ready_at = self._clock + MANUAL_COOLDOWN_SECONDS
		self:_refresh_meter()

		return true, result
	elseif result == "conflict" then
		mod:echo("[Tertium Fixes] Manual cleanup blocked because this feature does not own Lua cleanup.")
	else
		mod:echo("[Tertium Fixes] Manual cleanup blocked: %s.", tostring(result))
	end

	return false, result
end

function module:toggle_hud()
	local currently_visible = self._hud_user_visible

	if currently_visible == nil then
		currently_visible = runtime:get("gc_hud_enabled") == true
	end

	self._hud_user_visible = not currently_visible
	self:_refresh_meter()
	mod:echo("[Tertium Fixes] Lua heap meter %s.", self._hud_user_visible and "shown" or "hidden")

	return self._hud_user_visible
end

function module:meter_snapshot()
	return self._meter
end

function module:reset()
	-- Validate collector ownership before any restoration call. Ownership can
	-- change between the last update and this reset.
	self:_scan_conflicts()

	if not self._conflict then
		self:_restore_tuning("module reset")
	else
		self:_drop_tuning_ownership()
	end

	self:_clear_pressure_state(false)
	self._last_heap_mb = nil
	self._last_percent = nil
	self._sample_timer = 0
	self._growth_samples = {}
	self:_cancel_scheduled()
	self._conflict_timer = 0
	self._periodic_timer = 0
	self._persist_timer = 0
	self._manual_ready_at = 0
	self:_detect_heap_capacity()
	self:_scan_conflicts()
	self:_refresh_meter()
end

function module:runtime_status()
	if self._conflict then
		return "cleanup-standby"
	elseif runtime:get("gc_cleaning_permitted") ~= true then
		return "monitor-only"
	elseif self._last_percent and self._last_percent >= EMERGENCY_PERCENT then
		return "emergency"
	elseif self._last_percent and self._last_percent >= CRITICAL_PERCENT then
		return "critical"
	elseif self._pressure then
		return self._tuning_level >= 2 and "pressure-escalated" or "pressure"
	end

	return "monitoring"
end

function module:describe()
	local heap = self._last_heap_mb and string.format("%.1f MB", self._last_heap_mb) or "not sampled"
	local percent = self._last_percent and string.format("%.1f%%", self._last_percent) or "n/a"
	local detail = string.format(
		"heap=%s/%d MB (%s), capacity=%s, full=%d, steps=%d, reclaimed=%.1f MB",
		heap,
		self._heap_capacity_mb,
		percent,
		self._capacity_source,
		self._metrics.full_collections,
		self._metrics.incremental_steps,
		self._metrics.reclaimed_mb
	)

	if self._conflict then
		detail = detail .. ", cleanup=standby"
	end

	return detail
end

return module
