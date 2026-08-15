local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "notification_queue_callbacks",
	label = "Notification overflow callback preservation",
	setting_id = "notification_queue_callbacks_enabled",
}

function module:_restore_callbacks(
	notification_feed,
	message_type,
	data,
	notification_id,
	start_callback,
	done_callback
)
	local queue = type(notification_feed) == "table"
		and rawget(notification_feed, "_queue_notifications")
	local queued = type(queue) == "table" and rawget(queue, 1)

	if type(queued) ~= "table"
		or rawget(queued, "id") ~= notification_id
		or rawget(queued, "message_type") ~= message_type
		or rawget(queued, "data") ~= data then
		return start_callback, done_callback, 0
	end

	local restored = 0

	if start_callback == nil and rawget(queued, "start_callback") ~= nil then
		start_callback = rawget(queued, "start_callback")
		restored = restored + 1
	end

	if done_callback == nil and rawget(queued, "done_callback") ~= nil then
		done_callback = rawget(queued, "done_callback")
		restored = restored + 1
	end

	return start_callback, done_callback, restored
end

function module:install()
	local hook_ok = runtime:install_hook(
		self.id,
		"scripts/ui/constant_elements/elements/notification_feed/constant_element_notification_feed",
		"_add_notification_message",
		"normal",
		function (func, notification_feed, message_type, data, notification_id, start_callback, sound_event, done_callback)
			if not runtime:is_active(self.id) then
				return func(
					notification_feed,
					message_type,
					data,
					notification_id,
					start_callback,
					sound_event,
					done_callback
				)
			end

			local ok, restored_start, restored_done, restored = runtime:run(
				self.id,
				self._restore_callbacks,
				self,
				notification_feed,
				message_type,
				data,
				notification_id,
				start_callback,
				done_callback
			)

			if ok and restored > 0 then
				start_callback = restored_start
				done_callback = restored_done
				runtime:record_hit(self.id)
				runtime:record_action(self.id, restored)
			end

			return func(
				notification_feed,
				message_type,
				data,
				notification_id,
				start_callback,
				sound_event,
				done_callback
			)
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "NotificationFeed queue method unavailable")
	end
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding overflow queue" or "disabled"
end

function module:describe()
	return "restores start/done callbacks dropped while a full feed drains"
end

return module
