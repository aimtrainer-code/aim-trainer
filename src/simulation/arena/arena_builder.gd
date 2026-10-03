class_name ArenaBuilder
extends RefCounted

## Turns an `ArenaDefinition` into geometry records and cover boxes.
##
## Deliberately node-free: the builder returns plain data so it can be unit-tested
## without a scene tree, and so the same geometry can be consumed by the renderer, the
## hit registry and the Rival's line-of-sight test. `src/simulation/world.gd` is the
## only place that turns these records into nodes.

## Material presets referenced by name from arena JSON.
const MATERIAL_MATTE: String = "matte"
const MATERIAL_GRID: String = "grid"
const MATERIAL_ACCENT: String = "accent"
const MATERIAL_EMISSIVE: String = "emissive"


## Room shell: floor, ceiling-less walls and a back wall. Generated from the
## dimensions rather than authored, so every arena is closed and cannot be shot out of.
static func shell(arena: ArenaDefinition) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var floor_thickness := 0.5
	records.append({
		"kind": "box",
		"position": Vector3(0, arena.floor_y - floor_thickness * 0.5, 0),
		"size": Vector3(arena.half_width * 2.0 + 6.0, floor_thickness, arena.depth * 2.0 + 6.0),
		"basis": Basis.IDENTITY,
		"tag": "floor",
		"material": MATERIAL_GRID,
		"colour": VantaStyle.BG,
	})
	var wall_height := arena.height
	for side in [-1.0, 1.0]:
		records.append({
			"kind": "box",
			"position": Vector3(side * arena.half_width, arena.floor_y + wall_height * 0.5, 0),
			"size": Vector3(0.5, wall_height, arena.depth * 2.0 + 6.0),
			"basis": Basis.IDENTITY,
			"tag": "wall",
			"material": MATERIAL_GRID,
			"colour": VantaStyle.BG,
		})
	# Back wall: behind the targets, with a subtle accent band so the far distance is
	# readable without any HUD element.
	records.append({
		"kind": "box",
		"position": Vector3(0, arena.floor_y + wall_height * 0.5, -arena.depth),
		"size": Vector3(arena.half_width * 2.0 + 0.5, wall_height, 0.5),
		"basis": Basis.IDENTITY,
		"tag": "wall",
		"material": MATERIAL_GRID,
		"colour": VantaStyle.BG,
	})
	# Behind the player is open in most aim trainers; VANTA closes it so a stray flick
	# cannot reveal a hole in the world.
	records.append({
		"kind": "box",
		"position": Vector3(0, arena.floor_y + wall_height * 0.5, arena.depth),
		"size": Vector3(arena.half_width * 2.0 + 0.5, wall_height, 0.5),
		"basis": Basis.IDENTITY,
		"tag": "wall",
		"material": MATERIAL_MATTE,
		"colour": VantaStyle.SURFACE,
	})
	return records


## Authored primitives, converted to records with a resolved basis.
static func authored(arena: ArenaDefinition) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for primitive in arena.primitives:
		var rotation: Vector3 = primitive["rotation"]
		var basis := Basis.IDENTITY
		if not is_zero_approx(rotation.x):
			basis = basis.rotated(Vector3.RIGHT, deg_to_rad(rotation.x))
		if not is_zero_approx(rotation.y):
			basis = basis.rotated(Vector3.UP, deg_to_rad(rotation.y))
		records.append({
			"kind": String(primitive["type"]),
			"position": primitive["position"],
			"size": primitive["size"],
			"basis": basis,
			"tag": String(primitive["tag"]),
			"material": String(primitive["material"]),
			"colour": primitive["colour"],
		})
	return records


static func geometry(arena: ArenaDefinition) -> Array[Dictionary]:
	var records := shell(arena)
	records.append_array(authored(arena))
	# Anchor cover is part of the geometry, and two anchors may share one barrier
	# (a target on each side of the same wall). Identical boxes are emitted once: two
	# coincident meshes z-fight, and two coincident hit boxes cost twice for nothing.
	var seen := {}
	for anchor in arena.anchors:
		if not anchor.has_cover:
			continue
		var size: Vector3 = anchor.cover_primitive["size"]
		var key := "%s|%s" % [str(anchor.cover_position.round()), str(size.round())]
		if seen.has(key):
			continue
		seen[key] = true
		records.append({
			"kind": "box",
			"position": anchor.cover_position,
			"size": size,
			"basis": Basis.IDENTITY,
			"tag": "cover",
			"material": MATERIAL_GRID,
			"colour": VantaStyle.SURFACE_2,
		})
	return records


## Every solid volume, as hit-testable boxes. Anything with a tag other than "decal"
## blocks shots.
static func cover_boxes(arena: ArenaDefinition) -> Array[CoverBox]:
	var boxes: Array[CoverBox] = []
	for record in geometry(arena):
		if String(record["tag"]) == "decal":
			continue
		var box := CoverBox.new()
		box.center = record["position"]
		box.basis = record["basis"]
		box.half_size = (record["size"] as Vector3) * 0.5
		box.tag = String(record["tag"])
		box.colour = record["colour"]
		box.material = String(record["material"])
		boxes.append(box)
	return boxes


static func cover_tags(arena: ArenaDefinition) -> Array[String]:
	var tags: Array[String] = []
	for box in cover_boxes(arena):
		tags.append(box.tag)
	return tags


## Converts a spawn zone into world space.
static func zone_aabb(zone: Dictionary) -> AABB:
	var center: Vector3 = zone["center"]
	var size: Vector3 = zone["size"]
	return AABB(center - size * 0.5, size)


## Half-width of the lateral corridor a target may move in, derived from the spawn
## geometry: at distance d, an azimuth range of ±a degrees spans d·tan(a) metres.
## Using the spawn cone as the motion limit is what stops a target from drifting out
## of the region the scenario author chose.
static func corridor_half_width(distance: float, azimuth_half_range_degrees: float) -> float:
	var half_range := maxf(1.0, azimuth_half_range_degrees)
	return clampf(distance * tan(deg_to_rad(half_range)), 0.25, 40.0)


## Vertical band a target may move in, from the elevation range.
static func vertical_band(distance: float, elevation_half_range_degrees: float) -> float:
	var half_range := maxf(1.0, elevation_half_range_degrees)
	return clampf(distance * tan(deg_to_rad(half_range)), 0.15, 20.0)
