class_name SpawnDirector
extends RefCounted

## Decides *where* and *how* each target appears.
##
## This is the anti-memorisation layer, and it is deliberately rule-based rather than
## purely random. Pure randomness is worse training than it looks: it produces
## clusters (three targets in a row in the same spot) that a player learns to ignore,
## and it makes difficulty unpredictable in a way that is not informative. The
## director therefore applies:
##
##   - a minimum angular separation from the previous spawn, so a new target always
##     requires a real mouse movement;
##   - optional side alternation, which removes the "same side twice" pattern;
##   - a centre bias parameter, so micro-flick scenarios stay centred while wide-flick
##     scenarios push towards the extremes;
##   - weighted target-group selection, so mixed scenarios keep their intended mix
##     instead of drifting towards one group by chance.
##
## All of it runs off the scenario's `VantaRng`, so a fixed seed reproduces the exact
## sequence — which is what makes the benchmark scenes and the regression tests
## meaningful.

## One planned spawn.
class Plan extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var group_index: int = 0
	var size_scale: float = 1.0
	var lifetime: float = 1.0
	var anchor_id: String = ""
	var azimuth_degrees: float = 0.0
	var elevation_degrees: float = 0.0
	var distance: float = 0.0
	## For disc targets: the basis that makes the disc face the player at spawn.
	var basis: Basis = Basis.IDENTITY
	## For peek targets: the axis the target peeks along, taken from the anchor it was
	## placed on. Zero when the spawn did not come from an anchor.
	var peek_axis: Vector3 = Vector3.ZERO


var _rng: VantaRng = null
var _definition: ScenarioDefinition = null
var _arena: ArenaDefinition = null
var _last_azimuth: float = 0.0
var _last_elevation: float = 0.0
var _spawn_index: int = 0
var _last_side: float = 0.0
var _anchor_cursor: int = 0


func setup(definition: ScenarioDefinition, arena: ArenaDefinition, rng: VantaRng) -> void:
	_definition = definition
	_arena = arena
	_rng = rng
	_last_azimuth = 0.0
	_last_elevation = 0.0
	_spawn_index = 0
	_last_side = 0.0
	_anchor_cursor = 0


## Produces the next spawn, or null when the scenario has no spawnable groups.
func next_plan(player_position: Vector3, player_forward: Vector3, now: float) -> Plan:
	if _definition == null or _rng == null:
		return null
	var group_index := _pick_group()
	if group_index < 0:
		return null
	var group: TargetGroup = _definition.target_groups[group_index]

	var plan := Plan.new()
	plan.group_index = group_index
	plan.size_scale = _rng.roll_range("spawn", group.size_variance.x, group.size_variance.y)
	plan.lifetime = _roll_lifetime()
	plan.basis = Basis.IDENTITY

	var uses_anchor := _uses_anchors()
	if uses_anchor:
		_place_on_anchor(plan, group, player_position)
	else:
		_place_in_region(plan, group, player_position, player_forward, now)

	if group.type == TargetGroup.Type.DISC:
		# Discs face the player at spawn so that "shoot the coin" is a precision test
		# rather than a test of whether you happened to catch it edge-on.
		var to_player := (player_position - plan.position).normalized()
		plan.basis = Basis.looking_at(-to_player, Vector3.UP)
	_spawn_index += 1
	return plan


func _uses_anchors() -> bool:
	if _arena == null or _arena.anchors.is_empty():
		return false
	var spawn := _definition.spawn
	if spawn.region == SpawnSpec.Region.COVER_EDGE:
		return true
	return not spawn.anchor_ids.is_empty()


func _place_on_anchor(plan: Plan, group: TargetGroup, player_position: Vector3) -> void:
	var candidates: Array[ArenaAnchor] = []
	for anchor in _arena.anchors:
		if not _definition.spawn.anchor_ids.is_empty() and not _definition.spawn.anchor_ids.has(anchor.id):
			continue
		candidates.append(anchor)
	if candidates.is_empty():
		candidates = _arena.anchors
	var anchor: ArenaAnchor = candidates[_rng.roll_int("spawn", 0, candidates.size() - 1)]
	# A head-only or humanoid target needs its feet on the floor; the anchor position
	# is authored at eye height, so the group's local centre is compensated for.
	var group_center := TargetShape.local_center(group, plan.size_scale)
	plan.position = anchor.position - Vector3(0, group_center.y, 0)
	plan.anchor_id = anchor.id
	plan.basis = Basis.looking_at(anchor.facing, Vector3.UP)
	plan.peek_axis = anchor.peek_axis
	var delta := plan.position - player_position
	plan.distance = delta.length()
	var angles := MathX.angles_from_direction(-delta.normalized())
	plan.azimuth_degrees = angles.x
	plan.elevation_degrees = angles.y


