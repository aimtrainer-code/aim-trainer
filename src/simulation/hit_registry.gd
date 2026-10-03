class_name HitRegistry
extends RefCounted

## Analytic hit resolution.
##
## A shot is a ray. Resolving it means finding the nearest intersection with, in this
## order of priority:
##
##   1. arena cover (a wall always wins — you cannot shoot through a box)
##   2. target regions (head / torso / legs / body)
##
## The resolver is a pure function of the world state it is handed, which has three
## practical consequences the project relies on:
##
##   - **Determinism.** The same world state and the same ray always produce the same
##     result, so scenario seeds reproduce exactly and regression tests are possible.
##   - **No duplicate hits.** There is exactly one code path that can award a hit for
##     a shot, and it is driven by the single shot event, never by a physics callback
##     that might fire twice for one shot.
##   - **Cover is authoritative.** Because cover participates in the same nearest-hit
##     search as targets, "shooting through a wall" cannot happen by accident — it
##     would require cover geometry to be missing from the arena definition, which the
##     arena validator reports.

## Reason codes returned in the result dictionary.
const HIT_TARGET: String = "target"
const HIT_COVER: String = "cover"
const HIT_NOTHING: String = "nothing"
const HIT_OUT_OF_BOUNDS: String = "out_of_bounds"

## A ray that travels further than this is treated as a miss. 500 m is far beyond
## any arena VANTA ships, and it keeps a target placed at a silly distance from
## producing an absurd hit.
const MAX_RANGE: float = 500.0

## Cover volumes. These are oriented boxes, not AABBs: a ramp or an angled wall is
## exactly the geometry that makes crosshair placement interesting, and an
## axis-aligned approximation of a rotated wall can be hit by a shot that the rendered
## wall visually blocks. The box's `world_aabb()` is used only as a cheap broad-phase
## reject before the exact oriented test.
var _cover: Array[CoverBox] = []


func configure(cover_boxes: Array[CoverBox]) -> void:
	_cover = cover_boxes


func cover_count() -> int:
	return _cover.size()


## Resolves a shot.
##
## Returns:
##   {
##     result: "target" | "cover" | "nothing",
##     distance: float,
##     target: TargetInstance | null,
##     region: HitRegion | null,
##     region_id: String,
##     is_headshot: bool,
##     point: Vector3,
##     cover_tag: String,
##   }
func resolve(origin: Vector3, direction: Vector3, targets: Array[TargetInstance]) -> Dictionary:
	var dir := direction.normalized()
	var cover_distance := _nearest_cover(origin, dir)
	var cover_tag := _nearest_cover_tag

	var best_distance := MAX_RANGE
	var best_target: TargetInstance = null
	var best_region: HitRegion = null
	for target in targets:
		if target == null or not target.alive:
			continue
		# Broad reject: a ray that misses the bounding sphere cannot hit a region,
		# so the per-region tests are skipped for every target the crosshair is not
		# near. This is the difference between 3 tests and 30 per shot.
		var center := target.aim_center()
		var radius := target.bounding_radius()
		var bounding := MathX.ray_sphere(origin, dir, center, radius)
		if bounding < 0.0 or bounding > best_distance:
			continue
		for region in target.regions:
			var distance := region.intersect(origin, dir, target.world_position(), target.basis)
			if distance < 0.0 or distance >= best_distance:
				continue
			best_distance = distance
			best_target = target
			best_region = region

	if cover_distance >= 0.0 and cover_distance <= best_distance:
		return {
			"result": HIT_COVER,
			"distance": cover_distance,
			"target": null,
			"region": null,
			"region_id": "",
			"is_headshot": false,
			"point": origin + dir * cover_distance,
			"cover_tag": cover_tag,
		}
	if best_target != null:
		return {
			"result": HIT_TARGET,
			"distance": best_distance,
			"target": best_target,
			"region": best_region,
			"region_id": best_region.id if best_region != null else "",
			"is_headshot": best_region.is_headshot if best_region != null else false,
			"point": origin + dir * best_distance,
			"cover_tag": "",
		}
	return {
		"result": HIT_NOTHING,
		"distance": -1.0,
		"target": null,
		"region": null,
		"region_id": "",
		"is_headshot": false,
		"point": origin + dir * MAX_RANGE,
		"cover_tag": "",
	}


var _nearest_cover_tag: String = ""


func _nearest_cover(origin: Vector3, direction: Vector3) -> float:
	var best := -1.0
	_nearest_cover_tag = ""
	for box in _cover:
		if box == null:
			continue
		var distance := box.intersect(origin, direction)
		if distance < 0.0 or distance > MAX_RANGE:
			continue
		if best < 0.0 or distance < best:
			best = distance
			_nearest_cover_tag = box.tag
	return best


## True when a straight line between two points is blocked by cover. Used by the
## Rival, whose perception must respect the same geometry the player shoots through.
func line_blocked(from: Vector3, to: Vector3) -> bool:
	var delta := to - from
	var distance := delta.length()
	if distance <= 0.001:
		return false
	var direction := delta / distance
	var cover_distance := _nearest_cover(from, direction)
	return cover_distance >= 0.0 and cover_distance < distance


## Nearest cover distance along a direction, exposed for the Rival's cover logic.
func cover_distance(origin: Vector3, direction: Vector3) -> float:
	return _nearest_cover(origin, direction.normalized())


func cover_boxes() -> Array[CoverBox]:
	return _cover
