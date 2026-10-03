extends VantaTestCase

## Covers the analytic math the hit registration depends on. These tests are the
## reason VANTA can claim "hit registration is verified" for the geometry layer:
## the ray tests are exercised directly, deterministically, without a scene tree.

const EPS := 0.001


func test_direction_round_trip() -> void:
	var angles := [Vector2(0.0, 0.0), Vector2(90.0, 0.0), Vector2(-45.0, 30.0), Vector2(179.0, -60.0)]
	for a in angles:
		var dir := MathX.direction_from_angles(a.x, a.y)
		var back := MathX.angles_from_direction(dir)
		var yaw_delta := absf(MathX.yaw_delta_degrees(a.x, back.x))
		assert_less(yaw_delta, EPS, "yaw round trip for %s" % str(a))
		assert_almost_eq(back.y, a.y, "pitch round trip for %s" % str(a), EPS)


func test_yaw_delta_wraps_correctly() -> void:
	assert_almost_eq(MathX.yaw_delta_degrees(350.0, 10.0), 20.0, "wrap forward", EPS)
	assert_almost_eq(MathX.yaw_delta_degrees(10.0, 350.0), -20.0, "wrap backward", EPS)
	assert_almost_eq(MathX.yaw_delta_degrees(0.0, 180.0), -180.0, "exact half turn is negative", EPS)


func test_angle_between() -> void:
	var a := Vector3(0, 0, -1)
	var b := Vector3(0, 0, 1)
	assert_almost_eq(MathX.angle_between(a, b), 180.0, "opposite directions", EPS)
	var c := Vector3(1, 0, 0)
	assert_almost_eq(MathX.angle_between(Vector3(0, 0, -1), c), 90.0, "perpendicular", EPS)


func test_ray_sphere_hit_and_miss() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	# Direct hit at distance 10 on a 0.5 radius sphere centred on the ray.
	var t := MathX.ray_sphere(origin, forward, Vector3(0, 0, -10), 0.5)
	assert_almost_eq(t, 9.5, "direct hit distance", EPS)
	# Sphere behind the ray must not hit.
	assert_eq(MathX.ray_sphere(origin, forward, Vector3(0, 0, 10), 0.5), -1.0, "sphere behind ray is not hit")
	# Offset beyond the radius must miss.
	assert_eq(MathX.ray_sphere(origin, forward, Vector3(1.0, 0, -10), 0.5), -1.0, "sphere off axis is not hit")
	# Origin inside the sphere returns the exit distance, not a negative value.
	var inside := MathX.ray_sphere(Vector3(0, 0, -10), forward, Vector3(0, 0, -10), 0.5)
	assert_greater(inside, 0.0, "origin inside sphere returns positive distance")


func test_ray_sphere_from_inside_is_exit_distance() -> void:
	# This matters for headshots resolved from inside a target after a teleport; it
	# must never return a negative distance that would be treated as "no hit".
	var t := MathX.ray_sphere(Vector3(0, 0, -9.9), Vector3(0, 0, -1), Vector3(0, 0, -10), 0.5)
	assert_greater(t, 0.0, "exit distance is positive")


func test_ray_aabb() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var box_pos := Vector3(0, 0, -5)
	var box_size := Vector3(2, 2, 2)
	var t := MathX.ray_aabb(origin, forward, box_pos, box_size)
	assert_almost_eq(t, 4.0, "box front face at 4 m", EPS)
	assert_eq(MathX.ray_aabb(origin, forward, Vector3(3, 0, -5), box_size), -1.0, "box outside the ray")
	# A ray parallel to a face must not produce NaN.
	var parallel := MathX.ray_aabb(Vector3(0, 3, 0), forward, box_pos, box_size)
	assert_eq(parallel, -1.0, "parallel ray above the box misses")


