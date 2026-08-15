-- chunkname: @scripts/mods/TertiumFixes/hud/hud_element_gc_meter_definitions.lua

local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local METER_WIDTH = 260
local METER_HEIGHT = 42
local METER_PADDING = 8
local BAR_HEIGHT = 7
local BAR_WIDTH = METER_WIDTH - METER_PADDING * 2
local SCREEN_WIDTH = UIWorkspaceSettings.screen.size[1]
local SCREEN_HEIGHT = UIWorkspaceSettings.screen.size[2]
local X_TRAVEL = math.max(SCREEN_WIDTH - METER_WIDTH, 0)
local Y_TRAVEL = math.max(SCREEN_HEIGHT - METER_HEIGHT, 0)
local DEFAULT_X_PERCENT = 5
local DEFAULT_Y_PERCENT = 65

local scenegraph_definition = {
	screen = UIWorkspaceSettings.screen,
	gc_meter = {
		horizontal_alignment = "left",
		parent = "screen",
		vertical_alignment = "top",
		size = {
			METER_WIDTH,
			METER_HEIGHT,
		},
		position = {
			X_TRAVEL * DEFAULT_X_PERCENT * 0.01,
			Y_TRAVEL * DEFAULT_Y_PERCENT * 0.01,
			10,
		},
	},
}

local label_style = table.clone(UIFontSettings.hud_body)

label_style.font_size = 17
label_style.font_type = "machine_medium"
label_style.horizontal_alignment = "left"
label_style.vertical_alignment = "top"
label_style.text_horizontal_alignment = "left"
label_style.text_vertical_alignment = "center"
label_style.text_color = {
	255,
	91,
	158,
	73,
}
label_style.size = {
	BAR_WIDTH,
	22,
}
label_style.offset = {
	METER_PADDING,
	16,
	3,
}

local widget_definitions = {
	gc_meter = UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				color = {
					205,
					6,
					10,
					13,
				},
			},
		},
		{
			pass_type = "rect",
			style_id = "track",
			style = {
				color = {
					235,
					35,
					43,
					48,
				},
				offset = {
					METER_PADDING,
					7,
					1,
				},
				size = {
					BAR_WIDTH,
					BAR_HEIGHT,
				},
			},
		},
		{
			pass_type = "rect",
			style_id = "fill",
			style = {
				color = {
					255,
					91,
					158,
					73,
				},
				offset = {
					METER_PADDING,
					7,
					2,
				},
				size = {
					0,
					BAR_HEIGHT,
				},
			},
		},
		{
			pass_type = "text",
			style_id = "label",
			value = "LUA HEAP  --",
			value_id = "label",
			style = label_style,
		},
	}, "gc_meter"),
}

return {
	bar_width = BAR_WIDTH,
	default_x_percent = DEFAULT_X_PERCENT,
	default_y_percent = DEFAULT_Y_PERCENT,
	scenegraph_definition = scenegraph_definition,
	widget_definitions = widget_definitions,
	x_travel = X_TRAVEL,
	y_travel = Y_TRAVEL,
}
