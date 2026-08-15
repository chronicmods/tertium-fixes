local failures = 0
local checks = 0

local function check(condition, message)
	checks = checks + 1

	if condition then
		io.write("PASS " .. message .. "\n")
	else
		failures = failures + 1
		io.stderr:write("FAIL " .. message .. "\n")
	end
end

local settings = {
	notification_dedupe_enabled = true,
	notification_dedupe_window_seconds = 2,
	notification_include_mission = false,
}
local hooks = {}
local active = true
local force_run_failure = false
local hits = 0
local actions = 0

local runtime = {
	clock = 0,
}

function runtime:get(setting_id)
	return settings[setting_id]
end

function runtime:is_active(module_id)
	return active and (
		module_id == "notification_dedupe"
			or module_id == "notification_queue_callbacks"
	)
end

function runtime:install_hook(module_id, path, method_name, hook_kind, callback)
	hooks[module_id .. ":" .. method_name] = callback

	return path ~= nil and hook_kind == "normal"
end

function runtime:run(_, callback, ...)
	if force_run_failure then
		return false, "forced test failure"
	end

	return pcall(callback, ...)
end

function runtime:record_hit(_, count)
	hits = hits + (count or 1)
end

function runtime:record_action(_, count)
	actions = actions + (count or 1)
end

function runtime:set_available()
end

local mod = {
	_tf_runtime = runtime,
}

function get_mod(name)
	if name == "TertiumFixes" then
		return mod
	end
end

local module = dofile("scripts/mods/TertiumFixes/modules/notification_dedupe.lua")
module:install()
local queue_module = dofile("scripts/mods/TertiumFixes/modules/notification_queue_callbacks.lua")
queue_module:install()

local hook = hooks["notification_dedupe:event_add_notification_message"]
local queue_hook = hooks["notification_queue_callbacks:_add_notification_message"]

check(type(hook) == "function", "notification hook installs")
check(type(queue_hook) == "function", "notification overflow callback hook installs")

local calls = {}
local return_marker = {}

