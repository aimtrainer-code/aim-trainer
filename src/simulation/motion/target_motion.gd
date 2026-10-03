class_name TargetMotion
extends RefCounted

## Stateful motion for one target, advanced at the fixed simulation rate.
##
## Models are selected by id from `MotionSpec.model_id`. Each model changes only how
## velocity is produced; position integration, corridor clamping, interpolation and
## determinism are shared, so a new model cannot accidentally break frame-rate
## independence or leave the arena.
##
## Corridor clamping deserves a note. A strafing target that wanders out of its
## spawn cone stops being a training target and becomes scenery: it drifts behind the
## player or off the arena. Every model is therefore clamped to a lateral corridor
## derived from the spawn geometry (half-width = distance × tan(azimuth range)) and to
## a vertical band derived from the elevation range.

## Context handed to the motion model each step.
class Context extends RefCounted:
	## Player eye position (world).
	var player_position: Vector3 = Vector3.ZERO
	## Player's current view direction (world, normalised).
	var player_forward: Vector3 = Vector3.FORWARD
	var player_velocity: Vector3 = Vector3.ZERO
	## Seconds since the target spawned.
	var age: float = 0.0
	## True while the target is in its spawn fade-in.
	var fading_in: bool = false

var model_id: String = "stationary"
var spec: MotionSpec = null

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Position used by the renderer and by hit tests, interpolated between steps.
var interpolated: Vector3 = Vector3.ZERO
var origin: Vector3 = Vector3.ZERO

var _previous: Vector3 = Vector3.ZERO
var _rng: VantaRng = null
var _lateral_axis: Vector3 = Vector3.RIGHT
var _up_axis: Vector3 = Vector3.UP
var _forward_axis: Vector3 = Vector3.FORWARD
var _corridor: float = 2.0
var _vertical_band: float = 0.5
var _direction: float = 1.0
var _timer: float = 0.0
var _elapsed: float = 0.0
var _speed: float = 1.0
var _target_speed: float = 1.0
var _spike_remaining: float = 0.0
var _reaction_timer: float = 0.0
var _airborne_phase: float = 0.0
var _peek: PeekController = null
var _has_peek: bool = false
var _period: float = 1.2
var _phase_offset: float = 0.0


func setup(motion_spec: MotionSpec, reaction_spec: ReactionSpec, rng: VantaRng, spawn_position: Vector3, view_forward: Vector3, corridor: float, vertical_band: float, lateral_hint: Vector3 = Vector3.ZERO) -> void:
	spec = motion_spec
	model_id = motion_spec.model_id
	_rng = rng
	origin = spawn_position
	position = spawn_position
	_previous = spawn_position
	interpolated = spawn_position
	_corridor = maxf(0.1, corridor)
	_vertical_band = maxf(0.05, vertical_band)

	# Movement axes are derived from the direction the player was looking at spawn,
	# so a strafe is always lateral *relative to the player* and never along the
	# view direction (which would change apparent size instead of requiring a track).
	_forward_axis = -view_forward.normalized()
	_up_axis = Vector3.UP
	_lateral_axis = _up_axis.cross(_forward_axis).normalized()
	if _lateral_axis.length_squared() < 0.5:
		_lateral_axis = Vector3.RIGHT
	# A peek target moves along the axis its cover permits, not along the axis that
	# happens to be lateral to the player: an anchor beside a wall dictates which way
	# the target can actually step out. The authored axis is flattened so a peek can
	# never gain height.
	if lateral_hint.length_squared() > 0.5:
		var flattened := Vector3(lateral_hint.x, 0.0, lateral_hint.z).normalized()
		if flattened.length_squared() > 0.5:
			_lateral_axis = flattened

	_direction = -1.0 if _rng.chance("motion", 0.5) else 1.0
	_speed = _rng.roll_range("motion", spec.speed.x, spec.speed.y)
	_target_speed = _speed
	_timer = _rng.roll_range("motion", spec.direction_duration.x, spec.direction_duration.y)
	# A sinusoidal strafe reverses every half period, so the period is twice the
	# authored direction duration: the author's number keeps meaning "how long before
	# the target changes direction".
	_period = maxf(0.2, 2.0 * _timer)
	_phase_offset = _rng.roll_range("motion", 0.0, TAU)
	_elapsed = 0.0
	_spike_remaining = 0.0
	_reaction_timer = 0.0
	_airborne_phase = 0.0
	_has_peek = model_id == "peek"
	if _has_peek:
		_peek = PeekController.new()
		# An authored axis (from a spawn anchor) names the direction the target steps
		# out in, so the peek side is fixed. Without one, the target may peek either
		# way and the arena must offer cover on both sides.
		var peek_side := 0.0 if lateral_hint.length_squared() < 0.5 else 1.0
		_peek.setup(spec, reaction_spec, rng, origin, _lateral_axis, _corridor, peek_side)


