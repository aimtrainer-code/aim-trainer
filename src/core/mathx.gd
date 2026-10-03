class_name MathX
extends RefCounted

## Pure math helpers used by the simulation, the input layer and the tests.
##
## Everything here is static, allocation-free and frame-rate independent so it can
## be reasoned about (and unit-tested) without a running scene tree.

const DEG_TO_RAD: float = PI / 180.0
const RAD_TO_DEG: float = 180.0 / PI

## Screen-space is measured in "counts" (what the OS reports for mouse movement).
## One count rotates the view by `yaw` degrees, where yaw is derived from the
## user's sensitivity: yaw_deg_per_count = 360 / (cm360 * dpi / 2.54) ... see
## src/input/sensitivity.gd for the user-facing math.

const EPSILON: float = 1e-6


static func clampf_safe(value: float, min_value: float, max_value: float) -> float:
	if is_nan(value):
		return min_value
	return clampf(value, min_value, max_value)


## Exponential smoothing that is stable regardless of frame time.
static func damp(current: float, target: float, smoothing: float, delta: float) -> float:
	if smoothing <= 0.0:
		return target
	return lerpf(current, target, 1.0 - exp(-delta / smoothing))


static func wrap_degrees(degrees: float) -> float:
	var d := fmod(degrees, 360.0)
	if d < 0.0:
		d += 360.0
	return d


## Signed shortest delta between two yaw angles in degrees, in [-180, 180).
static func yaw_delta_degrees(from_yaw: float, to_yaw: float) -> float:
	var d := wrap_degrees(to_yaw - from_yaw)
	if d >= 180.0:
		d -= 360.0
	return d


## Direction vector for yaw/pitch in degrees. Yaw 0 looks down -Z (Godot forward),
## positive pitch looks up, matching Camera3D's rotation order (YXZ).
static func direction_from_angles(yaw_degrees: float, pitch_degrees: float) -> Vector3:
	var yaw := yaw_degrees * DEG_TO_RAD
	var pitch := pitch_degrees * DEG_TO_RAD
	var cos_pitch := cos(pitch)
	return Vector3(-sin(yaw) * cos_pitch, sin(pitch), -cos(yaw) * cos_pitch).normalized()


