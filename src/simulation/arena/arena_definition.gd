class_name ArenaDefinition
extends RefCounted

## Original, procedurally described training environment.
##
## VANTA ships no map data from any game. An arena is a list of primitives plus
## semantic anchors (spawn zones, peek positions, sightlines) described in JSON, and
## the builder turns it into geometry and cover boxes.
##
## Why primitives and anchors instead of imported meshes:
##   - the hit-test geometry is then guaranteed to match the visual geometry;
##   - arenas stay tiny (a few kB of JSON) and load instantly, which matters because
##     fast transitions between drills are a product requirement;
##   - contributors can build a new arena in a text editor.

const SCHEMA_VERSION: int = 1

var id: String = ""
var name: String = "ARENA"
var description: String = ""
var author: String = ""

## Interior dimensions of the room, as half-extents from the player's start position.
var half_width: float = 14.0
var height: float = 7.0
var depth: float = 18.0
## Where the player stands. The player never moves in aim drills; movement drills
## spawn them here too, so every scenario shares one frame of reference.
var player_start: Vector3 = Vector3(0, 1.7, 0)
var floor_y: float = 0.0

var primitives: Array[Dictionary] = []
var anchors: Array[ArenaAnchor] = []
var spawn_zones: Array[Dictionary] = []

var errors: Array[String] = []
var warnings: Array[String] = []
var source_path: String = ""


static func from_dict(data: Variant, source_path: String = "") -> Dictionary:
	var arena := ArenaDefinition.new()
	arena.source_path = source_path
	if typeof(data) != TYPE_DICTIONARY:
		arena.errors.append("arena file must contain a JSON object")
		return {"arena": arena, "errors": arena.errors, "warnings": arena.warnings}
	var d: Dictionary = data

	arena.id = SpecParse.string_value(d, "id", "", 64)
	if arena.id.is_empty():
		arena.errors.append("'id' is required")
	elif not ScenarioDefinition.is_safe_id(arena.id):
		arena.errors.append("'id' must be lowercase letters, digits, dashes or underscores")
	arena.name = SpecParse.string_value(d, "name", arena.id.to_upper(), 48)
	arena.description = SpecParse.string_value(d, "description", "", 240)
	arena.author = SpecParse.string_value(d, "author", "", 48)

	arena.half_width = SpecParse.float_value(d, "half_width", 14.0, 3.0, 200.0, arena.errors, "arena")
	arena.height = SpecParse.float_value(d, "height", 7.0, 2.0, 100.0, arena.errors, "arena")
	arena.depth = SpecParse.float_value(d, "depth", 18.0, 3.0, 400.0, arena.errors, "arena")
	arena.floor_y = SpecParse.float_value(d, "floor_y", 0.0, -100.0, 100.0, arena.errors, "arena")
	arena.player_start = _vector3(d.get("player_start", null), Vector3(0, 1.7, 0))
	arena.player_start.y = clampf(arena.player_start.y, arena.floor_y + 0.5, arena.floor_y + 10.0)

	var raw_primitives: Variant = d.get("primitives", [])
	if typeof(raw_primitives) != TYPE_ARRAY:
		arena.errors.append("'primitives' must be an array")
	else:
		for entry in (raw_primitives as Array):
			var parsed := _parse_primitive(entry)
			if parsed.has("error"):
				arena.errors.append(String(parsed["error"]))
			else:
				arena.primitives.append(parsed)

	var raw_anchors: Variant = d.get("anchors", [])
	if typeof(raw_anchors) != TYPE_ARRAY:
		arena.errors.append("'anchors' must be an array")
	else:
		for entry in (raw_anchors as Array):
			var parsed_anchor := ArenaAnchor.from_dict(entry)
			arena.errors.append_array(parsed_anchor["errors"])
			arena.warnings.append_array(parsed_anchor["warnings"])
			arena.anchors.append(parsed_anchor["anchor"])

	var raw_zones: Variant = d.get("spawn_zones", [])
	if typeof(raw_zones) == TYPE_ARRAY:
		for entry in (raw_zones as Array):
			var zone := _parse_zone(entry)
			if zone.has("error"):
				arena.errors.append(String(zone["error"]))
			else:
				arena.spawn_zones.append(zone)
	elif raw_zones != null:
		arena.errors.append("'spawn_zones' must be an array")

	if arena.spawn_zones.is_empty():
		arena.spawn_zones.append({
			"id": "default",
			"center": Vector3(0.0, arena.player_start.y, -arena.depth * 0.6),
			"size": Vector3(arena.half_width * 1.4, 3.0, 3.0),
		})

	arena._validate()
	return {"arena": arena, "errors": arena.errors, "warnings": arena.warnings}