## Advances one fixed simulation step.
func step(dt: float, context: Context) -> void:
	_previous = position
	_elapsed += dt
	if _has_peek and _peek != null:
		position = _peek.advance(dt, context)
		velocity = _peek.velocity
		interpolated = _previous.lerp(position, 0.0)
	else:
		match model_id:
			"stationary":
				_velocity_stationary(dt)
			"linear":
				_velocity_linear(dt)
			"smooth_strafe":
				_velocity_smooth_strafe(dt, 1.0)
			"short_strafe":
				_velocity_timed_strafe(dt, 0.55)
			"long_strafe":
				_velocity_timed_strafe(dt, 1.8)
			"acceleration_strafe":
				_velocity_acceleration_strafe(dt, 1.0)
			"deceleration_strafe":
				_velocity_acceleration_strafe(dt, -1.0)
			"reactive_strafe":
				_velocity_reactive_strafe(dt, context)
			"erratic":
				_velocity_erratic(dt)
			"airborne":
				_velocity_airborne(dt)
			"arc":
				_velocity_arc(dt)
			_:
				_velocity_stationary(dt)
		position += velocity * dt
		_clamp_inside_corridor()
	interpolated = position


## Called after a simulation step to produce the rendered position.
func update_interpolated(alpha: float) -> void:
	interpolated = _previous.lerp(position, clampf(alpha, 0.0, 1.0))


## True when the model has settled and would not need interpolation.
func is_still() -> bool:
	return model_id == "stationary"


# --- models ----------------------------------------------------------------

func _velocity_stationary(_dt: float) -> void:
	velocity = Vector3.ZERO


func _velocity_linear(_dt: float) -> void:
	velocity = _lateral_axis * _speed * _direction * spec.lateral_only


func _velocity_smooth_strafe(_dt: float, _frequency_scale: float) -> void:
	# Sinusoidal lateral motion: constant speed with smooth reversals. This is the
	# "smooth strafe" a player meets when an opponent holds A/D without stopping.
	# `_period` is fixed at spawn so the motion is a pure function of elapsed time and
	# therefore identical at every frame rate.
	var omega: float = TAU / maxf(_period, 0.2)
	var amplitude: float = clampf(_speed / maxf(omega, 0.001), 0.05, _corridor)
	var phase: float = _elapsed * omega + _phase_offset
	var offset: float = sin(phase) * amplitude
	position = origin + _lateral_axis * (offset * spec.lateral_only)
	velocity = _lateral_axis * (cos(phase) * amplitude * omega * spec.lateral_only)


