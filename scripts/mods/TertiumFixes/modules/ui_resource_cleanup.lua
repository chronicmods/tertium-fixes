local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "ui_resource_cleanup",
	label = "UI resource cleanup",
	setting_id = "ui_resource_cleanup_enabled",
}

local function _check_render_release(generator, reference_id, keep_reference)
	if type(generator) ~= "table"
		or type(generator._requests_by_size) ~= "table"
		or type(generator._request_by_reference_id) ~= "function" then
		return false
	end

	local request = generator:_request_by_reference_id(reference_id)

	if request == nil then
		return true
	end

	if keep_reference or generator._render_enabled ~= false
		or type(request.references_array) ~= "table"
		or type(request.references_lookup) ~= "table" then
		return false
	end

	-- Suspension empties the array but keeps the owners in the lookup.
	-- A real release must still count the owners that are staying.
	local references = request.references_array
	local present = {}
	local repaired = false

	for i = 1, #references do
		present[references[i]] = true
	end

	for id, owned in pairs(request.references_lookup) do
		if owned and not present[id] then
			references[#references + 1] = id
			repaired = true
		end
	end

	return false, repaired
end

local function _released_item_request(loader, reference_id, check_queue)
	if type(loader) ~= "table"
		or type(loader._requests) ~= "table"
		or type(loader._request_by_id) ~= "function" then
		return false
	end

	if loader:_request_by_id(reference_id) == nil then
		return true
	end

	local queue = loader._requests_to_unload

	if check_queue and type(queue) == "table" then
		for i = 1, #queue do
			if type(queue[i]) == "table" and queue[i].id == reference_id then
				return true
			end
		end
	end

	return false
end

local function _missing_view_reference(ui_manager, view_name, reference_name)
	local views = type(ui_manager) == "table" and ui_manager._views_loading_data
	local references = type(views) == "table" and views[view_name]

	return type(references) == "table"
		and type(reference_name) == "string"
		and references["UIManager_" .. reference_name] == nil
end

local function _resume_request(generator, request_id, render_context, reference_id)
	if type(generator) ~= "table" or type(request_id) ~= "string" then
		return
	end

	local size = render_context and render_context.size or generator._default_size
	local requests_by_size = generator._requests_by_size

	if type(size) ~= "table" or type(requests_by_size) ~= "table"
		or type(generator._get_key_by_size) ~= "function" then
		return
	end

	local size_key = generator:_get_key_by_size(size)
	local requests = requests_by_size[size_key]
	local request = type(requests) == "table" and requests[request_id]

	if type(request) ~= "table" or request.id ~= request_id
		or type(request.references_lookup) ~= "table"
		or not request.references_lookup[reference_id]
		or type(request.references_array) ~= "table"
		or type(generator._requests_queue_order) ~= "table" then
		return
	end

	local suffix = "_" .. size_key

	if request_id:sub(-#suffix) == suffix then
		return request_id:sub(1, #request_id - #suffix), request
	end
end

local function _remove_repeats(entries, value)
	local later_index

	for i = #entries, 1, -1 do
		if entries[i] == value then
			if later_index then
				table.remove(entries, later_index)
			end

			later_index = i
		end
	end
end

local function _finish_resume(generator, request, reference_id)
	-- A shared portrait needs one render job and one entry per owner.
	_remove_repeats(request.references_array, reference_id)
	_remove_repeats(generator._requests_queue_order, request.id)
end

local function _release_empty_party_slots(view)
	local widgets = type(view) == "table" and view._widgets_by_name

	if type(widgets) ~= "table" or type(view._unload_portrait_icon) ~= "function" then
		return 0
	end

	local released = 0

	for i = 1, 4 do
		local widget = widgets["team_member_" .. i]
		local content = type(widget) == "table" and widget.content

		if type(content) == "table" and content.slot_filled == false
			and (content.icon_load_id or content.frame_load_id or content.insignia_load_id) then
			view:_unload_portrait_icon(widget, view._ui_renderer)
			released = released + 1
		end
	end

	return released
end

function module:_clean_party_slots(view, ...)
	if runtime:is_active(self.id) then
		local ok, released = runtime:run(self.id, _release_empty_party_slots, view)

		if ok and released > 0 then
			runtime:record_hit(self.id)
			runtime:record_action(self.id, released)
		end
	end

	return ...
end

function module:_after_resume(generator, request, reference_id, ...)
	local ok = runtime:run(self.id, _finish_resume, generator, request, reference_id)

	if ok then
		runtime:record_action(self.id)
	end

	return ...
end

function module:_skip_release(check, ...)
	if not runtime:is_active(self.id) then
		return false
	end

	local ok, released, repaired = runtime:run(self.id, check, ...)

	if ok and (released or repaired) then
		runtime:record_hit(self.id)
		runtime:record_action(self.id)

		return released == true
	end

	return false
end

function module:install()
	if rawget(_G, "DEDICATED_SERVER") == true then
		runtime:set_available(self.id, false, "dedicated server")

		return
	end

	local item_path = "scripts/ui/item_icon_loader_ui"
	local item_ok = runtime:install_hook(self.id, item_path, "unload_icon", "normal",
		function (func, loader, reference_id, ...)
			if self:_skip_release(_released_item_request, loader, reference_id, true) then
				return
			end

			return func(loader, reference_id, ...)
		end
	)
	local delayed_item_ok = runtime:install_hook(self.id, item_path, "_unload_icon", "normal",
		function (func, loader, reference_id, ...)
			if self:_skip_release(_released_item_request, loader, reference_id, false) then
				return
			end

			return func(loader, reference_id, ...)
		end
	)
	local view_ok = runtime:install_hook(self.id, "scripts/managers/ui/ui_manager", "unload_view", "normal",
		function (func, ui_manager, view_name, reference_name, ...)
			if self:_skip_release(_missing_view_reference, ui_manager, view_name, reference_name) then
				return
			end

			return func(ui_manager, view_name, reference_name, ...)
		end
	)
	local function release_render_request(func, generator, reference_id, ...)
		if self:_skip_release(_check_render_release, generator, reference_id, ...) then
			return
		end

		return func(generator, reference_id, ...)
	end

	local function generate_icon_request(func, generator, request_id, data, load_callback, render_context, prioritized, unload_callback, reference_id, ...)
		if not runtime:is_active(self.id) or reference_id == nil then
			return func(generator, request_id, data, load_callback, render_context, prioritized, unload_callback, reference_id, ...)
		end

		local ok, prefix, request = runtime:run(self.id, _resume_request, generator, request_id, render_context, reference_id)

		if not ok or prefix == nil then
			return func(generator, request_id, data, load_callback, render_context, prioritized, unload_callback, reference_id, ...)
		end

		-- Render toggles pass a full request ID; the loader adds the size itself.
		runtime:record_hit(self.id)

		return self:_after_resume(generator, request, reference_id,
			func(generator, prefix, data, load_callback, render_context, prioritized, unload_callback, reference_id, ...))
	end

	local render_ok = true
	local render_paths = {
		"scripts/ui/portrait_ui",
		"scripts/ui/weapon_icon_ui",
	}

	-- These classes copy the base methods when their files load.
	for i = 1, #render_paths do
		local release_ok = runtime:install_hook(self.id, render_paths[i], "unload_request_reference", "normal", release_render_request)
		local resume_ok = runtime:install_hook(self.id, render_paths[i], "_generate_icon_request", "normal", generate_icon_request)

		render_ok = render_ok and release_ok and resume_ok
	end

	local party_path = "scripts/ui/views/group_finder_view/group_finder_view"
	local party_update_ok = runtime:install_hook(self.id, party_path, "_update_listed_group", "normal",
		function (func, view, ...)
			return self:_clean_party_slots(view, func(view, ...))
		end
	)
	local party_exit_ok = runtime:install_hook(self.id, party_path, "on_exit", "normal",
		function (func, view, ...)
			self:_clean_party_slots(view)

			return func(view, ...)
		end
	)

	if not render_ok or not item_ok or not delayed_item_ok or not view_ok or not party_update_ok or not party_exit_ok then
		runtime:set_available(self.id, false, "UI resource methods unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return "keeps render references stable and releases abandoned UI resources"
end

return module