func _place_in_region(plan: Plan, group: TargetGroup, player_position: Vector3, player_forward: Vector3, _now: float) -> void:
	var spawn := _definition.spawn
	var attempts := 0
	var azimuth := 0.0
	var elevation := 0.0
	var distance := 0.0
	var position := Vector3.ZERO
	var zone_center := player_position
	var zone_size := Vector3.ZERO

	match spawn.region:
		SpawnSpec.Region.BOX_VOLUME:
			var zone: Dictionary = _arena.spawn_zones[_rng.roll_int("spawn", 0, _arena.spawn_zones.size() - 1)]
			var aabb := ArenaBuilder.zone_aabb(zone)
			zone_center = aabb.get_center()
			zone_size = aabb.size
		_:
			pass

	while attempts < 12:
		attempts += 1
		azimuth = _roll_azimuth(spawn)
		elevation = _rng.roll_range("spawn", spawn.elevation_degrees.x, spawn.elevation_degrees.y)
		distance = _rng.roll_range("spawn", spawn.distance_min, spawn.distance_max)
		if spawn.region == SpawnSpec.Region.BOX_VOLUME:
			position = zone_center + Vector3(
				_rng.roll_range("spawn", -zone_size.x * 0.5, zone_size.x * 0.5),
				_rng.roll_range("spawn", -zone_size.y * 0.5, zone_size.y * 0.5),
				_rng.roll_range("spawn", -zone_size.z * 0.5, zone_size.z * 0.5)
			)
			var delta := position - player_position
			var angles := MathX.angles_from_direction(-delta.normalized())
			azimuth = angles.x
			elevation = angles.y
			distance = delta.length()
		else:
			var direction := _direction_from_angles(azimuth, elevation, player_forward)
			position = player_position + direction * distance

		# Vertical offset (targets standing on the floor, or floating at head height).
		position.y += _rng.roll_range("spawn", spawn.height_offset.x, spawn.height_offset.y)

		# Rejections: too close to the last spawn, or inside cover.
		if spawn.min_angle_between > 0.0:
			var separation := absf(MathX.yaw_delta_degrees(_last_azimuth, azimuth))
			if separation < spawn.min_angle_between and attempts < 10:
				continue
		if _inside_cover(position, group, plan.size_scale):
			continue
		break

	if _inside_cover(position, group, plan.size_scale):
		# A spawn inside geometry would be unshootable; push it towards the player
		# rather than silently keeping a broken position.
		var correction := (player_position - position).normalized() * 1.2
		position += correction

	plan.position = position
	plan.azimuth_degrees = azimuth
	plan.elevation_degrees = elevation
	plan.distance = distance
	_last_azimuth = azimuth
	_last_elevation = elevation


func _roll_azimuth(spawn: SpawnSpec) -> float:
	var lower: float = spawn.azimuth_degrees.x
	var upper: float = spawn.azimuth_degrees.y
	var value := _rng.roll_range("spawn", lower, upper)
	# Centre bias pulls the magnitude towards zero (micro flicks) without removing the
	# outer range entirely, which keeps the drill from becoming purely predictable.
	if spawn.centre_bias > 0.0:
		var biased := value * (1.0 - spawn.centre_bias)
		value = lerpf(value, biased, spawn.centre_bias)
	if spawn.alternate_sides:
		var side := signf(value) if not is_zero_approx(value) else 1.0
		if not is_zero_approx(_last_side) and is_equal_approx(side, _last_side):
			value = -value
		_last_side = signf(value)
	return value


func _direction_from_angles(azimuth_degrees: float, elevation_degrees: float, player_forward: Vector3) -> Vector3:
	# The spawn cone is expressed relative to where the player is looking, so a
	# scenario behaves identically regardless of the arena's orientation.
	var yaw := MathX.angles_from_direction(player_forward).x
	return MathX.direction_from_angles(yaw - azimuth_degrees, elevation_degrees)


func _roll_lifetime() -> float:
	var lifetime := _definition.lifetime
	if is_equal_approx(lifetime.min_seconds, lifetime.max_seconds):
		return lifetime.min_seconds
	return _rng.roll_range("lifetime", lifetime.min_seconds, lifetime.max_seconds)


func _pick_group() -> int:
	var weights: Array[float] = []
	for group in _definition.target_groups:
		weights.append(group.weight)
	var index := _rng.pick_weighted("spawn", weights)
	if index < 0:
		return -1
	return index


func _inside_cover(position: Vector3, group: TargetGroup, size_scale: float) -> bool:
	if _arena == null:
		return false
	var radius := TargetShape.bounding_radius(group, size_scale)
	var center := position + Vector3(0, TargetShape.local_center(group, size_scale).y, 0)
	var point := AABB(center - Vector3(radius, radius, radius), Vector3(radius * 2.0, radius * 2.0, radius * 2.0))
	for box in ArenaBuilder.cover_boxes(_arena):
		if box.tag == "floor":
			continue
		if box.world_aabb().intersects(point):
			return true
	return false


func spawn_count() -> int:
	return _spawn_index
