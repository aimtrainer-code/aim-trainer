class_name TargetShape
extends RefCounted

## Builds the hit regions and the proportions of a training dummy.
##
## The humanoid is VANTA's own minimal training dummy: three primitive volumes
## (head, torso, legs) sized from a single `height` value. It is not a character
## model, contains no third-party assets, and its hit volumes are the *same*
## primitives the renderer instantiates, so what is drawn is what can be shot.
##
## Proportions are intentionally human-like rather than anatomically exact: the goal
## is that a head shot requires the same order of precision as in a tactical shooter.
## At 1.80 m the head sphere is 11.7 cm in radius (23.4 cm tall), the torso capsule is
## 41 cm wide, and the legs are 25 cm wide.

const HEAD_RADIUS_RATIO: float = 0.065
const HEAD_HEIGHT_RATIO: float = 0.93
const TORSO_RADIUS_RATIO: float = 0.115
const TORSO_BOTTOM_RATIO: float = 0.60
const TORSO_TOP_RATIO: float = 0.80
const LEGS_RADIUS_RATIO: float = 0.070
const LEGS_TOP_RATIO: float = 0.55
## Tactical games model standing players with a head hitbox a little smaller than the
## rendered helmet; keeping the multiplier at 1.0 by default avoids inventing a value
## that does not correspond to any real title.
const DISC_THICKNESS_RATIO: float = 0.18


## Regions for a target type at a given size (height/radius in metres).
static func regions_for(group: TargetGroup, size_scale: float = 1.0) -> Array[HitRegion]:
	var regions: Array[HitRegion] = []
	var size: float = maxf(0.02, group.size * size_scale)
	match group.type:
		TargetGroup.Type.SPHERE:
			regions.append(HitRegion.sphere(HitRegion.BODY, Vector3(0, size, 0), size, 1.0, false))
		TargetGroup.Type.POINT:
			regions.append(HitRegion.sphere(HitRegion.BODY, Vector3(0, size, 0), size, 1.0, false))
		TargetGroup.Type.DISC:
			# Faces the player; the runtime supplies the actual facing at spawn time.
			regions.append(HitRegion.disc(HitRegion.BODY, Vector3(0, size, 0), Vector3(0, 0, 1), size, size * DISC_THICKNESS_RATIO))
		TargetGroup.Type.HUMANOID:
			regions.append_array(_humanoid_regions(size))
		TargetGroup.Type.HEAD_ONLY:
			var head := HitRegion.sphere(HitRegion.HEAD, Vector3(0, size * HEAD_HEIGHT_RATIO, 0), size * HEAD_RADIUS_RATIO, 1.0, true)
			regions.append(head)
	return regions


static func _humanoid_regions(height: float) -> Array[HitRegion]:
	var regions: Array[HitRegion] = []
	var head := HitRegion.sphere(HitRegion.HEAD, Vector3(0, height * HEAD_HEIGHT_RATIO, 0), height * HEAD_RADIUS_RATIO, 3.0, true)
	var torso := HitRegion.capsule(
		HitRegion.TORSO,
		Vector3(0, height * TORSO_BOTTOM_RATIO, 0),
		Vector3(0, height * TORSO_TOP_RATIO, 0),
		height * TORSO_RADIUS_RATIO
	)
	var legs := HitRegion.capsule(
		HitRegion.LEGS,
		Vector3(0, height * 0.03, 0),
		Vector3(0, height * LEGS_TOP_RATIO, 0),
		height * LEGS_RADIUS_RATIO
	)
	regions.append(head)
	regions.append(torso)
	regions.append(legs)
	return regions


## Applies the scenario's per-region damage multipliers to a region list.
static func apply_multipliers(regions: Array[HitRegion], group: TargetGroup) -> void:
	if group.region_multipliers.is_empty():
		return
	for region in regions:
		if group.region_multipliers.has(region.id):
			region.damage_multiplier *= float(group.region_multipliers[region.id])


## Restricts a humanoid to a subset of regions, used by scenarios that only accept
## head hits (a body hit then counts as a miss instead of partial damage).
static func restrict_to(regions: Array[HitRegion], allowed: Array[String]) -> Array[HitRegion]:
	var out: Array[HitRegion] = []
	for region in regions:
		if allowed.has(region.id):
			out.append(region)
	return out


## World-space bounding radius, used for spawn spacing and for the hit-test broad
## reject (a ray that misses the bounding sphere cannot hit any region).
static func bounding_radius(group: TargetGroup, size_scale: float = 1.0) -> float:
	var size: float = maxf(0.02, group.size * size_scale)
	match group.type:
		TargetGroup.Type.HUMANOID:
			return size
		TargetGroup.Type.HEAD_ONLY:
			return size * HEAD_HEIGHT_RATIO + size * HEAD_RADIUS_RATIO
		_:
			return size * 1.2


## Centre of mass in local space, so targets can be placed by their visual centre
## rather than by their feet.
static func local_center(group: TargetGroup, size_scale: float = 1.0) -> Vector3:
	var size: float = maxf(0.02, group.size * size_scale)
	match group.type:
		TargetGroup.Type.HUMANOID:
			return Vector3(0, size * 0.5, 0)
		TargetGroup.Type.HEAD_ONLY:
			return Vector3(0, size * HEAD_HEIGHT_RATIO, 0)
		_:
			return Vector3(0, size, 0)


## The humanoid proportions as data, so the renderer can build the same silhouette
## without duplicating any constants.
static func humanoid_parts(height: float) -> Array[Dictionary]:
	return [
		{"id": HitRegion.HEAD, "kind": "sphere", "center": Vector3(0, height * HEAD_HEIGHT_RATIO, 0), "radius": height * HEAD_RADIUS_RATIO},
		{"id": HitRegion.TORSO, "kind": "capsule", "a": Vector3(0, height * TORSO_BOTTOM_RATIO, 0), "b": Vector3(0, height * TORSO_TOP_RATIO, 0), "radius": height * TORSO_RADIUS_RATIO},
		{"id": HitRegion.LEGS, "kind": "capsule", "a": Vector3(0, height * 0.03, 0), "b": Vector3(0, height * LEGS_TOP_RATIO, 0), "radius": height * LEGS_RADIUS_RATIO},
	]
