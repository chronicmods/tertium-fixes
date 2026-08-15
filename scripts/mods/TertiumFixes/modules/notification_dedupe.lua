local mod = get_mod("TertiumFixes")
local runtime = mod._tf_runtime

local module = {
	id = "notification_dedupe",
	label = "Notification deduplication",
	setting_id = "notification_dedupe_enabled",
	_seen = {},
	_queue = {},
	_queue_head = 1,
}

local function _scalar(value, allow_nil)
	local value_type = type(value)

	if value == nil then
		return allow_nil and "z;" or nil
	end

	if value_type == "string" or value_type == "number" or value_type == "boolean" then
		local encoded = tostring(value)
		local tag = value_type == "string" and "s"
			or value_type == "number" and "n"
			or "b"

		return tag .. tostring(#encoded) .. ":" .. encoded
	end

	return nil
end

local function _fingerprint(message_type, data, sound_event)
	local message_type_part = _scalar(message_type, false)
	local data_part
	local sound_part = _scalar(sound_event, true)

	if not message_type_part or not sound_part then
		return nil
	end

	if message_type == "default" or message_type == "mission" then
		data_part = _scalar(data, false)
	elseif message_type == "alert" and type(data) == "table" then
		local text_part = _scalar(rawget(data, "text"), false)
		local alert_type_part = _scalar(rawget(data, "type"), true)

		if text_part and alert_type_part then
			data_part = text_part .. alert_type_part
		end
	end

	if not data_part then
		return nil
	end

	-- Every scalar is type-tagged and length-prefixed, and nil has its own tag.
	-- Concatenation therefore cannot collide at field boundaries. Unsupported
	-- values deliberately return nil so complex notifications pass through.
	return message_type_part .. data_part .. sound_part
end

function module:_prune(now, window)
	local queue = self._queue
	local head = self._queue_head

	while head <= #queue do
		local entry = queue[head]

		if entry.time > now - window and (#queue - head + 1) <= 384 then
			break
		end

		if self._seen[entry.key] == entry.time then
			self._seen[entry.key] = nil
		end

		queue[head] = false
		head = head + 1
	end

	if head > 128 then
		local compact = {}

		for i = head, #queue do
			compact[#compact + 1] = queue[i]
		end

		self._queue = compact
		self._queue_head = 1
	else
		self._queue_head = head
	end
end

function module:_is_duplicate(message_type, data, callback, sound_event, done_callback, delay)
	if callback ~= nil or done_callback ~= nil or delay ~= nil then
		return false
	end

	if message_type ~= "default" and message_type ~= "alert" then
		if message_type ~= "mission" or runtime:get("notification_include_mission") ~= true then
			return false
		end
	end

	local key = _fingerprint(message_type, data, sound_event)

	if not key then
		return false
	end

	local now = runtime.clock
	local window = tonumber(runtime:get("notification_dedupe_window_seconds")) or 2

	self:_prune(now, window)

	local previous_time = self._seen[key]

	self._seen[key] = now
	self._queue[#self._queue + 1] = {
		key = key,
		time = now,
	}

	return previous_time ~= nil and now - previous_time <= window
end

function module:install()
	local hook_ok = runtime:install_hook(
		self.id,
		"scripts/ui/constant_elements/elements/notification_feed/constant_element_notification_feed",
		"event_add_notification_message",
		"normal",
		function (func, notification_feed, message_type, data, callback, sound_event, done_callback, delay)
			if not runtime:is_active(self.id) then
				return func(notification_feed, message_type, data, callback, sound_event, done_callback, delay)
			end

			local ok, duplicate = runtime:run(
				self.id,
				self._is_duplicate,
				self,
				message_type,
				data,
				callback,
				sound_event,
				done_callback,
				delay
			)

			if not ok then
				return func(notification_feed, message_type, data, callback, sound_event, done_callback, delay)
			end

			if duplicate then
				runtime:record_hit(self.id)
				runtime:record_action(self.id)

				return
			end

			return func(notification_feed, message_type, data, callback, sound_event, done_callback, delay)
		end
	)

	if not hook_ok then
		runtime:set_available(self.id, false, "NotificationFeed method unavailable")
	end
end

function module:reset()
	self._seen = {}
	self._queue = {}
	self._queue_head = 1
end

function module:on_enabled()
	self:reset()
end

function module:on_disabled()
	self:reset()
end

function module:on_unload()
	self:reset()
end

function module:runtime_status()
	return runtime:is_active(self.id) and "guarding" or "disabled"
end

function module:describe()
	return string.format("window=%ss, cached=%d", tostring(runtime:get("notification_dedupe_window_seconds")), #self._queue - self._queue_head + 1)
end

return module
