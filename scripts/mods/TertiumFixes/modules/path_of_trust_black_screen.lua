local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local TARGET_CINEMATIC = "path_of_trust_09"
local REPAIR_FADE_SECONDS = 0.25
local COMPLETION_WINDOW_SECONDS = 10

local module = {
	id = "path_of_trust_black_screen",
	label = "Path of Trust black-screen recovery",
	setting_id = "path_of_trust_black_screen_enabled",
	_awaiting_fade_out = false,
	_completion_deadline = nil,
}

local function _queue_is_empty(cinematic_manager)
	local queue = type(cinematic_manager) == "table"
		and rawget(cinematic_manager, "_queued_stories")

	return type(queue) == "table" and rawget(queue, 1) == nil
end

function module:_observe_completion(cinematic_manager, was_target)
	if not was_target
		or type(cinematic_manager) ~= "table"
		or rawget(cinematic_manager, "_is_server") == true
		or rawget(cinematic_manager, "_active_story") ~= nil
		or not _queue_is_empty(cinematic_manager) then
		return
	end

	self._awaiting_fade_out = true
	self._completion_deadline = runtime.clock + COMPLETION_WINDOW_SECONDS
	runtime:record_hit(self.id)
end

function module:_repair_if_stuck(hud)
	if not self._awaiting_fade_out then
		return
	end

	if runtime.clock > (self._completion_deadline or 0) then
		self._awaiting_fade_out = false
		self._completion_deadline = nil

		return
	end

	-- A valid fade-out, immediate or scheduled, always changes one of these
	-- fields. Only repair the exact terminal fully-black state left by the
	-- missing Path of Trust flow event.
	if rawget(hud, "_fading_in") ~= true then
		self._awaiting_fade_out = false
		self._completion_deadline = nil

		return
	end

	if rawget(hud, "_fade_duration") ~= nil
		or rawget(hud, "_fade_out_data") ~= nil then
		return
	end

	local player = rawget(hud, "_player")
	local fade_out = hud.event_cutscene_fade_out

	if player == nil or type(fade_out) ~= "function" then
		return
	end

	fade_out(
		hud,
		player,
		REPAIR_FADE_SECONDS,
		nil,
		rawget(hud, "_fade_color")
	)

	self._awaiting_fade_out = false
	self._completion_deadline = nil
	runtime:record_action(self.id)
end

function module:_after_hud_update(hud)
	if not runtime:is_active(self.id) then
		return
	end

	runtime:run(self.id, self._repair_if_stuck, self, hud)
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local manager_ok = runtime:install_hook(
		self.id,
		"scripts/managers/cinematic/cinematic_manager",
		"update",
		"normal",
		function (func, cinematic_manager, ...)
			local story = type(cinematic_manager) == "table"
				and rawget(cinematic_manager, "_active_story")
			local was_target = type(story) == "table"
				and rawget(story, "cinematic_scene_name") == TARGET_CINEMATIC
			local a, b, c, d = func(cinematic_manager, ...)

			if runtime:is_active(self.id) then
				runtime:run(
					self.id,
					self._observe_completion,
					self,
					cinematic_manager,
					was_target
				)
			end

			return a, b, c, d
		end
	)
	local hud_ok = runtime:install_hook(
		self.id,
		"scripts/ui/hud/elements/cutscene_fading/hud_element_cutscene_fading",
		"update",
		"safe",
		function (hud)
			self:_after_hud_update(hud)
		end
	)

	if not manager_ok or not hud_ok then
		runtime:set_available(
			self.id,
			false,
			"CinematicManager or cutscene-fading HUD lifecycle unavailable"
		)
	end
end

function module:on_setting_changed(setting_id)
	if setting_id == self.setting_id and not runtime:is_active(self.id) then
		self:reset()
	end
end

function module:on_disabled()
	self:reset()
end

function module:on_unload()
	self:reset()
end

function module:reset()
	self._awaiting_fade_out = false
	self._completion_deadline = nil
end

function module:runtime_status()
	if self._awaiting_fade_out then
		return "checking final fade"
	end

	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "releases only a stranded full-black fade after path_of_trust_09 ends"
end

return module
