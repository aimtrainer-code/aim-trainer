class_name ArenaAnchor
extends RefCounted

## A named point of tactical interest: a corner to peek, a door to hold, a lane to
## clear.
##
## Anchors are what turn "targets appear somewhere" into "targets appear from a
## position that has a tactical meaning". Peek Lab uses them as the set of places an
## opponent can emerge from; Crosshair Placement drills use them as the angles the
## player is expected to pre-aim.
##
## An anchor is deliberately self-contained: the peek axis, the cover that hides the
## target before it emerges, and the stance are all part of the anchor, so moving an
## anchor in the JSON moves the whole behaviour with it.

var id: String = ""
## Where the target stands when fully exposed (usually just clear of the cover edge).
var position: Vector3 = Vector3.ZERO
## Direction the target faces while exposed (used to orient discs and to give the
## Rival a facing to reason about).
var facing: Vector3 = Vector3(0, 0, 1)
## Unit vector along which the target travels out of cover. Defaults to the
## perpendicular of `facing`.
var peek_axis: Vector3 = Vector3.RIGHT
## The cover primitive that occludes the hidden position (a dictionary in the same
## shape as an arena primitive), or null when the anchor has no cover.
var cover_primitive: Dictionary = {}
var cover_position: Vector3 = Vector3.ZERO
var has_cover: bool = false
## "standing" or "crouch": crouch anchors place the exposed target lower, which
## trains a different pre-aim height.
var stance: String = "standing"
## Free-form tags for scenario filtering: "corner", "door", "long", "short", "elevated".
var tags: Array[String] = []


static func from_dict(data: Variant) -> Dictionary:
	var anchor := ArenaAnchor.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("arena anchors must be objects")
		return {"anchor": anchor, "errors": errors, "warnings": warnings}
	var d: Dictionary = data

	anchor.id = SpecParse.string_value(d, "id", "", 32)
	if anchor.id.is_empty() or not ScenarioDefinition.is_safe_id(anchor.id):
		errors.append("anchor ids must be plain lowercase ids (got '%s')" % anchor.id)

	anchor.position = _vector3(d.get("position", null), Vector3.ZERO)
	anchor.facing = _vector3(d.get("facing", null), Vector3(0, 0, 1)).normalized()
	if anchor.facing.length_squared() < 0.5:
		anchor.facing = Vector3(0, 0, 1)

	var raw_axis: Variant = d.get("peek_axis", null)
	if typeof(raw_axis) == TYPE_ARRAY:
		anchor.peek_axis = _vector3(raw_axis, anchor.facing.cross(Vector3.UP).normalized()).normalized()
	else:
		# Default: perpendicular to facing, on the horizontal plane.
		anchor.peek_axis = anchor.facing.cross(Vector3.UP).normalized()
		if anchor.peek_axis.length_squared() < 0.5:
			anchor.peek_axis = Vector3.RIGHT
	if anchor.peek_axis.length_squared() < 0.5:
		errors.append("anchor '%s' has a degenerate peek axis" % anchor.id)
		anchor.peek_axis = Vector3.RIGHT

	anchor.stance = SpecParse.string_value(d, "stance", "standing", 16).to_lower()
	if not ["standing", "crouch"].has(anchor.stance):
		warnings.append("anchor '%s' has unknown stance '%s'; using standing" % [anchor.id, anchor.stance])
		anchor.stance = "standing"

	if d.has("cover"):
		var cover_data: Variant = d["cover"]
		if typeof(cover_data) == TYPE_DICTIONARY:
			var parsed := ArenaDefinition._parse_primitive(cover_data)
			if parsed.has("error"):
				errors.append("anchor '%s': %s" % [anchor.id, String(parsed["error"])])
			else:
				anchor.cover_primitive = parsed
				anchor.cover_position = parsed["position"]
				anchor.has_cover = true
		else:
			errors.append("anchor '%s' cover must be an object" % anchor.id)

	if d.has("tags"):
		var raw_tags: Variant = d["tags"]
		if typeof(raw_tags) == TYPE_ARRAY:
			for item in (raw_tags as Array):
				if typeof(item) == TYPE_STRING:
					anchor.tags.append(String(item))

	if anchor.has_cover:
		var cover_box := CoverBox.make(
			anchor.cover_position,
			anchor.cover_primitive["size"],
			(anchor.cover_primitive["rotation"] as Vector3).y,
			(anchor.cover_primitive["rotation"] as Vector3).x
		)
		var exposed_top := cover_box.top_y()
		var stance_height := 1.05 if anchor.stance == "crouch" else 1.45
		if exposed_top < anchor.position.y + stance_height - 0.25:
			warnings.append("anchor '%s' cover is taller than the exposed target, so the peek may remain hidden" % anchor.id)

	return {"anchor": anchor, "errors": errors, "warnings": warnings}


static func _vector3(value: Variant, fallback: Vector3) -> Vector3:
	return ArenaDefinition._vector3(value, fallback)


func cover_box() -> CoverBox:
	if not has_cover:
		return null
	return CoverBox.make(
		cover_position,
		cover_primitive["size"],
		(cover_primitive["rotation"] as Vector3).y,
		(cover_primitive["rotation"] as Vector3).x,
		"cover"
	)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": [position.x, position.y, position.z],
		"facing": [facing.x, facing.y, facing.z],
		"peek_axis": [peek_axis.x, peek_axis.y, peek_axis.z],
		"stance": stance,
		"tags": tags,
		"cover": cover_primitive,
	}
