extends VantaTestCase

## Sensitivity is the number a competitive player trusts most, so it is pinned with
## known-good reference values rather than with round numbers VANTA itself invented.
##
## Reference: 800 DPI at sensitivity 2.0 with the Source coefficient (0.022°/count)
## is one of the most common CS setups and corresponds to ≈ 26.0 cm/360.


func test_source_reference_value() -> void:
	var summary := VantaSensitivity.summary(800, 2.0)
	assert_almost_eq(summary["cm_per_360"], 25.96, "800 DPI / sens 2 ≈ 25.96 cm/360", 0.05)


func test_counts_per_360() -> void:
	assert_almost_eq(VantaSensitivity.counts_per_360(1.0, 0.022), 16363.636, "counts per 360 at sens 1", 0.5)


func test_cm360_round_trip() -> void:
	for dpi in [400, 800, 1600, 3200]:
		for cm in [15.0, 25.96, 40.0, 60.5]:
			var sens := VantaSensitivity.sensitivity_for_cm_per_360(dpi, cm)
			var back := VantaSensitivity.cm_per_360(dpi, sens)
			assert_almost_eq(back, cm, "cm/360 round trip at %d DPI" % dpi, 0.01)


func test_yaw_per_count_scales_linearly() -> void:
	assert_almost_eq(VantaSensitivity.yaw_per_count(0.5), 0.011, "half sensitivity halves the coefficient", 1e-6)
	assert_almost_eq(VantaSensitivity.yaw_per_count(4.0), 0.088, "double sensitivity doubles the coefficient", 1e-6)


func test_rotation_for_delta_sign_conventions() -> void:
	# Moving the mouse right must turn the view right (yaw increases), which in
	# Godot's coordinate system is a negative yaw delta on the rig.
	var delta := Vector2(10.0, 0.0)
	var rotation := VantaSensitivity.rotation_for_delta(delta, 0.022, 1.0, false)
	assert_almost_eq(rotation.x, -0.22, "mouse right decreases yaw", 1e-6)
	assert_almost_eq(rotation.y, 0.0, "no pitch from horizontal motion", 1e-6)


func test_rotation_vertical_and_inversion() -> void:
	# Positive pitch means looking up, so moving the mouse down (screen +Y) must
	# produce a negative pitch delta unless the player asked for inverted aim.
	var down := Vector2(0.0, 10.0)
	var normal := VantaSensitivity.rotation_for_delta(down, 0.022, 1.0, false)
	assert_almost_eq(normal.y, -0.22, "mouse down looks down by default", 1e-6)
	var inverted := VantaSensitivity.rotation_for_delta(down, 0.022, 1.0, true)
	assert_almost_eq(inverted.y, 0.22, "invert_y flips the pitch sign", 1e-6)


func test_vertical_scale_applies_only_to_pitch() -> void:
	var r := VantaSensitivity.rotation_for_delta(Vector2(10.0, 10.0), 0.022, 0.5, false)
	assert_almost_eq(r.x, -0.22, "vertical scale must not touch yaw", 1e-6)
	assert_almost_eq(r.y, -0.11, "vertical scale halves pitch", 1e-6)


func test_profile_conversion_is_lossless() -> void:
	# A source-style sens of 2.0 must become the tactical//val-style sens that produces
	# the same cm/360, and converting back must return the original number.
	var tactical := VantaSensitivity.convert_sensitivity(2.0, "source", "tactical_val")
	assert_almost_eq(tactical, 2.0 * 0.022 / 0.07, "source→tactical_val conversion", 1e-6)
	var back := VantaSensitivity.convert_sensitivity(tactical, "tactical_val", "source")
	assert_almost_eq(back, 2.0, "conversion round trip", 1e-6)


func test_profile_metadata_is_complete() -> void:
	assert_eq(VantaSensitivity.PROFILE_IDS.size(), 3, "three calibration profiles ship")
	for id in VantaSensitivity.PROFILE_IDS:
		var entry := VantaSensitivity.profile(id)
		assert_eq(String(entry["id"]), String(id), "profile '%s' reports its own id" % id)
		assert_greater(String(entry["label"]).length(), 10.0, "profile '%s' has a descriptive label" % id)
		assert_greater(float(entry["yaw_coefficient"]), 0.0, "profile '%s' has a positive coefficient" % id)
	# The two coefficients VANTA can state a source for. The VANTA profile deliberately
	# reuses the Source coefficient rather than inventing a third calibration.
	assert_almost_eq(float(VantaSensitivity.profile("source")["yaw_coefficient"]), VantaSensitivity.YAW_COEFFICIENT_SOURCE, "source coefficient", 1e-9)
	assert_almost_eq(float(VantaSensitivity.profile("tactical_val")["yaw_coefficient"]), VantaSensitivity.YAW_COEFFICIENT_TACTICAL_VAL, "tactical_val coefficient", 1e-9)
	assert_almost_eq(float(VantaSensitivity.profile("vanta")["yaw_coefficient"]), VantaSensitivity.YAW_COEFFICIENT_SOURCE, "vanta coefficient", 1e-9)
	assert_eq(VantaSensitivity.convert_sensitivity(2.0, "vanta", "source"), 2.0, "vanta and source are the same calibration")


func test_zoom_multiplier() -> void:
	# Monitor-distance matching: a 90°→45° zoom halves the field of view, so the
	# effective sensitivity is scaled by tan(22.5°)/tan(45°) ≈ 0.414 to keep the
	# on-screen distance covered by a mouse movement the same as at hip fire.
	assert_almost_eq(VantaSensitivity.zoom_multiplier(90.0, 45.0), 0.4142, "90→45 zoom multiplier", 0.001)
	assert_almost_eq(VantaSensitivity.zoom_multiplier(90.0, 90.0), 1.0, "no zoom means no change", 1e-6)
	assert_almost_eq(VantaSensitivity.zoom_multiplier(45.0, 90.0), 1.0 / 0.4142, "45→90 is the inverse scaling", 0.01)


func test_validation_bounds() -> void:
	assert_false(VantaSensitivity.validate(0, 2.0)["ok"], "DPI 0 rejected")
	assert_false(VantaSensitivity.validate(800, 0.0)["ok"], "sensitivity 0 rejected")
	assert_false(VantaSensitivity.validate(800, 1000.0)["ok"], "absurd sensitivity rejected")
	assert_true(VantaSensitivity.validate(800, 2.0)["ok"], "typical setup accepted")


func test_unknown_profile_falls_back_to_vanta() -> void:
	# A settings file written by a build with a different profile list must still load
	# with a stated coefficient rather than silently becoming a different calibration.
	var profile := VantaSensitivity.profile("some_other_game")
	assert_eq(profile["id"], "vanta", "unknown profile id falls back to the VANTA profile")
	assert_almost_eq(float(profile["yaw_coefficient"]), VantaSensitivity.YAW_COEFFICIENT_SOURCE, "the fallback coefficient is VANTA's own", 1e-9)


func test_degenerate_inputs_do_not_produce_nan() -> void:
	assert_false(is_nan(VantaSensitivity.cm_per_360(0, 2.0)), "0 DPI does not produce NaN")
	assert_false(is_nan(VantaSensitivity.yaw_per_count(-1.0)), "negative sensitivity does not produce NaN")
	assert_true(is_inf(VantaSensitivity.cm_per_360(0, 2.0)), "0 DPI reports infinity instead of a wrong number")
