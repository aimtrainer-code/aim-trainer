class_name WeaponRuntime
extends RefCounted

## Live weapon state: ammunition, cone of fire, recoil, and shot generation.
##
## Two properties matter more than any individual number here:
##
##  1. **Shots go where the crosshair points.** The direction handed back by
##     `fire()` is derived from the *same* yaw/pitch the player is currently looking
##     through, plus the spread cone and the accumulated recoil. There is no separate
##     "bullet origin" that could drift away from the reticle.
##  2. **Determinism.** Spread and recoil are drawn from a seeded `VantaRng` stream,
##     so a scenario with a fixed seed produces the identical spray pattern on every
##     machine. That is what lets a benchmark be repeatable and what makes a
##     "recoil control" score comparable between two sessions.

## Inputs that influence the weapon for a frame.
class State extends RefCounted:
	var moving_speed: float = 0.0
	var airborne: bool = false
	var aiming: bool = false
	## Set while the player is rooted (movement drills in a stationary phase).
	var stationary: bool = true


var definition: WeaponDefinition = null
var ammo: int = 30
var reloading: bool = false
var reload_remaining: float = 0.0
var spread_deg: float = 0.0
var last_shot_time: float = -1000.0
var shots_fired: int = 0
var shots_in_burst: int = 0
var burst_cooldown_remaining: float = 0.0
var time_since_last_shot: float = 1000.0

## Recoil offset applied to the player's view, in degrees.
var recoil: Vector2 = Vector2.ZERO

var _rng: VantaRng = null
## Consecutive shots without a pause, used to grow the recoil pattern.
var _recoil_shot_index: int = 0
var _pattern_seed: int = 0
var _blocked_reason: String = ""


func _init(weapon: WeaponDefinition = null, rng: VantaRng = null) -> void:
	definition = weapon
	_rng = rng
	reset()


func reset() -> void:
	if definition == null:
		return
	ammo = definition.magazine
	reloading = false
	reload_remaining = 0.0
	spread_deg = definition.spread_base_deg
	shots_fired = 0
	shots_in_burst = 0
	burst_cooldown_remaining = 0.0
	recoil = Vector2.ZERO
	_recoil_shot_index = 0
	time_since_last_shot = 1000.0
	last_shot_time = -1000.0
	_rng_ready()


func _rng_ready() -> void:
	if _rng == null:
		_rng = VantaRng.new(1)
		_pattern_seed = 1


## Total cone of fire for the current state, in degrees (half-angle).
func current_spread(state: State) -> float:
	if definition == null:
		return 0.0
	if definition.beam:
		return definition.spread_base_deg
	var spread := spread_deg
	var movement_scale: float = 0.0
	if definition.movement_reference_speed > 0.0:
		movement_scale = clampf(state.moving_speed / definition.movement_reference_speed, 0.0, 1.5)
	spread += definition.movement_inaccuracy_deg * movement_scale
	if state.airborne:
		spread += definition.airborne_inaccuracy_deg
	if state.aiming and definition.ads_enabled:
		spread *= definition.ads_spread_multiplier
	return clampf(spread, 0.0, definition.spread_max_deg + definition.movement_inaccuracy_deg + definition.airborne_inaccuracy_deg)


func can_fire(now: float) -> bool:
	if definition == null:
		_blocked_reason = "no_weapon"
		return false
	if reloading:
		_blocked_reason = "reloading"
		return false
	if not definition.beam and ammo <= 0:
		_blocked_reason = "empty"
		return false
	if burst_cooldown_remaining > 0.0:
		_blocked_reason = "burst_cooldown"
		return false
	if now - last_shot_time < definition.shot_interval() - 0.0005:
		_blocked_reason = "fire_rate"
		return false
	return true


func blocked_reason() -> String:
	return _blocked_reason


## Fires one shot. Returns an empty dictionary when the weapon cannot fire.
##
## The returned dictionary is the record of the shot: where it came from, which way
## it went, and with which parameters. Hit resolution is a separate step
## (`HitRegistry.resolve`) so the two concerns can be tested independently.
func fire(now: float, state: State) -> Dictionary:
	if not can_fire(now):
		return {}
	if not definition.beam:
		ammo -= 1
	var spread := current_spread(state)
	var first_shot := _recoil_shot_index == 0
	if first_shot:
		spread *= definition.first_shot_spread_multiplier
	# One offset per pellet. Single-pellet weapons (every archetype VANTA ships) draw
	# exactly one offset, so their pattern is unchanged; the array exists for
	# community weapons that model shot spread.
	var offsets: Array[Vector2] = []
	var pellet_count := maxi(1, definition.pellets)
	for _pellet in pellet_count:
		offsets.append(_sample_cone(spread) if spread > 0.0 else Vector2.ZERO)
	var applied_recoil := _apply_recoil(first_shot)
	last_shot_time = now
	shots_fired += 1
	shots_in_burst += 1
	time_since_last_shot = 0.0
	_recoil_shot_index += 1
	if definition.shots_per_burst > 0 and shots_in_burst >= definition.shots_per_burst:
		burst_cooldown_remaining = definition.burst_cooldown
		shots_in_burst = 0
	# Reloading is deliberately *not* started here. Whether an empty magazine ends the
	# run, reloads automatically, or is ignored is a scenario decision
	# (`AmmoSpec.empty_ends_round` / `auto_reload`), so `ScenarioRuntime` owns it. The
	# weapon's only job is to say that it cannot fire and why.
	return {
		"spread_offset_deg": offsets[0],
		"spread_offsets_deg": offsets,
		"recoil_applied_deg": applied_recoil,
		"spread_deg": spread,
		"first_shot": first_shot,
		"ammo_after": ammo,
		"shot_index": shots_fired,
	}