local function original(...)
	local call = {
		count = select("#", ...),
	}

	for index = 1, call.count do
		call[index] = select(index, ...)
	end

	calls[#calls + 1] = call

	return return_marker
end

local feed = {}
local add_callback = function()
end
local done_callback = function()
end
local start_callback = function()
end

active = false
local inactive_result = hook(
	original,
	feed,
	"default",
	"inactive",
	add_callback,
	"sound",
	done_callback,
	1,
	start_callback
)

check(
	inactive_result == return_marker
		and #calls == 1
		and calls[1].count == 8
		and calls[1][1] == feed
		and calls[1][4] == add_callback
		and calls[1][6] == done_callback
		and calls[1][7] == 1
		and calls[1][8] == start_callback,
	"inactive hook forwards the complete Darktide 1.12.4 call"
)

active = true
calls = {}
module:reset()
runtime.clock = 10

local first_result = hook(original, feed, "default", "same", nil, nil, nil, nil, nil)
runtime.clock = 10.5
local duplicate_result = hook(original, feed, "default", "same", nil, nil, nil, nil, nil)

check(
	first_result == return_marker
		and duplicate_result == nil
		and #calls == 1
		and hits == 1
		and actions == 1,
	"a safe repeated notification is suppressed exactly once"
)

calls = {}
module:reset()
runtime.clock = 20

hook(original, feed, "default", "start-side-effect", nil, nil, nil, nil, start_callback)
runtime.clock = 20.2
hook(original, feed, "default", "start-side-effect", nil, nil, nil, nil, start_callback)

check(
	#calls == 2
		and calls[1].count == 8
		and calls[1][8] == start_callback
		and calls[2][8] == start_callback,
	"start callbacks are never deduplicated or dropped"
)

calls = {}
module:reset()
runtime.clock = 30

hook(original, feed, "default", "add-side-effect", add_callback, nil, nil, nil, nil)
hook(original, feed, "default", "done-side-effect", nil, nil, done_callback, nil, nil)
hook(original, feed, "default", "delayed", nil, nil, nil, 0.5, nil)

check(
	#calls == 3
		and calls[1][4] == add_callback
		and calls[2][6] == done_callback
		and calls[3][7] == 0.5,
	"add, done, and delay side effects always pass through"
)

calls = {}
module:reset()
force_run_failure = true
local failure_result = hook(
	original,
	feed,
	"default",
	"fail-open",
	add_callback,
	"sound",
	done_callback,
	2,
	start_callback
)
force_run_failure = false

check(
	failure_result == return_marker
		and #calls == 1
		and calls[1].count == 8
		and calls[1][8] == start_callback,
	"guard failure preserves the complete original call"
)

calls = {}
module:reset()
runtime.clock = 40
hook(original, feed, "mission", "objective", nil, nil, nil, nil, nil)
runtime.clock = 40.1
hook(original, feed, "mission", "objective", nil, nil, nil, nil, nil)

check(#calls == 2, "mission notifications remain excluded by default")

local lifecycle_start_count = 0
local lifecycle_done_count = 0
local lifecycle_start_id
local lifecycle_data = {}
local lifecycle_feed = {
	_notifications = {},
	_queue_notifications = {},
}

local function stock_add_notification(
	stock_feed,
	message_type,
	data,
	notification_id,
	start_callback_arg,
	sound_event,
	done_callback_arg
)
	if #stock_feed._notifications >= 1 then
		stock_feed._queue_notifications[#stock_feed._queue_notifications + 1] = {
			message_type = message_type,
			data = data,
			start_callback = start_callback_arg,
			done_callback = done_callback_arg,
			sound_event = sound_event,
			id = notification_id,
		}

		return
	end

	local notification = {
		data = data,
		done_callback = done_callback_arg,
		id = notification_id,
		message_type = message_type,
		sound_event = sound_event,
	}

	stock_feed._notifications[#stock_feed._notifications + 1] = notification

	if start_callback_arg then
		start_callback_arg(notification_id)
	end

	return notification
end

local function guarded_stock_add(...)
	return queue_hook(stock_add_notification, ...)
end

-- This deliberately reproduces Darktide 1.12.4's overflow promotion bug:
-- it reads the obsolete `callback` field and omits the stored done callback.
local function stock_remove_notification(stock_feed, notification_to_remove)
	for index = 1, #stock_feed._notifications do
		local notification = stock_feed._notifications[index]

		if notification == notification_to_remove then
			table.remove(stock_feed._notifications, index)

			if notification.done_callback then
				notification.done_callback()
			end

			break
		end
	end

	if stock_feed._queue_notifications[1] and #stock_feed._notifications < 1 then
		local queued_notification = stock_feed._queue_notifications[1]
		local callback_arg = queued_notification.callback

		guarded_stock_add(
			stock_feed,
			queued_notification.message_type,
			queued_notification.data,
			queued_notification.id,
			callback_arg,
			queued_notification.sound_event
		)
		table.remove(stock_feed._queue_notifications, 1)
	end
end

local visible_notification = guarded_stock_add(
	lifecycle_feed,
	"default",
	"visible",
	40,
	nil,
	nil,
	nil
)
guarded_stock_add(
	lifecycle_feed,
	"default",
	lifecycle_data,
	41,
	function (notification_id)
		lifecycle_start_count = lifecycle_start_count + 1
		lifecycle_start_id = notification_id
	end,
	"queue_sound",
	function ()
		lifecycle_done_count = lifecycle_done_count + 1
	end
)

check(
	#lifecycle_feed._notifications == 1
		and #lifecycle_feed._queue_notifications == 1
		and lifecycle_start_count == 0
		and lifecycle_done_count == 0,
	"stock overflow keeps callbacks dormant while the item is queued"
)

local hits_before_lifecycle = hits
local actions_before_lifecycle = actions
stock_remove_notification(lifecycle_feed, visible_notification)
local promoted_notification = lifecycle_feed._notifications[1]

check(
	#lifecycle_feed._queue_notifications == 0
		and #lifecycle_feed._notifications == 1
		and promoted_notification.id == 41
		and promoted_notification.data == lifecycle_data
		and lifecycle_start_count == 1
		and lifecycle_start_id == 41
		and lifecycle_done_count == 0
		and hits == hits_before_lifecycle + 1
		and actions == actions_before_lifecycle + 2,
	"overflow removal promotes the same queued id and fires its restored start callback exactly once"
)

stock_remove_notification(lifecycle_feed, promoted_notification)
stock_remove_notification(lifecycle_feed, promoted_notification)

check(
	#lifecycle_feed._notifications == 0
		and lifecycle_start_count == 1
		and lifecycle_done_count == 1
		and hits == hits_before_lifecycle + 1
		and actions == actions_before_lifecycle + 2,
	"the promoted notification retains its done callback and fires it exactly once on later removal"
)

calls = {}
local queued_data = {}
local queued_start = function ()
end
local queued_done = function ()
end
local queue_feed = {
	_queue_notifications = {
		{
			data = queued_data,
			done_callback = queued_done,
			id = 41,
			message_type = "default",
			start_callback = queued_start,
		},
	},
}
local hits_before_queue = hits
local actions_before_queue = actions
local queue_result = queue_hook(
	original,
	queue_feed,
	"default",
	queued_data,
	41,
	nil,
	"queue_sound",
	nil
)

check(
	queue_result == return_marker
		and #calls == 1
		and calls[1].count == 7
		and calls[1][1] == queue_feed
		and calls[1][5] == queued_start
		and calls[1][6] == "queue_sound"
		and calls[1][7] == queued_done
		and hits == hits_before_queue + 1
		and actions == actions_before_queue + 2,
	"overflow drain restores both exact callbacks and preserves the complete call"
)

calls = {}
local hits_before_mismatch = hits
local actions_before_mismatch = actions
queue_hook(original, queue_feed, "default", queued_data, 42, nil, nil, nil)
queue_hook(original, queue_feed, "default", {}, 41, nil, nil, nil)

check(
	#calls == 2
		and calls[1].count == 7
		and calls[1][5] == nil
		and calls[1][7] == nil
		and calls[2][5] == nil
		and calls[2][7] == nil
		and hits == hits_before_mismatch
		and actions == actions_before_mismatch,
	"ordinary or mismatched adds remain byte-for-byte callback no-ops"
)

calls = {}
active = false
local explicit_start = function ()
end
local explicit_done = function ()
end
queue_result = queue_hook(
	original,
	queue_feed,
	"alert",
	"direct",
	43,
	explicit_start,
	"direct_sound",
	explicit_done
)
active = true

check(
	queue_result == return_marker
		and #calls == 1
		and calls[1].count == 7
		and calls[1][5] == explicit_start
		and calls[1][6] == "direct_sound"
		and calls[1][7] == explicit_done,
	"disabled overflow guard preserves every direct argument and return"
)

calls = {}
force_run_failure = true
queue_result = queue_hook(
	original,
	queue_feed,
	"default",
	queued_data,
	41,
	nil,
	"fail_open_sound",
	nil
)
force_run_failure = false

check(
	queue_result == return_marker
		and #calls == 1
		and calls[1].count == 7
		and calls[1][5] == nil
		and calls[1][6] == "fail_open_sound"
		and calls[1][7] == nil,
	"overflow guard failure passes the exact original call through"
)

io.write(string.format("notification_dedupe_behavior: %d passed, %d failed\n", checks - failures, failures))

if failures > 0 then
	os.exit(1)
end
