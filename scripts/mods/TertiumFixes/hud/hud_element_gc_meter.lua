-- chunkname: @scripts/mods/TertiumFixes/hud/hud_element_gc_meter.lua

local mod = get_mod("TertiumFixes")
local Definitions = mod:io_dofile("TertiumFixes/scripts/mods/TertiumFixes/hud/hud_element_gc_meter_definitions")
local HudElementTertiumFixesGcMeter = class("HudElementTertiumFixesGcMeter", "HudElementBase")

local REFRESH_INTERVAL = 0.5
local BAR_WIDTH = Definitions.bar_width
local DEFAULT_X_PERCENT = Definitions.default_x_percent
local DEFAULT_Y_PERCENT = Definitions.default_y_percent
local X_TRAVEL = Definitions.x_travel
local Y_TRAVEL = Definitions.y_travel

local COLORS = {
	normal = {
		255,
		91,
		158,
		73,
	},
	watch = {
		255,
		106,
		180,
		205,
	},
	pressure = {
		255,
		226,
		181,
		63,
	},
	warning = {
		255,
		242,
		132,
		54,
	},
	critical = {
		255,
		224,
		72,
		72,
	},
	emergency = {
		255,
		255,
		44,
		77,
	},
}

local function read_snapshot(runtime)
	if not runtime or type(runtime.get_module) ~= "function" then
		return nil
	end

	local gc_pressure = runtime:get_module("gc_pressure")

	if not gc_pressure or type(gc_pressure.meter_snapshot) ~= "function" then
		return nil
	end

	return gc_pressure:meter_snapshot()
end

local function copy_color(destination, source)
	destination[1] = source[1]
	destination[2] = source[2]
	destination[3] = source[3]
	destination[4] = source[4]
end

local function clamp_percent(value)
	if value < 0 then
		return 0
	elseif value > 100 then
		return 100
	end

	return value
end

local function fallback_severity(percent)
	if percent >= 95 then
		return "emergency"
	elseif percent >= 90 then
		return "critical"
	elseif percent >= 85 then
		return "warning"
	elseif percent >= 80 then
		return "pressure"
	elseif percent >= 65 then
		return "watch"
	end

	return "normal"
end

HudElementTertiumFixesGcMeter.init = function (self, parent, draw_layer, start_scale)
	HudElementTertiumFixesGcMeter.super.init(self, parent, draw_layer, start_scale, Definitions)

	local widget = self._widgets_by_name.gc_meter

	self._runtime = mod and mod._tf_runtime
	self._refresh_elapsed = REFRESH_INTERVAL
	self._meter_x_percent = DEFAULT_X_PERCENT
	self._meter_y_percent = DEFAULT_Y_PERCENT
	widget.content.visible = false
end

HudElementTertiumFixesGcMeter.destroy = function (self, ui_renderer)
	HudElementTertiumFixesGcMeter.super.destroy(self, ui_renderer)
end

HudElementTertiumFixesGcMeter.update = function (self, dt, t, ui_renderer, render_settings, input_service)
	local refresh_elapsed = self._refresh_elapsed + dt

	if refresh_elapsed >= REFRESH_INTERVAL then
		self._refresh_elapsed = 0
		self:_refresh_meter()
	else
		self._refresh_elapsed = refresh_elapsed
	end

	HudElementTertiumFixesGcMeter.super.update(self, dt, t, ui_renderer, render_settings, input_service)
end

HudElementTertiumFixesGcMeter._refresh_meter = function (self)
	if not self._runtime then
		self._runtime = mod and mod._tf_runtime
	end

	local widget = self._widgets_by_name.gc_meter
	local success, snapshot = pcall(read_snapshot, self._runtime)

	if not success or type(snapshot) ~= "table" or snapshot.visible ~= true then
		if widget.content.visible then
			widget.content.visible = false
			widget.dirty = true
		end

		return
	end

	local x_percent = tonumber(snapshot.x)
	local y_percent = tonumber(snapshot.y)

	x_percent = clamp_percent(x_percent or self._meter_x_percent)
	y_percent = clamp_percent(y_percent or self._meter_y_percent)

	if x_percent ~= self._meter_x_percent or y_percent ~= self._meter_y_percent then
		self._meter_x_percent = x_percent
		self._meter_y_percent = y_percent
		self:set_scenegraph_position("gc_meter", X_TRAVEL * x_percent * 0.01, Y_TRAVEL * y_percent * 0.01)
	end

	local percent = tonumber(snapshot.percent or snapshot.usage_percent)

	if not percent then
		local ratio = tonumber(snapshot.ratio)

		percent = ratio and ratio * 100 or 0
	end

	percent = clamp_percent(percent)

	local severity = snapshot.severity or snapshot.level
	local color = COLORS[severity] or COLORS[fallback_severity(percent)]
	local style = widget.style

	style.fill.size[1] = BAR_WIDTH * percent * 0.01
	copy_color(style.fill.color, color)
	copy_color(style.label.text_color, color)

	local label = snapshot.label or snapshot.text

	if type(label) == "string" and label ~= "" then
		widget.content.label = label
	else
		local heap_mb = tonumber(snapshot.heap_mb) or 0
		local capacity_mb = tonumber(snapshot.capacity_mb or snapshot.limit_mb or snapshot.cap_mb) or 0

		widget.content.label = string.format("LUA HEAP  %.0f%%  %.1f / %.0f MB", percent, heap_mb, capacity_mb)
	end

	widget.content.visible = true
	widget.dirty = true
end

return HudElementTertiumFixesGcMeter