## Samples a point inside the cone of fire. Uniform by area, not by angle: sampling
## the radius uniformly would bias shots towards the centre, which would make spread
## feel tighter than it is.
func _sample_cone(half_angle_deg: float) -> Vector2:
	var angle := _rng.roll("weapon") * TAU
	var radius := half_angle_deg * sqrt(_rng.roll("weapon"))
	return Vector2(cos(angle) * radius, sin(angle) * radius)


func _apply_recoil(first_shot: bool) -> Vector2:
	if definition.recoil_vertical_deg <= 0.0 and definition.recoil_horizontal_deg <= 0.0:
		return Vector2.ZERO
	var index := float(_recoil_shot_index)
	var growth := pow(definition.recoil_growth, index / 10.0)
	var vertical := definition.recoil_vertical_deg * growth
	if first_shot:
		# The first shot of a burst is the accurate one; that is the shot precision
		# drills train, so its recoil is not scaled up by pattern growth.
		vertical = definition.recoil_vertical_deg
	var pattern_ratio := clampf(definition.recoil_pattern_ratio, 0.0, 1.0)
	var horizontal_pattern := sin(index * 1.1 + float(_pattern_seed % 7)) * definition.recoil_horizontal_deg
	var random_walk := _rng.roll_range("recoil", -definition.recoil_horizontal_deg, definition.recoil_horizontal_deg)
	var horizontal := lerpf(random_walk, horizontal_pattern, pattern_ratio)
	var applied := Vector2(horizontal, vertical)
	recoil += applied
	return applied


## Advances timers: spread recovery, recoil recovery, reload, burst cooldown.
func step(delta: float, _state: State) -> void:
	if definition == null:
		return
	time_since_last_shot += delta
	burst_cooldown_remaining = maxf(0.0, burst_cooldown_remaining - delta)
	if reloading:
		reload_remaining -= delta
		if reload_remaining <= 0.0:
			finish_reload()
	if delta <= 0.0:
		return
	# Spread recovers only after a pause, so tap firing is rewarded and spraying is
	# not. The pause is derived from the weapon's own cadence: firing at the weapon's
	# rate never fully recovers the cone, which is what makes burst discipline matter.
	var recovery_delay: float = maxf(definition.shot_interval() * 1.5, 0.05)
	if time_since_last_shot <= recovery_delay:
		return
	spread_deg = maxf(definition.spread_base_deg, spread_deg - definition.spread_recovery_deg_per_second * delta)
	var recovery: float = definition.recoil_recovery_deg_per_second * delta
	recoil.x = move_toward(recoil.x, 0.0, recovery)
	recoil.y = move_toward(recoil.y, 0.0, recovery)
	# The pattern index only resets after a real pause, so a player cannot erase the
	# climb by stutter-firing a single round at a time.
	if _recoil_shot_index > 0 and time_since_last_shot > maxf(recovery_delay, 0.35):
		_recoil_shot_index = 0


## Called by the scenario runtime after a shot is accepted.
func register_shot() -> void:
	spread_deg = minf(definition.spread_max_deg, spread_deg + definition.spread_per_shot_deg)


func start_reload() -> bool:
	if definition == null or reloading:
		return false
	if ammo >= definition.magazine:
		return false
	if definition.reload_seconds <= 0.0:
		ammo = definition.magazine
		return true
	reloading = true
	reload_remaining = definition.reload_seconds
	# A reload cancels the recoil pattern: the recoil offset itself keeps decaying,
	# but the burst index resets, which is the behaviour competitive players expect.
	_recoil_shot_index = 0
	return true


func finish_reload() -> void:
	reloading = false
	reload_remaining = 0.0
	if definition != null:
		ammo = definition.magazine
	spread_deg = definition.spread_base_deg


func is_magazine_empty() -> bool:
	return definition != null and ammo <= 0 and not definition.beam


func magazine_fraction() -> float:
	if definition == null or definition.magazine <= 0:
		return 0.0
	return clampf(float(ammo) / float(definition.magazine), 0.0, 1.0)


## Spread expressed in screen pixels for the crosshair gap. Uses the same pinhole
## model as the view, so the crosshair gap reflects the real cone of fire.
func spread_pixels(viewport_height: float, fov_degrees: float) -> float:
	if fov_degrees <= 0.0:
		return 0.0
	var focal := (viewport_height * 0.5) / tan(deg_to_rad(fov_degrees * 0.5))
	return tan(deg_to_rad(spread_deg)) * focal


func snapshot() -> Dictionary:
	return {
		"ammo": ammo,
		"magazine": definition.magazine if definition != null else 0,
		"reloading": reloading,
		"reload_remaining": reload_remaining,
		"spread_deg": spread_deg,
		"recoil": [recoil.x, recoil.y],
		"shots_fired": shots_fired,
	}
