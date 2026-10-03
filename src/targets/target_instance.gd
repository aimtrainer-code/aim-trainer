class_name TargetInstance
extends RefCounted

## One live target: its geometry, health, motion, and its participation in scoring.
##
## Instances are pooled by the target manager, so a scenario that spawns 20 000
## targets over a long session does not churn the allocator. `reset()` therefore has
## to fully re-initialise every field that a previous life touched — a stale field is
## exactly the class of bug that makes "the second target never expires".

var id: int = -1
var group: TargetGroup = null
var size_scale: float = 1.0
var regions: Array[HitRegion] = []
var hp: float = 1.0
var max_hp: float = 1.0
var alive: bool = false
var spawn_time: float = 0.0
var lifetime: float = 0.0
var grace_until: float = 0.0
var origin: Vector3 = Vector3.ZERO
## Orientation of the target. Discs are rotated to face the player at spawn; dummies
## keep their default orientation unless a peek variant asks for a yaw.
var basis: Basis = Basis.IDENTITY
var motion: TargetMotion = null

# --- statistics per target ---
var shots_taken: int = 0
var hits_taken: int = 0
var first_hit_time: float = -1.0
var expired: bool = false
var eliminated: bool = false
var ended_by: String = ""
## Simulation time at which the target was retired (-1 while it is alive). Holding
## the end time here is what makes time-to-kill an honest measurement: it is taken
## from the same clock the shot was resolved on, not from a frame counter.
var ended_at: float = -1.0

## Metadata for the HUD and for scoring (which group this came from, which spawn
## anchor was used, and which peek behaviour was rolled).
var group_index: int = 0
var spawn_anchor: String = ""
var colour_index: int = 0


func setup(new_id: int, source_group: TargetGroup, scale: float, spawn_position: Vector3, spawn_basis: Basis, now: float, lifetime_seconds: float, damage_multipliers: bool = true) -> void:
	id = new_id
	group = source_group
	size_scale = scale
	origin = spawn_position
	basis = spawn_basis
	spawn_time = now
	lifetime = lifetime_seconds
	grace_until = 0.0
	regions = TargetShape.regions_for(group, scale)
	if damage_multipliers:
		TargetShape.apply_multipliers(regions, group)
	hp = group.hp
	max_hp = group.hp
	alive = true
	shots_taken = 0
	hits_taken = 0
	first_hit_time = -1.0
	expired = false
	eliminated = false
	ended_by = ""
	ended_at = -1.0
	colour_index = group.color_override


## World position of the target's origin (its feet for humanoids).
func world_position() -> Vector3:
	if motion != null:
		return motion.interpolated
	return origin


func aim_center() -> Vector3:
	return world_position() + basis * TargetShape.local_center(group, size_scale)


## Bounding radius of everything that can be hit.
func bounding_radius() -> float:
	return TargetShape.bounding_radius(group, size_scale)


func age(now: float) -> float:
	return now - spawn_time


## Seconds remaining before expiry; negative when already expired.
func remaining_lifetime(now: float) -> float:
	var limit := lifetime
	if grace_until > 0.0:
		limit = maxf(limit, grace_until - spawn_time)
	return limit - age(now)


func has_expired(now: float) -> bool:
	if not alive:
		return false
	return remaining_lifetime(now) <= 0.0


## Applies damage from a hit region. Returns a result dictionary describing what
## happened so the caller can score, play audio and update the HUD without asking
## the target any further questions.
func apply_hit(region: HitRegion, damage: float, now: float) -> Dictionary:
	if not alive or region == null:
		return {"accepted": false, "reason": "dead_or_no_region"}
	shots_taken += 1
	var effective := damage * region.damage_multiplier
	if effective <= 0.0:
		return {
			"accepted": false,
			"reason": "inert_region",
			"region": region.id,
			"is_headshot": region.is_headshot,
			"lethal": false,
			"damage": 0.0,
		}
	hits_taken += 1
	if first_hit_time < 0.0:
		first_hit_time = now
	hp = maxf(0.0, hp - effective)
	var lethal := hp <= 0.0
	var was_grace := grace_until
	return {
		"accepted": true,
		"reason": "",
		"region": region.id,
		"is_headshot": region.is_headshot,
		"damage": effective,
		"lethal": lethal,
		"remaining_hp": hp,
		"time_to_first_hit": (first_hit_time - spawn_time) if was_grace == 0.0 else (first_hit_time - spawn_time),
	}


## Marks the target as removed. `reason` is one of "eliminated", "expired", "aborted".
## `now` is the simulation time of the retirement; it is what time-to-kill is measured
## against, so it must be the same clock the shot was resolved on.
func retire(reason: String, now: float = -1.0) -> void:
	alive = false
	ended_by = reason
	ended_at = now
	match reason:
		"eliminated":
			eliminated = true
		"expired":
			expired = true


## Seconds from spawn to the killing blow, or -1.0 if the target was not eliminated.
func time_to_kill() -> float:
	if not eliminated or ended_at < 0.0:
		return -1.0
	return maxf(0.0, ended_at - spawn_time)


## Seconds from spawn to the first accepted hit, or -1.0 if nothing ever connected.
func time_to_first_hit() -> float:
	if first_hit_time < 0.0:
		return -1.0
	return maxf(0.0, first_hit_time - spawn_time)


func to_debug_dict() -> Dictionary:
	return {
		"id": id,
		"group": group.type_id() if group != null else "?",
		"hp": hp,
		"alive": alive,
		"shots": shots_taken,
		"hits": hits_taken,
		"position": [world_position().x, world_position().y, world_position().z],
	}
