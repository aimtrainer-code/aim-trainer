extends VantaTestCase

## Weapon runtime tests.
##
## These check the properties that make aim training meaningful rather than the exact
## numbers: that the first shot is the accurate one, that sustained fire grows the cone
## of fire, that the cone recovers only after a pause, that ammunition and reloading
## behave, and that the whole thing is reproducible from a seed.

func _weapon_data(overrides: Dictionary = {}) -> Dictionary:
	var data := {
		"id": "test_rifle",
		"archetype": "tactical_rifle",
		"fire_rate_rpm": 600.0,
		"damage": 30.0,
		"spread_base_deg": 0.1,
		"spread_per_shot_deg": 0.2,
		"spread_max_deg": 3.0,
		"spread_recovery_deg_per_second": 4.0,
		"recoil_vertical_deg": 0.5,
		"recoil_horizontal_deg": 0.2,
		"recoil_recovery_deg_per_second": 12.0,
		"magazine": 5,
		"reload_seconds": 1.0,
	}
	for key in overrides.keys():
		data[key] = overrides[key]
	return data


func _make_runtime(overrides: Dictionary = {}, seed_value: int = 7) -> WeaponRuntime:
	var parsed := WeaponDefinition.from_dict(_weapon_data(overrides))
	assert_eq((parsed["errors"] as Array).size(), 0, "the test weapon is valid")
	var runtime := WeaponRuntime.new(parsed["weapon"], VantaRng.new(seed_value))
	return runtime


func _state(moving: float = 0.0, airborne: bool = false, aiming: bool = false) -> WeaponRuntime.State:
	var state := WeaponRuntime.State.new()
	state.moving_speed = moving
	state.airborne = airborne
	state.aiming = aiming
	return state


func test_fire_rate_is_enforced() -> void:
	var runtime := _make_runtime({"fire_rate_rpm": 600.0})
	var state := _state()
	assert_eq(runtime.ammo, 5, "the magazine starts full")
	var first := runtime.fire(0.0, state)
	assert_false(first.is_empty(), "the first shot is accepted")
	assert_true(runtime.can_fire(0.05) == false, "a shot 50 ms later is refused at 600 rpm")
	assert_eq(String(runtime.blocked_reason()), "fire_rate", "the refusal names the fire rate")
	var second := runtime.fire(runtime.definition.shot_interval(), state)
	assert_false(second.is_empty(), "a shot after one interval is accepted")
	assert_eq(runtime.ammo, 3, "two shots consumed two rounds")


func test_magazine_and_reload() -> void:
	var runtime := _make_runtime({"magazine": 2, "reload_seconds": 1.0})
	var state := _state()
	var now := 0.0
	for i in 2:
		runtime.fire(now, state)
		now += runtime.definition.shot_interval()
	assert_true(runtime.is_magazine_empty(), "the magazine is empty after two shots")
	assert_false(runtime.can_fire(now), "an empty weapon cannot fire")
	assert_true(runtime.start_reload(), "reloading starts")
	assert_false(runtime.start_reload(), "reloading twice does nothing")
	runtime.step(0.5, state)
	assert_true(runtime.reloading, "the reload is still in progress halfway")
	runtime.step(0.6, state)
	assert_false(runtime.reloading, "the reload finished")
	assert_eq(runtime.ammo, 2, "the magazine is full again")


func test_first_shot_is_the_accurate_one() -> void:
	var runtime := _make_runtime()
	var state := _state()
	var first := runtime.fire(0.0, state)
	assert_true(bool(first["first_shot"]), "the first shot of a burst is flagged as the first shot")
	assert_less(float(first["spread_deg"]), runtime.definition.spread_base_deg, "the first shot uses the reduced first-shot spread")
	runtime.register_shot()
	var second := runtime.fire(runtime.definition.shot_interval(), state)
	assert_false(bool(second["first_shot"]), "the second shot is not the first shot")
	assert_greater(float(second["spread_deg"]), float(first["spread_deg"]), "the cone of fire grew after a shot")


func test_sustained_fire_grows_and_pause_recovers_spread() -> void:
	var runtime := _make_runtime({"magazine": 30, "spread_max_deg": 2.0, "spread_per_shot_deg": 0.4})
	var state := _state()
	var now := 0.0
	for i in 10:
		if not runtime.fire(now, state).is_empty():
			runtime.register_shot()
		now += runtime.definition.shot_interval()
		runtime.step(runtime.definition.shot_interval(), state)
	var hot := runtime.current_spread(state)
	assert_greater(hot, runtime.definition.spread_base_deg * 2.0, "sustained fire produced a wide cone")
	# A short pause must not be enough: the recovery delay is derived from the weapon's
	# own cadence so that firing at the weapon's rate never fully recovers the cone.
	runtime.step(0.05, state)
	assert_greater(runtime.current_spread(state), hot * 0.9, "a 50 ms pause barely recovers the cone")
	for i in 60:
		runtime.step(0.05, state)
	assert_less(runtime.current_spread(state), hot, "a long pause recovers the cone")
	assert_less(runtime.current_spread(state), runtime.definition.spread_base_deg + 0.01, "the cone returns to its base value")


