class_name SpawnSpec
extends RefCounted

## Where targets may appear.
##
## Spawning in polar coordinates (azimuth angle, elevation angle, distance) keeps
## scenarios independent of arena geometry and makes angular difficulty explicit:
## "a 1° micro flick" is a statement about the spawn distribution, not about a
## particular map.
##
## Anti-memorisation: the runtime never uses a fixed spawn sequence. `sequence` can
## bias the distribution (alternate sides, force long-to-short switches) but every
## parameter is still randomised inside its range with the scenario's seed.

enum Region { SPHERE_CAP, BOX_VOLUME, ARC, COVER_EDGE, ADVANCED_ROUTE }
const REGION_IDS: Array[String] = ["sphere_cap", "box_volume", "arc", "cover_edge", "advanced_route"]

## Azimuth: 0° is straight ahead, positive is to the right.
var azimuth_degrees: Vector2 = Vector2(-45.0, 45.0)
## Elevation: 0° is eye level, positive is up.
var elevation_degrees: Vector2 = Vector2(-10.0, 10.0)
## Distance from the player, in metres.
var distance_min: float = 6.0
var distance_max: float = 14.0
var region: int = Region.SPHERE_CAP
## Vertical offset applied to the player's eye height (negative = below eye level).
var height_offset: Vector2 = Vector2(0.0, 0.0)
## Biases the horizontal distribution: 0 = uniform, >0 favours the centre.
var centre_bias: float = 0.0
## Alternates spawns between left/right of the previous target. Costs nothing and
## removes the "same side twice" pattern that lets players pre-aim.
var alternate_sides: bool = false
## Minimum angular distance between consecutive spawns, in degrees.
var min_angle_between: float = 0.0
## Extra spawn points declared by the arena (cover edges, doors, lanes).
var anchor_ids: Array[String] = []

var errors: Array[String] = []


static func from_dict(data: Variant) -> SpawnSpec:
	var spec := SpawnSpec.new()
	var source := SpecParse.dict(data)
	var label := "spawn"
	spec.azimuth_degrees = SpecParse.range_value(source, "azimuth_degrees", -45.0, 45.0, -180.0, 180.0, spec.errors, label)
	spec.elevation_degrees = SpecParse.range_value(source, "elevation_degrees", -10.0, 10.0, -89.0, 89.0, spec.errors, label)
	spec.distance_min = SpecParse.float_value(source, "distance_min", 6.0, 0.5, 200.0, spec.errors, label)
	spec.distance_max = SpecParse.float_value(source, "distance_max", 14.0, 0.5, 200.0, spec.errors, label)
	if spec.distance_min > spec.distance_max:
		spec.errors.append("spawn.distance_min is greater than spawn.distance_max")
		spec.distance_min = spec.distance_max
	spec.height_offset = SpecParse.range_value(source, "height_offset", 0.0, 0.0, -20.0, 20.0, spec.errors, label)
	spec.centre_bias = SpecParse.float_value(source, "centre_bias", 0.0, 0.0, 1.0, spec.errors, label)
	spec.alternate_sides = SpecParse.bool_value(source, "alternate_sides", false)
	spec.min_angle_between = SpecParse.float_value(source, "min_angle_between", 0.0, 0.0, 180.0, spec.errors, label)
	var region_id := SpecParse.string_value(source, "region", "sphere_cap")
	var region_index := REGION_IDS.find(region_id)
	if region_index < 0:
		spec.errors.append("spawn.region '%s' is not supported" % region_id)
	else:
		spec.region = region_index
	if source.has("anchor_ids"):
		var raw: Variant = source["anchor_ids"]
		if typeof(raw) == TYPE_ARRAY:
			for item in raw:
				if typeof(item) == TYPE_STRING and ScenarioDefinition.is_safe_id(String(item)):
					spec.anchor_ids.append(String(item))
				else:
					spec.errors.append("spawn.anchor_ids entries must be plain ids")
		else:
			spec.errors.append("spawn.anchor_ids must be an array")
	return spec


func to_dict() -> Dictionary:
	return {
		"region": REGION_IDS[clampi(region, 0, REGION_IDS.size() - 1)],
		"azimuth_degrees": [azimuth_degrees.x, azimuth_degrees.y],
		"elevation_degrees": [elevation_degrees.x, elevation_degrees.y],
		"distance_min": distance_min,
		"distance_max": distance_max,
		"height_offset": [height_offset.x, height_offset.y],
		"centre_bias": centre_bias,
		"alternate_sides": alternate_sides,
		"min_angle_between": min_angle_between,
		"anchor_ids": anchor_ids,
	}
