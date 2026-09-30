local common = {
	master_render_settings = {
		graphics_quality = "custom",
		rt_reflections_quality = "off",
		rtxgi_quality = "off",
		ssr_quality = "off",
		dof_quality = "off",
		lens_flare_quality = "off",
		ambient_occlusion_quality = "off",
		light_quality = "low",
		volumetric_fog_quality = "low",
		gi_quality = "low",
	},
	render_settings = {
		dxr = false,
		rt_reflections_enabled = false,
		rt_mixed_reflections = false,
		rt_checkerboard_reflections = false,
		rtxgi_enabled = false,
		baked_ddgi = true,
		rtxgi_scale = 0.5,
		ssr_enabled = false,
		ssr_high_quality = false,
		ao_enabled = false,
		gtao_enabled = false,
		gtao_quality = 0,
		cacao_enabled = false,
		bloom_enabled = false,
		dof_enabled = false,
		dof_high_quality = false,
		motion_blur_enabled = false,
		skin_material_enabled = false,
		lens_quality_enabled = false,
		lens_quality_color_fringe_enabled = false,
		lens_quality_distortion_enabled = false,
		lens_flares_enabled = false,
		sun_flare_enabled = false,
		local_lights_shadows_enabled = false,
		sun_shadows = false,
		static_sun_shadows = false,
		light_shafts_enabled = false,
		volumetric_volumes_enabled = true,
		volumetric_lighting_local_lights = false,
		volumetric_extrapolation_high_quality = false,
		volumetric_extrapolation_volumetric_shadows = false,
		volumetric_reprojection_amount = 0.875,
		volumetric_data_size = { 80, 64, 96 },
	},
}

local function copy(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, item in pairs(value) do
		result[key] = copy(item)
	end
	return result
end

local function profile(id, label, description, changes)
	local values = copy(common)
	for location, settings in pairs(changes or {}) do
		for key, value in pairs(settings) do
			values[location][key] = copy(value)
		end
	end
	return { id = id, label = label, description = description, values = values }
end

local function lighting(atlas_size, sun_enabled, sun_filter, sun_size)
	return {
		local_lights_shadows_enabled = true,
		local_lights_max_dynamic_shadow_distance = 50,
		local_lights_max_non_shadow_casting_distance = 0,
		local_lights_max_static_shadow_distance = 100,
		local_lights_shadow_map_filter_quality = "low",
		local_lights_shadow_atlas_size = { atlas_size, atlas_size },
		static_sun_shadows = true,
		static_sun_shadow_map_size = { 2048, 2048 },
		sun_shadows = sun_enabled,
		sun_shadow_map_filter_quality = sun_filter,
		sun_shadow_map_size = { sun_size, sun_size },
	}
end

local balanced_render = lighting(512, false, "low", 4)
balanced_render.ao_enabled = true
balanced_render.gtao_enabled = true

local quality_render = lighting(1024, true, "medium", 2048)
quality_render.ao_enabled = true
quality_render.gtao_enabled = true
quality_render.gtao_quality = 1
quality_render.rtxgi_scale = 1
quality_render.light_shafts_enabled = true
quality_render.volumetric_lighting_local_lights = true
quality_render.volumetric_extrapolation_high_quality = true
quality_render.volumetric_reprojection_amount = 0.625
quality_render.volumetric_data_size = { 96, 80, 128 }

-- Performance modes leave shadow-map sizes alone while shadows are disabled.
-- None of these profiles changes geometry, corpse or decal limits.
return {
	ultra_performance = profile("ultra_performance", "Ultra Performance",
		"Removes AO, shadows and fog volumes. Fog and gas areas may look different.", {
			render_settings = { volumetric_volumes_enabled = false },
		}),
	performance = profile("performance", "Performance",
		"Removes AO and shadows while keeping low fog volumes without extra light shafts or local fog lighting."),
	balanced = profile("balanced", "Balanced",
		"Keeps low AO, shadows and fog while leaving ray tracing, screen reflections and costly post effects off.", {
			master_render_settings = { ambient_occlusion_quality = "low" },
			render_settings = balanced_render,
		}),
	quality = profile("quality", "Quality",
		"Keeps medium AO, lighting and fog with higher baked lighting detail. Ray tracing and screen reflections stay off.", {
			master_render_settings = {
				ambient_occlusion_quality = "medium",
				light_quality = "medium",
				volumetric_fog_quality = "medium",
				gi_quality = "high",
			},
			render_settings = quality_render,
		}),
}
