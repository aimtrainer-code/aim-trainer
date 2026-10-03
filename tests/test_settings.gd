extends VantaTestCase

## Settings are user-editable JSON. These tests treat that file as hostile input:
## the model must always yield a usable configuration and must report what it
## repaired instead of silently accepting nonsense.


func test_defaults_round_trip() -> void:
	var s := VantaSettings.default_settings()
	var restored: Variant = VantaSettings.from_dict(s.to_dict())["settings"]
	assert_eq(restored.dpi, s.dpi, "dpi survives a round trip")
	assert_eq(restored.sensitivity, s.sensitivity, "sensitivity survives a round trip")
	assert_eq(restored.orientation, s.orientation, "orientation survives a round trip")
	assert_eq(restored.crosshair.length, s.crosshair.length, "crosshair survives a round trip")


func test_schema_version_is_written() -> void:
	var data := VantaSettings.default_settings().to_dict()
	assert_eq(data["schema_version"], VantaSettings.SCHEMA_VERSION, "schema version present")


func test_garbage_root_is_replaced_by_defaults() -> void:
	var result: Dictionary = VantaSettings.from_dict("not a dictionary")
	assert_not_null(result["settings"], "settings object always produced")
	assert_greater(float(result["repairs"].size()), 0.0, "the repair is reported")


func test_out_of_range_values_are_clamped() -> void:
	var data := {
		"mouse": {"dpi": 999999, "sensitivity": -50.0, "vertical_scale": 500.0},
		"display": {"resolution": [999999, 1], "ui_scale": 99.0, "msaa": 7},
		"audio": {"master": 12.0},
	}
	var s: VantaSettings = VantaSettings.from_dict(data)["settings"]
	assert_eq(s.dpi, VantaSensitivity.DPI_MAX, "dpi clamped to the maximum")
	assert_eq(s.sensitivity, VantaSensitivity.SENS_MIN, "sensitivity clamped to the minimum")
	assert_almost_eq(s.vertical_scale, 4.0, "vertical scale clamped")
	assert_eq(s.resolution.x, 7680, "resolution clamped")
	assert_almost_eq(s.ui_scale, 1.6, "ui scale clamped")
	assert_eq(s.msaa, 0, "invalid msaa falls back to disabled")
	assert_almost_eq(s.audio_master, 1.0, "volume clamped to 1.0")


func test_wrong_types_never_crash() -> void:
	var data := {
		"mouse": {"dpi": "eight hundred", "sensitivity": [], "invert_y": "yes"},
		"display": {"resolution": "1920x1080"},
		"identity": {"player_name": 12345},
	}
	var s: VantaSettings = VantaSettings.from_dict(data)["settings"]
	assert_eq(s.dpi, 800, "non-numeric dpi falls back to default")
	assert_eq(s.sensitivity, 2.0, "non-numeric sensitivity falls back to default")
	assert_true(s.invert_y, "truthy string is accepted for booleans")
	assert_eq(s.resolution, Vector2i(1920, 1080), "malformed resolution falls back to default")
	assert_eq(s.player_name, "12345", "non-string name is coerced")


func test_unknown_orientation_is_repaired() -> void:
	var data := {"identity": {"orientation": "professional_esports_mode"}}
	var result: Dictionary = VantaSettings.from_dict(data)
	var s: VantaSettings = result["settings"]
	assert_eq(s.orientation_id(), "raw", "unknown orientation falls back to RAW AIM")
	assert_greater(float(result["repairs"].size()), 0.0, "repair reported for the orientation")


func test_player_name_is_bounded() -> void:
	var data := {"identity": {"player_name": "x".repeat(200)}}
	var s: VantaSettings = VantaSettings.from_dict(data)["settings"]
	assert_less(float(s.player_name.length()), 25.0, "player name truncated to 24 characters")


func test_unknown_keys_are_ignored() -> void:
	var data := VantaSettings.default_settings().to_dict()
	data["future_section"] = {"something": true}
	data["mouse"]["hyperspace_mode"] = 1
	var result: Dictionary = VantaSettings.from_dict(data)
	assert_not_null(result["settings"], "a file from a newer build still loads")


func test_high_contrast_forces_safe_palette() -> void:
	var data := {"accessibility": {"high_contrast": true, "color_vision_palette": false}}
	var s: VantaSettings = VantaSettings.from_dict(data)["settings"]
	assert_true(s.color_vision_palette, "high contrast implies the colour-vision-safe palette")


func test_duplicate_is_independent() -> void:
	var original := VantaSettings.default_settings()
	var copy := original.duplicate_settings()
	copy.sensitivity = 9.9
	assert_not_eq(original.sensitivity, copy.sensitivity, "duplicate does not alias the original")
	assert_not_eq(copy.crosshair, original.crosshair, "crosshair is duplicated too")


func test_crosshair_repairs_are_surfaced() -> void:
	var data := VantaSettings.default_settings().to_dict()
	data["crosshair"] = {"style": "hexagon", "length": 9999, "color": [255, 0, 128]}
	var result: Dictionary = VantaSettings.from_dict(data)
	var s: VantaSettings = result["settings"]
	assert_eq(s.crosshair.style_id(), "cross", "unknown crosshair style falls back to CROSS")
	assert_eq(s.crosshair.length, VantaCrosshair.LENGTH_MAX, "crosshair length clamped")
	assert_almost_eq(s.crosshair.color.r, 1.0, "0-255 colour values are rescaled", 0.001)
	var joined := "\n".join(result["repairs"])
	assert_string_contains(joined, "crosshair", "crosshair repairs are reported to the user")


func test_rank_presets_are_ordered() -> void:
	var ids := RenderPresets.labels()
	assert_eq(ids.size(), 3, "three render presets exist")
	assert_eq(ids[0], "COMPETITIVE", "competitive is listed first")
	assert_eq(RenderPresets.by_id("competitive")["motion_blur"], false, "motion blur is never enabled")
	assert_eq(RenderPresets.by_id("competitive")["dof"], false, "depth of field is never enabled")
