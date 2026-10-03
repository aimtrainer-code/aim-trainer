class_name HitRegion
extends RefCounted

## One hit-testable primitive of a target, in target-local space.
##
## Hit registration is analytic (ray against primitives) rather than physics-based.
## For an aim trainer that is the correct trade:
##  - it is exactly reproducible, which is what a benchmark and a regression test need;
##  - it costs no physics-server time, so 8 kHz mice and 480 Hz displays are not
##    competing with a broadphase for CPU;
##  - the same primitive list drives both the hit test and the mesh generation, so
##    the visual silhouette and the hittable silhouette cannot drift apart.
##
## Regions map onto the three-zone humanoid model (head / torso / legs) and onto the
## simple shapes used by clicking drills.

enum Kind { SPHERE, CAPSULE, BOX, DISC }

## Region identifiers. The string form is what scenarios and scoring rules use.
const HEAD: String = "head"
const TORSO: String = "torso"
const LEGS: String = "legs"
const BODY: String = "body"

var id: String = BODY
var kind: int = Kind.SPHERE
## Primitive parameters, local to the target's origin.
var center: Vector3 = Vector3.ZERO
var radius: float = 0.5
var half_size: Vector3 = Vector3(0.5, 0.5, 0.5)
var capsule_a: Vector3 = Vector3.ZERO
var capsule_b: Vector3 = Vector3(0.0, 1.0, 0.0)
## For DISC: the disc's facing direction in local space (a coin has two faces).
var normal: Vector3 = Vector3(0, 0, 1)
var thickness: float = 0.05

## Damage multiplier applied when this region is hit. 0 makes the region inert.
var damage_multiplier: float = 1.0
## Marks the region as a headshot for scoring and statistics.
var is_headshot: bool = false


static func sphere(region_id: String, center_local: Vector3, radius_value: float, multiplier: float = 1.0, headshot: bool = false) -> HitRegion:
	var region := HitRegion.new()
	region.id = region_id
	region.kind = Kind.SPHERE
	region.center = center_local
	region.radius = radius_value
	region.damage_multiplier = multiplier
	region.is_headshot = headshot
	return region


static func capsule(region_id: String, a: Vector3, b: Vector3, radius_value: float, multiplier: float = 1.0) -> HitRegion:
	var region := HitRegion.new()
	region.id = region_id
	region.kind = Kind.CAPSULE
	region.capsule_a = a
	region.capsule_b = b
	region.radius = radius_value
	region.damage_multiplier = multiplier
	return region


static func box(region_id: String, center_local: Vector3, size: Vector3, multiplier: float = 1.0) -> HitRegion:
	var region := HitRegion.new()
	region.id = region_id
	region.kind = Kind.BOX
	region.center = center_local
	region.half_size = size * 0.5
	region.damage_multiplier = multiplier
	return region


static func disc(region_id: String, center_local: Vector3, facing: Vector3, radius_value: float, thickness_value: float, multiplier: float = 1.0) -> HitRegion:
	var region := HitRegion.new()
	region.id = region_id
	region.kind = Kind.DISC
	region.center = center_local
	region.normal = facing.normalized()
	region.radius = radius_value
	region.thickness = thickness_value
	region.damage_multiplier = multiplier
	return region


## Intersects a world-space ray with this region, given the target's world transform.
## Returns the entry distance, or -1.0 when the region is not hit.
func intersect(origin: Vector3, direction: Vector3, target_origin: Vector3, target_basis: Basis) -> float:
	if damage_multiplier <= 0.0:
		return -1.0
	match kind:
		Kind.SPHERE:
			return MathX.ray_sphere(origin, direction, target_origin + target_basis * center, radius)
		Kind.CAPSULE:
			return MathX.ray_capsule(
				origin, direction,
				target_origin + target_basis * capsule_a,
				target_origin + target_basis * capsule_b,
				radius
			)
		Kind.BOX:
			return MathX.ray_obb(origin, direction, target_origin + target_basis * center, target_basis, half_size)
		Kind.DISC:
			return _intersect_disc(origin, direction, target_origin, target_basis)
	return -1.0


func _intersect_disc(origin: Vector3, direction: Vector3, target_origin: Vector3, target_basis: Basis) -> float:
	# A disc is a thin coin: the cylindrical rim plus the two flat faces.
	var world_normal := (target_basis * normal).normalized()
	var world_center := target_origin + target_basis * center
	var denominator := direction.dot(world_normal)
	var best := -1.0
	if absf(denominator) > MathX.EPSILON:
		var t := (world_center - origin).dot(world_normal) / denominator
		if t >= 0.0:
			var point := origin + direction * t
			if point.distance_to(world_center) <= radius:
				best = t
	if best < 0.0:
		# Edge-on shots: fall back to the rim so a disc never becomes unhittable.
		var rim := MathX.ray_capsule(origin, direction, world_center - world_normal * thickness * 0.5, world_center + world_normal * thickness * 0.5, radius)
		if rim >= 0.0:
			best = rim
	return best


func to_dict() -> Dictionary:
	var kind_names := ["sphere", "capsule", "box", "disc"]
	return {
		"id": id,
		"kind": kind_names[clampi(kind, 0, kind_names.size() - 1)],
		"center": [center.x, center.y, center.z],
		"radius": radius,
		"damage_multiplier": damage_multiplier,
		"is_headshot": is_headshot,
	}