func _velocity_timed_strafe(dt: float, duration_scale: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		var duration := _rng.roll_range("motion", spec.direction_duration.x, spec.direction_duration.y) * duration_scale
		_timer = duration
		if _rng.chance("motion", spec.direction_change_probability):
			# Reverse, but with a small chance of a same-direction "hold" so the
			# rhythm is not a perfect metronome.
			_direction = -_direction
			_target_speed = _rng.roll_range("motion", spec.speed.x, spec.speed.y)
		else:
			_timer = duration * 0.5
	if spec.acceleration <= 0.0:
		_speed = _target_speed
	else:
		var max_delta: float = spec.acceleration * dt
		_speed = move_toward(_speed, _target_speed, max_delta)
	velocity = _lateral_axis * _speed * _direction * spec.lateral_only
	velocity.y += _vertical_component()


func _velocity_acceleration_strafe(dt: float, ease: float) -> void:
	# ease > 0: ramp up to speed (acceleration strafe), ease < 0: bleed off speed
	# towards the corridor edge (deceleration strafe).
	_timer -= dt
	var reversal_zone: float = _corridor * 0.35
	var offset := (position - origin).dot(_lateral_axis)
	var near_edge := absf(offset) > (_corridor - reversal_zone)
	if _timer <= 0.0 or near_edge:
		_timer = _rng.roll_range("motion", spec.direction_duration.x, spec.direction_duration.y)
		_direction = -_direction
	var target_speed := _rng.roll_range("motion", spec.speed.x, spec.speed.y)
	if ease < 0.0:
		var edge_factor: float = clampf(absf(offset) / maxf(_corridor, 0.001), 0.15, 1.0)
		_speed = target_speed * edge_factor
	else:
		_speed = move_toward(_speed, target_speed, spec.acceleration * dt)
	velocity = _lateral_axis * _speed * _direction * spec.lateral_only
	velocity.y += _vertical_component()


func _velocity_reactive_strafe(dt: float, context: Context) -> void:
	_velocity_smooth_strafe(dt, 1.0)
	_reaction_timer = maxf(0.0, _reaction_timer - dt)
	if spec.reactivity <= 0.0 or _reaction_timer > 0.0:
		return
	# Reaction trigger: how close the player's crosshair is to the target, measured
	# in degrees. Reacting to *aim*, not to a timer, is what makes this model feel
	# adversarial without being able to read the player's mind (it only ever sees
	# what a real opponent could see: where the weapon is pointing).
	var to_target := (position - context.player_position).normalized()
	var angle := MathX.angle_between(context.player_forward, to_target)
	if angle > 6.0:
		return
	var chance: float = spec.reactivity * dt * 2.5
	if not _rng.chance("reaction", chance):
		return
	_direction = -_direction
	_reaction_timer = spec.reaction_cooldown
	# A reactive target also alters speed, which prevents "read the rhythm" play.
	_speed = _rng.roll_range("motion", spec.speed.x, spec.speed.y)


func _velocity_erratic(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = _rng.roll_range("motion", spec.direction_duration.x * 0.4, spec.direction_duration.y * 0.6)
		if _rng.chance("motion", spec.direction_change_probability):
			_direction = -_direction
		_speed = _rng.roll_range("motion", spec.speed.x, spec.speed.y)
	if _spike_remaining > 0.0:
		_spike_remaining -= dt
	elif _rng.chance("motion", spec.jerk_probability * dt):
		_spike_remaining = _rng.roll_range("motion", 0.08, 0.28)
	var speed := _speed * (spec.jerk_multiplier if _spike_remaining > 0.0 else 1.0)
	velocity = _lateral_axis * speed * _direction * spec.lateral_only
	velocity.y += _vertical_component()


func _velocity_airborne(dt: float) -> void:
	# A sequence of parabolic hops with lateral drift, then a landing pause. The
	# vertical motion is what makes this different from a ground strafe: the player
	# has to track through a size change as well as a lateral offset.
	_airborne_phase += dt
	var duration: float = maxf(0.2, spec.arc_duration)
	var flight: float = duration * 0.75
	var ground_time: float = duration * 0.25
	var cycle: float = fmod(_airborne_phase, duration)
	if cycle > flight:
		velocity = Vector3.ZERO
		position.y = lerpf(position.y, origin.y, minf(1.0, (cycle - flight) / ground_time))
		return
	var progress: float = cycle / flight
	var height: float = 4.0 * spec.arc_height * progress * (1.0 - progress)
	var vertical_velocity: float = 4.0 * spec.arc_height * (1.0 - 2.0 * progress) / flight
	position.y = origin.y + height
	velocity = _lateral_axis * _speed * _direction * spec.lateral_only + Vector3.UP * vertical_velocity


func _velocity_arc(dt: float) -> void:
	# A smooth arc: lateral traversal while rising and falling once per period.
	_airborne_phase += dt
	var period: float = maxf(0.3, spec.arc_duration)
	var omega: float = TAU / period
	var amplitude: float = clampf(_speed / maxf(omega, 0.001), 0.0, _corridor)
	var offset: float = sin(_airborne_phase * omega) * amplitude
	position = origin + _lateral_axis * (offset * spec.lateral_only)
	position.y = origin.y + spec.arc_height * (0.5 - 0.5 * cos(_airborne_phase * omega * 0.5)) * spec.vertical_influence
	velocity = _lateral_axis * (cos(_airborne_phase * omega) * amplitude * omega * spec.lateral_only)


func _vertical_component() -> float:
	if spec.vertical_influence <= 0.0:
		return 0.0
	# A small vertical bounce driven by the same phase as the strafe, so motion is
	# two-dimensional without being random noise.
	return sin(_elapsed * 2.2) * spec.vertical_influence * 0.6


# --- helpers ---------------------------------------------------------------

func _clamp_inside_corridor() -> void:
	var offset := position - origin
	var lateral := clampf(offset.dot(_lateral_axis), -_corridor, _corridor)
	var vertical := clampf(offset.y, -_vertical_band, _vertical_band)
	var depth := clampf(offset.dot(_forward_axis), -_vertical_band * 2.0, _vertical_band * 2.0)
	position = origin + _lateral_axis * lateral + Vector3.UP * vertical + _forward_axis * depth
	# Turn away from the corridor edge. Without this a target can pin itself against
	# the boundary and stop being a moving target mid-drill.
	if absf(lateral) >= _corridor * 0.98 and lateral * _direction > 0.0:
		_direction = -_direction
		_timer = maxf(_timer, 0.15)


func snapshot() -> Dictionary:
	return {
		"model": model_id,
		"position": [position.x, position.y, position.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"direction": _direction,
		"speed": _speed,
	}


# --- peek integration ------------------------------------------------------

func is_peeking() -> bool:
	return _has_peek and _peek != null


func peek_state_label() -> String:
	if _has_peek and _peek != null:
		return _peek.state_label()
	return ""


func peek_behaviour_label() -> String:
	if _has_peek and _peek != null:
		return _peek.behaviour_label()
	return ""


func is_exposed_from_cover() -> bool:
	if _has_peek and _peek != null:
		return _peek.is_exposed()
	return true


func is_partially_hidden() -> bool:
	if _has_peek and _peek != null:
		return _peek.partially_hidden
	return false