static func angles_from_direction(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	var pitch := asin(clampf(d.y, -1.0, 1.0)) * RAD_TO_DEG
	var yaw := atan2(-d.x, -d.z) * RAD_TO_DEG
	return Vector2(yaw, pitch)


## Angular distance in degrees between two directions. Used by flick/tracking
## analysis (e.g. "how far did the crosshair move between two shots").
static func angle_between(a: Vector3, b: Vector3) -> float:
	var na := a.normalized()
	var nb := b.normalized()
	var dot := clampf(na.dot(nb), -1.0, 1.0)
	return acos(dot) * RAD_TO_DEG


## Horizontal-only angular distance in degrees, ignoring pitch.
static func yaw_distance_degrees(a: Vector3, b: Vector3) -> float:
	var pa := angles_from_direction(a)
	var pb := angles_from_direction(b)
	return absf(yaw_delta_degrees(pa.x, pb.x))


## Converts an on-screen pixel offset at a given FOV into a world direction,
## using the standard pinhole model. `viewport_size` and `fov_degrees` describe
## the *vertical* FOV, matching Godot's Camera3D default (keep_aspect = HEIGHT).
static func screen_offset_to_direction(offset: Vector2, viewport_size: Vector2, fov_degrees: float, yaw: float, pitch: float) -> Vector3:
	var base := direction_from_angles(yaw, pitch)
	if viewport_size.y <= 0.0 or fov_degrees <= 0.0:
		return base
	var focal: float = (viewport_size.y * 0.5) / tan(deg_to_rad(fov_degrees * 0.5))
	var right := Vector3(cos(yaw * DEG_TO_RAD), 0.0, -sin(yaw * DEG_TO_RAD))
	var up := base.cross(right).normalized()
	var world := base * focal + right * offset.x - up * offset.y
	return world.normalized()


## Ray/sphere intersection. Returns the entry distance or -1.0 when there is no
## hit in front of the ray. `ray_dir` must be normalized.
static func ray_sphere(origin: Vector3, ray_dir: Vector3, center: Vector3, radius: float) -> float:
	var m := origin - center
	var b: float = m.dot(ray_dir)
	var c: float = m.dot(m) - radius * radius
	if c > 0.0 and b > 0.0:
		return -1.0
	var discr: float = b * b - c
	if discr < 0.0:
		return -1.0
	var sqrt_d := sqrt(discr)
	var t: float = -b - sqrt_d
	if t < 0.0:
		t = -b + sqrt_d
	if t < 0.0:
		return -1.0
	return t


## Ray/AABB (slab method). Returns entry distance or -1.0. Axis-aligned boxes are
## used for cover geometry and for box-shaped target regions.
static func ray_aabb(origin: Vector3, ray_dir: Vector3, box_position: Vector3, box_size: Vector3) -> float:
	var inv := Vector3(
		1.0 / (ray_dir.x if absf(ray_dir.x) > EPSILON else (EPSILON * signf(ray_dir.x) if ray_dir.x != 0.0 else EPSILON)),
		1.0 / (ray_dir.y if absf(ray_dir.y) > EPSILON else (EPSILON * signf(ray_dir.y) if ray_dir.y != 0.0 else EPSILON)),
		1.0 / (ray_dir.z if absf(ray_dir.z) > EPSILON else (EPSILON * signf(ray_dir.z) if ray_dir.z != 0.0 else EPSILON))
	)
	var half := box_size * 0.5
	var t1 := (box_position - half - origin) * inv
	var t2 := (box_position + half - origin) * inv
	var tmin: float = maxf(maxf(minf(t1.x, t2.x), minf(t1.y, t2.y)), minf(t1.z, t2.z))
	var tmax: float = minf(minf(maxf(t1.x, t2.x), maxf(t1.y, t2.y)), maxf(t1.z, t2.z))
	if tmax < 0.0 or tmin > tmax:
		return -1.0
	return tmin if tmin >= 0.0 else tmax


## Ray/oriented-box. `basis` columns are the box's local axes (need not be
## orthonormal in general, but must be for exact results).
static func ray_obb(origin: Vector3, ray_dir: Vector3, center: Vector3, basis: Basis, half_size: Vector3) -> float:
	var inv_basis := basis.inverse()
	var local_origin := inv_basis * (origin - center)
	var local_dir := inv_basis * ray_dir
	return ray_aabb(local_origin, local_dir, Vector3.ZERO, half_size * 2.0)


## Ray/capsule (used for the limbs of training dummies, where a cylinder is a
## better silhouette than a box). Returns the entry distance or -1.0.
##
## Uses the standard segment-parameterised quadric for the cylindrical body, with
## exact rejection of cap hits: a ray can enter the sphere that caps the cylinder
## without touching the capsule (passing below/above the cap plane), so a cap hit
## is only accepted when its projection lies outside the segment.
static func ray_capsule(origin: Vector3, ray_dir: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var ba := b - a
	var oa := origin - a
	var baba := ba.dot(ba)
	if baba < EPSILON:
		return ray_sphere(origin, ray_dir, a, radius)

	var bard: float = ba.dot(ray_dir)
	var baoa: float = ba.dot(oa)
	var rdoa: float = ray_dir.dot(oa)
	var oaoa: float = oa.dot(oa)

	var best := -1.0
	var quad_a: float = baba - bard * bard
	var quad_b: float = baba * rdoa - baoa * bard
	var quad_c: float = baba * oaoa - baoa * baoa - radius * radius * baba
	var discriminant: float = quad_b * quad_b - quad_a * quad_c
	if discriminant >= 0.0 and absf(quad_a) > EPSILON:
		var sqrt_d := sqrt(discriminant)
		for root in [(-quad_b - sqrt_d) / quad_a, (-quad_b + sqrt_d) / quad_a]:
			var t: float = root
			if t < 0.0:
				continue
			var y: float = baoa + t * bard
			if y > 0.0 and y < baba:
				best = t if best < 0.0 else minf(best, t)

	# Caps. `ray_sphere` already rejects hits behind the origin.
	var cap_a := ray_sphere(origin, ray_dir, a, radius)
	if cap_a >= 0.0 and (origin + ray_dir * cap_a - a).dot(ba) <= 0.0:
		best = cap_a if best < 0.0 else minf(best, cap_a)
	var cap_b := ray_sphere(origin, ray_dir, b, radius)
	if cap_b >= 0.0 and (origin + ray_dir * cap_b - b).dot(ba) >= 0.0:
		best = cap_b if best < 0.0 else minf(best, cap_b)
	return best


## Distance from a point to a line segment.
static func point_segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < EPSILON:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func smoothstep01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Maps a value in [in_min, in_max] to [0, 1] with clamping.
static func inverse_lerp_clamped(in_min: float, in_max: float, value: float) -> float:
	if is_equal_approx(in_min, in_max):
		return 0.0
	return clampf((value - in_min) / (in_max - in_min), 0.0, 1.0)


## Rounds to a fixed number of decimals without string conversions.
static func round_to(value: float, decimals: int) -> float:
	var factor := pow(10.0, float(decimals))
	return roundf(value * factor) / factor


## Percentage helper that never divides by zero: returns 0.0 when `total <= 0`.
static func percent(part: float, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return (part / total) * 100.0


## Formats seconds as MM:SS (used by the HUD and the training plan).
static func format_clock(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	return "%02d:%02d" % [s / 60, s % 60]


## Formats seconds as "Hh MMm" for long-term totals (Zero to Elite).
static func format_duration(seconds: float) -> String:
	var total := maxi(0, int(round(seconds)))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm %02ds" % [minutes, total % 60]


## Snaps a value to a step (used by sliders that must produce stable numbers).
static func snap(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return roundf(value / step) * step