func test_movement_and_airborne_inaccuracy_stack() -> void:
	var runtime := _make_runtime({"ads_enabled": true})
	var still := _state(0.0, false, false)
	var moving := _state(3.0, false, false)
	var airborne := _state(3.0, true, false)
	var ads := _state(3.0, false, true)
	assert_greater(runtime.current_spread(moving), runtime.current_spread(still), "moving is less accurate than standing still")
	assert_greater(runtime.current_spread(airborne), runtime.current_spread(moving), "airborne is less accurate than moving")
	assert_less(runtime.current_spread(ads), runtime.current_spread(moving), "aiming down sights tightens the cone")


func test_cone_sampling_is_uniform_by_area() -> void:
	# Sampling the radius uniformly would bias shots towards the centre and make the
	# weapon feel tighter than its stated spread. With r = half_angle * sqrt(u) the
	# expected squared radius is half_angle^2 / 2, which is what this measures.
	var runtime := _make_runtime({"spread_base_deg": 4.0, "spread_per_shot_deg": 0.0, "spread_max_deg": 4.0,
		"recoil_vertical_deg": 0.0, "recoil_horizontal_deg": 0.0, "magazine": 500, "reload_seconds": 0.0})
	var state := _state()
	var total := 0.0
	var accepted := 0
	var samples := 400
	var now := 0.0
	var interval := runtime.definition.shot_interval()
	for i in samples:
		var shot := runtime.fire(now, state)
		if shot.is_empty():
			now += interval
			continue
		var offsets: Array[Vector2] = shot["spread_offsets_deg"]
		total += offsets[0].length_squared()
		accepted += 1
		now += interval
	assert_greater(float(accepted), float(samples) - 5.0, "nearly every sample was accepted")
	var mean := total / float(accepted)
	var expected := 4.0 * 4.0 / 2.0
	assert_between(mean, expected * 0.85, expected * 1.15, "the cone is sampled uniformly by area (mean r² = %.3f, expected %.3f)" % [mean, expected])


func test_shots_are_reproducible_from_a_seed() -> void:
	var first := _make_runtime({}, 99)
	var second := _make_runtime({}, 99)
	var state := _state()
	var now := 0.0
	for i in 12:
		var a := first.fire(now, state)
		var b := second.fire(now, state)
		if a.is_empty() or b.is_empty():
			break
		var offsets_a: Array[Vector2] = a["spread_offsets_deg"]
		var offsets_b: Array[Vector2] = b["spread_offsets_deg"]
		assert_eq(offsets_a[0].x, offsets_b[0].x, "shot %d has the same horizontal spread" % i)
		assert_eq(offsets_a[0].y, offsets_b[0].y, "shot %d has the same vertical spread" % i)
		first.register_shot()
		second.register_shot()
		now += first.definition.shot_interval()


func test_recoil_accumulates_and_recovers() -> void:
	var runtime := _make_runtime({"recoil_vertical_deg": 1.0, "recoil_pattern_ratio": 1.0, "recoil_growth": 1.0})
	var state := _state()
	var now := 0.0
	for i in 4:
		runtime.fire(now, state)
		now += runtime.definition.shot_interval()
	var climbed := runtime.recoil.y
	assert_greater(climbed, 3.0, "four shots climbed the view by more than three degrees (%.2f)" % climbed)
	for i in 40:
		runtime.step(0.05, state)
	assert_less(runtime.recoil.y, 0.01, "the recoil offset recovers to zero")
	assert_true(runtime.shots_fired == 4, "the weapon counted four shots")


func test_pellet_weapons_return_one_offset_per_pellet() -> void:
	var runtime := _make_runtime({"pellets": 5, "spread_base_deg": 2.0, "spread_per_shot_deg": 0.0})
	var shot := runtime.fire(0.0, _state())
	var offsets: Array[Vector2] = shot["spread_offsets_deg"]
	assert_eq(offsets.size(), 5, "a five-pellet weapon returns five offsets")
	var primary: Vector2 = shot["spread_offset_deg"]
	assert_almost_eq(offsets[0].x, primary.x, "the first pellet is also the shot's spread offset (x)", 0.0001)
	assert_almost_eq(offsets[0].y, primary.y, "the first pellet is also the shot's spread offset (y)", 0.0001)
	# Pellets must not be identical: independent draws from the same cone.
	assert_not_eq(offsets[0], offsets[1], "pellets are sampled independently")


func test_spread_pixels_uses_the_view_focal_length() -> void:
	var runtime := _make_runtime({"spread_base_deg": 1.0, "spread_per_shot_deg": 0.0, "spread_max_deg": 1.0})
	# At 90 degrees horizontal FOV and 1080 device pixels of height the focal length is
	# 540 / tan(45°) = 540 px, so 1° of spread is 540 * tan(1°) ≈ 9.4 px.
	var pixels := runtime.spread_pixels(1080.0, 90.0)
	assert_between(pixels, 9.0, 9.8, "one degree of spread is about 9.4 pixels at 1080p / 90 FOV (got %.2f)" % pixels)
