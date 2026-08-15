local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "campaign_vox_cleanup",
	label = "Campaign transmission audio cleanup",
	setting_id = "campaign_vox_cleanup_enabled",
}

local function _stop_hover_sound(content)
	if type(content) ~= "table" then
		return 0
	end

	local sound_id = rawget(content, "hover_sound_id")

	-- Clear the widget state before asking Wwise to stop the event. If the
	-- manager rejects a stale handle, the widget still cannot replay or retain
	-- that same leaked handle during teardown.
	content.hover_sound_id = nil
	content.hover_sound_played = nil

	if sound_id == nil then
		return 0
	end

	local managers = rawget(_G, "Managers")
	local ui_manager = managers and managers.ui
	local stop_sound = ui_manager and ui_manager.stop_2d_sound

	if type(stop_sound) == "function" then
		stop_sound(ui_manager, sound_id)

		return 1
	end

	return 0
end

function module:_cleanup(campaign_list)
	local grid = type(campaign_list) == "table" and rawget(campaign_list, "_mission_grid")

	if type(grid) ~= "table" then
		return 0
	end

	local stopped = 0

	for _, columns in pairs(grid) do
		if type(columns) == "table" then
			for _, cell_data in pairs(columns) do
				if type(cell_data) == "table" then
					local widget = rawget(cell_data, "debrief_widget")
					local content = type(widget) == "table" and rawget(widget, "content")

					stopped = stopped + _stop_hover_sound(content)
				end
			end
		end
	end

	return stopped
end

function module:_cleanup_before_original(campaign_list)
	if not runtime:is_active(self.id) then
		return
	end

	local ok, stopped = runtime:run(self.id, self._cleanup, self, campaign_list)

	if ok and stopped > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, stopped)
	end
end

function module:install()
	local class_path = "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list"
	local on_exit_ok = runtime:install_hook(
		self.id,
		class_path,
		"on_exit",
		"normal",
		function (func, campaign_list, ...)
			self:_cleanup_before_original(campaign_list)

			return func(campaign_list, ...)
		end
	)
	local destroy_ok = runtime:install_hook(
		self.id,
		class_path,
		"destroy",
		"normal",
		function (func, campaign_list, ...)
			self:_cleanup_before_original(campaign_list)

			return func(campaign_list, ...)
		end
	)

	if not on_exit_ok or not destroy_ok then
		runtime:set_available(self.id, false, "CampaignMissionList lifecycle methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "stops stored Campaign Data Transmission hover handles on exit and destroy"
end

return module