static func _parse_primitive(entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "arena primitives must be objects"}
	var e: Dictionary = entry
	var kind := SpecParse.string_value(e, "type", "box", 16).to_lower()
	var errors: Array[String] = []
	var position := _vector3(e.get("position", null), Vector3.ZERO)
	var size := _vector3(e.get("size", null), Vector3(1, 1, 1))
	var rotation := _vector3(e.get("rotation", null), Vector3.ZERO)
	var tag := SpecParse.string_value(e, "tag", "cover", 24)
	var material := SpecParse.string_value(e, "material", "matte", 24)
	var colour := _colour(e.get("colour", null))

	if kind != "box" and kind != "ramp":
		return {"error": "primitive type '%s' is not supported (use box or ramp)" % kind}
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		errors.append("primitive at %s has a non-positive size" % str(position))
	if size.length() > 400.0:
		errors.append("primitive at %s is unreasonably large" % str(position))
	if rotation.x < -80.0 or rotation.x > 80.0:
		errors.append("primitive pitch must stay between -80 and 80 degrees (got %.1f)" % rotation.x)
	if errors.size() > 0:
		return {"error": errors[0]}

	if kind == "ramp":
		# A ramp is a box whose pitch its derived from its length and height, so the
		# author specifies "rises to this height over this depth" instead of guessing.
		var rise := SpecParse.float_value(e, "rise", size.y, 0.05, 20.0, [], "arena")
		var pitch := rad_to_deg(atan2(rise, maxf(size.z, 0.05)))
		rotation.x = -pitch
		return {
			"type": "ramp",
			"position": position,
			"size": size,
			"rotation": rotation,
			"tag": tag,
			"material": material,
			"colour": colour,
			"rise": rise,
		}
	return {
		"type": "box",
		"position": position,
		"size": size,
		"rotation": rotation,
		"tag": tag,
		"material": material,
		"colour": colour,
	}


static func _parse_zone(entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"error": "spawn zones must be objects"}
	var e: Dictionary = entry
	var id := SpecParse.string_value(e, "id", "", 32)
	if id.is_empty() or not ScenarioDefinition.is_safe_id(id):
		return {"error": "spawn zone ids must be plain lowercase ids"}
	var size := _vector3(e.get("size", null), Vector3(4, 3, 2))
	if size.x <= 0.05 or size.y <= 0.05 or size.z <= 0.05:
		return {"error": "spawn zone '%s' has a degenerate size" % id}
	return {
		"id": id,
		"center": _vector3(e.get("center", null), Vector3.ZERO),
		"size": size,
	}


static func _vector3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			return Vector3(
				float(arr[0]) if _numeric(arr[0]) else fallback.x,
				float(arr[1]) if _numeric(arr[1]) else fallback.y,
				float(arr[2]) if _numeric(arr[2]) else fallback.z
			)
	return fallback


static func _numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _colour(value: Variant) -> Color:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3 and _numeric(arr[0]):
			var scale := 1.0
			if float(arr[0]) > 1.0:
				scale = 1.0 / 255.0
			return Color(
				clampf(float(arr[0]) * scale, 0.0, 1.0),
				clampf(float(arr[1]) * scale, 0.0, 1.0),
				clampf(float(arr[2]) * scale, 0.0, 1.0)
			)
	return Color(0.09, 0.105, 0.13)


## Post-parse structural checks. These are the failure modes that would silently
## produce an unfair arena, so they are errors rather than warnings.
func _validate() -> void:
	if primitives.is_empty():
		warnings.append("arena has no geometry; it will render as an empty room")
	var player_room_ok := player_start.x > -half_width and player_start.x < half_width \
		and player_start.z > -depth and player_start.z < depth \
		and player_start.y > floor_y
	if not player_room_ok:
		errors.append("player_start is outside the arena bounds")

	for zone in spawn_zones:
		var center: Vector3 = zone["center"]
		var size: Vector3 = zone["size"]
		var far_enough := center.distance_to(player_start) > 4.0
		if not far_enough:
			errors.append("spawn zone '%s' is closer than 4 m to the player, which is not a useful target distance" % zone["id"])
		for primitive in primitives:
			if String(primitive["tag"]) != "cover":
				continue
			var box := CoverBox.make(
				primitive["position"], primitive["size"],
				(primitive["rotation"] as Vector3).y, (primitive["rotation"] as Vector3).x,
				String(primitive["tag"])
			)
			var aabb := box.world_aabb()
			if aabb.intersects(AABB(center - size * 0.5, size)):
				warnings.append("spawn zone '%s' overlaps cover geometry '%s'" % [zone["id"], str(primitive["position"])])

	for anchor in anchors:
		if anchor.cover_position == null:
			warnings.append("anchor '%s' has no cover, so its peeks will not be occluded" % anchor.id)


func to_dict() -> Dictionary:
	var anchor_dicts: Array = []
	for anchor in anchors:
		anchor_dicts.append(anchor.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"name": name,
		"description": description,
		"author": author,
		"half_width": half_width,
		"height": height,
		"depth": depth,
		"floor_y": floor_y,
		"player_start": [player_start.x, player_start.y, player_start.z],
		"primitives": primitives,
		"anchors": anchor_dicts,
		"spawn_zones": spawn_zones,
	}
