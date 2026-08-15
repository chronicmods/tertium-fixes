local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "penance_carousel_scroll",
	label = "Penances carousel wheel direction",
	setting_id = "penance_carousel_scroll_enabled",
}

local function _read_axis(axis, index)
	local ok, value = pcall(function ()
		return axis[index]
	end)

	if ok then
		return value
	end

	return nil
end

function module:_input_proxy(input_service)
	local original_get = input_service.get
	local original_null_service = input_service.null_service
	local proxy = {}

	proxy.get = function (_, action_name, ...)
		local value = original_get(input_service, action_name, ...)

		if action_name ~= "scroll_axis" or value == nil then
			return value
		end

		local x = _read_axis(value, 1)
		local y = _read_axis(value, 2)
		local z = _read_axis(value, 3)

		if type(y) ~= "number" then
			return value
		end

		if y ~= 0 then
			runtime:record_hit(self.id)
			runtime:record_action(self.id)
		end

		return {
			x or 0,
			-y,
			z or 0,
		}
	end

	proxy.null_service = function (_, ...)
		return original_null_service(input_service, ...)
	end

	return proxy
end

function module:install()
	runtime:install_hook(
		self.id,
		"scripts/ui/views/penance_overview_view/penance_overview_view",
		"_handle_carousel_scroll",
		"normal",
		function (func, view, input_service, dt, ...)
			if not runtime:is_active(self.id)
				or type(view) ~= "table"
				or rawget(view, "_using_cursor_navigation") ~= true
				or type(input_service) ~= "table"
				or type(input_service.get) ~= "function"
				or type(input_service.null_service) ~= "function" then
				return func(view, input_service, dt, ...)
			end

			local ok, proxy = runtime:run(self.id, self._input_proxy, self, input_service)

			if not ok or type(proxy) ~= "table" then
				return func(view, input_service, dt, ...)
			end

			return func(view, proxy, dt, ...)
		end
	)
end

function module:runtime_status()
	return runtime:is_active(self.id) and "correcting mouse wheel" or "disabled"
end

function module:describe()
	return "reverses only the Penances carousel mouse-wheel axis"
end

return module
