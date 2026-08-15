local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "player_buff_removal",
	label = "Player buff removal cleanup",
	setting_id = "player_buff_removal_enabled",
}

local function _remove_skipped_buffs(hud)
	if type(hud) ~= "table" then
		return 0
	end

	local active_buffs_data = rawget(hud, "_active_buffs_data")

	if type(active_buffs_data) ~= "table" then
		return 0
	end

	local removed = 0

	-- The stock update walks this array forwards while removing entries. A
	-- backwards repair pass removes only consecutive entries it left behind.
	for i = #active_buffs_data, 1, -1 do
		local buff_data = rawget(active_buffs_data, i)

		if type(buff_data) == "table" and rawget(buff_data, "remove") == true then
			table.remove(active_buffs_data, i)
			removed = removed + 1
		end
	end

	return removed
end

function module:_after_update(hud)
	if not runtime:is_active(self.id) then
		return
	end

	local ok, removed = runtime:run(self.id, _remove_skipped_buffs, hud)

	if ok and removed > 0 then
		runtime:record_hit(self.id)
		runtime:record_action(self.id, removed)
	end
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local hook_ok = runtime:install_hook(
		self.id,
		"scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling",
		"update",
		"safe",
		function (hud)
			self:_after_update(hud)
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "HudElementPlayerBuffsPolling.update unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "removes consecutive stale buff entries skipped by the stock forward pass"
end

return module