func test_ray_aabb_axis_parallel_does_not_divide_by_zero() -> void:
	# Regression guard: the slab method divides by the direction component. An
	# unmasked division by zero would produce inf/NaN and a phantom hit.
	var origin := Vector3(-5, 0, 0)
	var dir := Vector3(1, 0, 0)
	var t := MathX.ray_aabb(origin, dir, Vector3(0, 0, 0), Vector3(1, 1, 1))
	assert_almost_eq(t, 4.5, "axis-parallel hit", EPS)
	assert_true(not is_nan(t), "distance is a real number")


func test_ray_obb_rotated() -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(45.0))
	var origin := Vector3(0, 0, 5)
	var dir := Vector3(0, 0, -1)
	var t := MathX.ray_obb(origin, dir, Vector3.ZERO, basis, Vector3(1, 1, 0.5))
	assert_greater(t, 0.0, "rotated box is hit")
	# The same box rotated must be hit at a different distance than its AABB.
	var t_aabb := MathX.ray_aabb(origin, dir, Vector3.ZERO, Vector3(2, 2, 1))
	assert_not_eq(snappedf(t, 0.01), snappedf(t_aabb, 0.01), "obb differs from aabb for a rotated box")


func test_ray_capsule_body_and_caps() -> void:
	var a := Vector3(0, 0, -5)
	var b := Vector3(0, 2, -5)
	var t := MathX.ray_capsule(Vector3(0, 1, 0), Vector3(0, 0, -1), a, b, 0.25)
	assert_almost_eq(t, 4.75, "capsule body hit", 0.01)
	# Above the top cap: must still hit the spherical cap.
	var t_cap := MathX.ray_capsule(Vector3(0, 2.2, 0), Vector3(0, 0, -1), a, b, 0.25)
	assert_greater(t_cap, 0.0, "capsule cap hit")
	# Far to the side: no hit.
	assert_eq(MathX.ray_capsule(Vector3(2, 1, 0), Vector3(0, 0, -1), a, b, 0.25), -1.0, "capsule miss")


func test_point_segment_distance() -> void:
	assert_almost_eq(MathX.point_segment_distance(Vector3(0, 0, 0), Vector3(-1, 0, 0), Vector3(1, 0, 0)), 0.0, "on the segment", EPS)
	assert_almost_eq(MathX.point_segment_distance(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(1, 0, 0)), 1.0, "perpendicular", EPS)
	assert_almost_eq(MathX.point_segment_distance(Vector3(3, 0, 0), Vector3(-1, 0, 0), Vector3(1, 0, 0)), 2.0, "beyond the end", EPS)


func test_formatting_helpers() -> void:
	assert_eq(MathX.format_clock(0.0), "00:00", "zero clock")
	assert_eq(MathX.format_clock(65.0), "01:05", "minute rollover")
	assert_eq(MathX.format_clock(3599.0), "59:59", "just below an hour")
	assert_eq(MathX.format_duration(3600.0), "1h 00m", "one hour")
	assert_eq(MathX.format_duration(45.0), "0m 45s", "under a minute")


func test_damp_is_frame_rate_independent() -> void:
	# Smoothing 100 ms applied as 10 × 10 ms steps must land close to one 100 ms step.
	var one_step := MathX.damp(0.0, 1.0, 0.1, 0.1)
	var many := 0.0
	for i in 10:
		many = MathX.damp(many, 1.0, 0.1, 0.01)
	assert_almost_eq(many, one_step, "damp is frame-rate independent", 0.001)


func test_screen_offset_to_direction_center_is_forward() -> void:
	var dir := MathX.screen_offset_to_direction(Vector2.ZERO, Vector2(1920, 1080), 90.0, 0.0, 0.0)
	assert_almost_eq(Vector3(0, 0, -1).angle_to(dir), 0.0, "centre of the screen looks forward", EPS)
	# Half the screen height at 90° vertical FOV is exactly 45° off centre.
	var edge := MathX.screen_offset_to_direction(Vector2(0, 540), Vector2(1920, 1080), 90.0, 0.0, 0.0)
	assert_almost_eq(Vector3(0, 0, -1).angle_to(edge) * MathX.RAD_TO_DEG, 45.0, "half-height is 45 degrees", 0.01)
