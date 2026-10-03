class_name RenderPresets
extends RefCounted

## Concrete rendering configuration for the COMPETITIVE / BALANCED / QUALITY presets.
##
## Competitive shooters trade image quality for frame pacing and clarity. VANTA's
## COMPETITIVE preset therefore disables every effect that either costs frame time
## or adds visual noise around a target: no motion blur (VANTA never implements
## it), no depth of field, no bloom, no SSAO, no volumetric fog, no particles
## beyond impact marks, and no shadows on moving targets.
##
## These values are applied by `src/core/display_service.gd`. Nothing here is a
## performance *claim*; docs/PERFORMANCE.md records what has actually been measured.

const PRESETS: Array[Dictionary] = [
	{
		"id": "competitive",
		"label": "COMPETITIVE",
		"description": "Minimum cost, maximum target clarity. Shadows and post effects off.",
		"msaa": 0,
		"screen_space_aa": 0,
		"use_taa": false,
		"render_scale": 1.0,
		"shadows": false,
		"shadow_quality": 0,
		"ssao": false,
		"ssil": false,
		"sdfgi": false,
		"glow": false,
		"fog": false,
		"volumetric_fog": false,
		"dof": false,
		"motion_blur": false,
		"debris_particles": false,
		"impact_marks": true,
		"arena_detail": "minimal",
		"sky_quality": "flat",
	},
	{
		"id": "balanced",
		"label": "BALANCED",
		"description": "Low-cost contact shadows, subtle anti-aliasing, same target clarity.",
		"msaa": 2,
		"screen_space_aa": 0,
		"use_taa": false,
		"render_scale": 1.0,
		"shadows": true,
		"shadow_quality": 1,
		"ssao": false,
		"ssil": false,
		"sdfgi": false,
		"glow": false,
		"fog": false,
		"volumetric_fog": false,
		"dof": false,
		"motion_blur": false,
		"debris_particles": false,
		"impact_marks": true,
		"arena_detail": "standard",
		"sky_quality": "gradient",
	},
	{
		"id": "quality",
		"label": "QUALITY",
		"description": "Anti-aliasing, soft shadows and a subtle ambient occlusion pass.",
		"msaa": 4,
		"screen_space_aa": 1,
		"use_taa": false,
		"render_scale": 1.0,
		"shadows": true,
		"shadow_quality": 2,
		"ssao": true,
		"ssil": false,
		"sdfgi": false,
		"glow": false,
		"fog": false,
		"volumetric_fog": false,
		"dof": false,
		"motion_blur": false,
		"debris_particles": true,
		"impact_marks": true,
		"arena_detail": "detailed",
		"sky_quality": "gradient",
	},
]


static func by_index(index: int) -> Dictionary:
	return PRESETS[clampi(index, 0, PRESETS.size() - 1)]


static func by_id(preset_id: String) -> Dictionary:
	for p in PRESETS:
		if p["id"] == preset_id:
			return p
	return PRESETS[0]


static func index_of(preset_id: String) -> int:
	for i in PRESETS.size():
		if PRESETS[i]["id"] == preset_id:
			return i
	return 0


static func labels() -> Array[String]:
	var out: Array[String] = []
	for p in PRESETS:
		out.append(String(p["label"]))
	return out
