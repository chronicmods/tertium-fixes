local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "social_roster_portrait",
	label = "Social roster portrait frames",
	setting_id = "social_roster_portrait_enabled",
}

local function _release_queued_frame(view, widget, frame_id, queue, first_index)
	local ui_manager = Managers and Managers.ui

	if view._icon_unload_queue ~= queue
		or not ui_manager or type(ui_manager.unload_item_icon) ~= "function" then
		return false
	end

	for i = #queue, first_index, -1 do
		local entry = queue[i]

		if type(entry) == "table" and entry.widget == widget
			and entry.load_id == frame_id and entry.delay == 0 then
			-- Clear the old material before a cached replacement can set the new one.
			-- The icon loader still waits two frames before releasing its packages.
			ui_manager:unload_item_icon(frame_id)
			table.remove(queue, i)

			return true
		end
	end

	return false
end

function module:_after_queue(view, widget, frame_id, queue, first_index, ...)
	local ok, released = runtime:run(self.id, _release_queued_frame, view, widget, frame_id, queue, first_index)

	if ok and released then
		runtime:record_hit(self.id)
		runtime:record_action(self.id)
	end

	return ...
end

function module:install()
	local ok = runtime:install_hook(
		self.id,
		"scripts/ui/views/social_menu_roster_view/social_menu_roster_view",
		"_queue_icons_for_unload",
		"normal",
		function (func, view, widget, ...)
			local content = type(widget) == "table" and widget.content
			local frame_id = type(content) == "table" and content.frame_load_id
			local queue = type(view) == "table" and view._icon_unload_queue

			if not runtime:is_active(self.id) or frame_id == nil or type(queue) ~= "table" then
				return func(view, widget, ...)
			end

			local first_index = #queue + 1

			return self:_after_queue(view, widget, frame_id, queue, first_index, func(view, widget, ...))
		end
	)

	if not ok then
		runtime:set_available(self.id, false, "Social roster icon queue unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "clears the old roster frame before its replacement loads"
end

return module
