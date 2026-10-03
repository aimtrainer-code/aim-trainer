class_name PeekController
extends RefCounted

## Peek behaviour for Peek Lab: decides when, how far and how fast a target exposes
## itself from behind cover.
##
## This is VANTA's flagship tactical feature, so the model is explicit rather than a
## random teleport. One peek cycle is:
##
##   hidden hold → exposure (chosen distance and speed) → exposed hold → retreat →
##   maybe re-peek after a new delay
##
## Difficulty comes from *controlled variation*: side, delay, peek distance, stance
## and the timing of the next peek are randomised inside ranges the scenario author
## chose. A player can never memorise the timing, but the distribution is knowable —
## which is how a real opponent behaves. Unbounded RNG (teleporting, or timings
## unrelated to the previous peek) is deliberately avoided: it would train
## pattern-breaking rather than counter-play.
##
## The controller has no opinion about geometry: it moves along the peek axis it is
## given. Cover itself comes from the arena, and a peek that is not actually occluded
## by that cover is a scenario/arena authoring error, surfaced by the arena validator.

enum Behaviour { SHORT_PEEK, WIDE_SWING, JIGGLE, SHOULDER, CROUCH_PEEK, DELAYED_PEEK, RE_PEEK, CHANGE_RHYTHM }
enum State { HIDDEN_HOLD, EXPOSING, EXPOSED_HOLD, RETREATING, FINISHED }

const BEHAVIOUR_IDS: Array[String] = [
	"short_peek", "wide_swing", "jiggle", "shoulder", "crouch_peek",
	"delayed_peek", "re_peek", "change_rhythm",
]
const BEHAVIOUR_LABELS: Array[String] = [
	"SHORT PEEK", "WIDE SWING", "JIGGLE", "SHOULDER", "CROUCH PEEK",
	"DELAYED PEEK", "RE-PEEK", "CHANGE RHYTHM",
]

## How the peek geometry is derived from the arena's corridor width. These are
## constants rather than magic numbers because scenario authors (and the content tests)
## need to compute exactly where a peek target will be.
const EXPOSE_OFFSET_FACTOR: float = 0.45
const EXPOSE_OFFSET_MIN: float = 0.25
const EXPOSE_OFFSET_MAX: float = 2.5
const HIDDEN_OFFSET_FACTOR: float = 0.7
const HIDDEN_OFFSET_MIN: float = 0.4
const HIDDEN_OFFSET_MAX: float = 3.5
## Fraction of the hidden offset that the waiting position actually uses.
const HIDDEN_HOLD_FACTOR: float = 0.35

## Distance behind cover at which the target waits, in metres.
var hidden_offset: float = 1.2
## How far out of cover the target travels at full exposure, in metres.
var expose_offset: float = 0.9
## Peak crossing speed, in metres per second.
var peek_speed: float = 4.2

var behaviour: int = Behaviour.SHORT_PEEK
var state: int = State.HIDDEN_HOLD
var velocity: Vector3 = Vector3.ZERO
## True while any part of the target is still occluded by cover.
var partially_hidden: bool = true
## Completed exposures in this chain.
var peek_count: int = 0

var _rng: VantaRng = null
var _spec: MotionSpec = null
var _reaction: ReactionSpec = null
var _origin: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3.RIGHT
var _side: float = 1.0
## When non-zero the peek always steps to this side of the axis. An anchor authors
## the direction its target steps out in, so an anchored peek must not randomly step
## the other way (which would leave the target permanently hidden).
var _fixed_side: float = 0.0
var _timer: float = 0.0
var _progress: float = 0.0
var _exposed: bool = false
var _crouch_depth: float = 0.0
var _crouch_active: bool = false
var _jitter: float = 0.0
var _pending_reengage: bool = false


func setup(spec: MotionSpec, reaction: ReactionSpec, rng: VantaRng, origin: Vector3, lateral_axis: Vector3, corridor: float, fixed_side: float = 0.0) -> void:
	_spec = spec
	_reaction = reaction
	_rng = rng
	_origin = origin
	_axis = lateral_axis
	# Offsets scale with the arena's corridor so the same scenario works in a narrow
	# lane and in a wide room.
	expose_offset = clampf(corridor * EXPOSE_OFFSET_FACTOR, EXPOSE_OFFSET_MIN, EXPOSE_OFFSET_MAX)
	hidden_offset = clampf(corridor * HIDDEN_OFFSET_FACTOR, HIDDEN_OFFSET_MIN, HIDDEN_OFFSET_MAX)
	_fixed_side = clampf(fixed_side, -1.0, 1.0)
	var span: Vector2 = spec.speed
	peek_speed = maxf(0.5, rng.roll_range("motion", span.x, span.y) if span.y > 0.0 else 4.2)
	_timer = _initial_delay()


## Advances one fixed step and returns the new world position.
func advance(dt: float, _context: TargetMotion.Context) -> Vector3:
	match state:
		State.HIDDEN_HOLD:
			_tick_hidden(dt)
		State.EXPOSING:
			_tick_exposing(dt)
		State.EXPOSED_HOLD:
			_tick_exposed(dt)
		State.RETREATING:
			_tick_retreating(dt)
		State.FINISHED:
			velocity = Vector3.ZERO
	return _position_for_state()


func _initial_delay() -> float:
	# The first peek always waits: the player must acquire the angle before anything
	# happens, otherwise every drill would start with a jump-scare.
	var base := _rng.roll_range("motion", 0.5, 1.1)
	if _spec != null and _spec.peek_behaviour == "delayed_peek":
		base += _rng.roll_range("motion", 0.6, 1.8)
	return base


func _choose_behaviour() -> void:
	if _spec != null and not _spec.peek_behaviour.is_empty() and _spec.peek_behaviour != "auto":
		var index := BEHAVIOUR_IDS.find(_spec.peek_behaviour)
		if index >= 0:
			behaviour = index
			return
	var weights := [1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.6, 0.6]
	if peek_count > 0:
		# After the first peek the controller leans towards variation. This is what
		# makes a Peek Lab target feel like a thinking opponent: it does not repeat the
		# same timing twice in a row, but it does stay consistent enough to read.
		weights[Behaviour.CHANGE_RHYTHM] *= 1.8
		weights[Behaviour.RE_PEEK] *= 1.5
		weights[Behaviour.SHORT_PEEK] *= 0.7
	var picked := _rng.pick_weighted("motion", weights)
	behaviour = picked if picked >= 0 else Behaviour.SHORT_PEEK


func _tick_hidden(dt: float) -> void:
	velocity = Vector3.ZERO
	_timer -= dt
	if _timer > 0.0:
		return
	_choose_behaviour()
	if not is_zero_approx(_fixed_side):
		_side = _fixed_side
	else:
		_side = -1.0 if _rng.chance("motion", 0.5) else 1.0
	_crouch_active = behaviour == Behaviour.CROUCH_PEEK
	_crouch_depth = 0.0
	_jitter = 0.0
	_exposed = false
	partially_hidden = true
	_pending_reengage = false
	state = State.EXPOSING
	_progress = 0.0
	# Travel time follows from distance and speed: a wide swing takes longer than a
	# shoulder peek, which is a genuine tactical trade-off rather than a magic delay.
	_timer = maxf(0.05, _travel_distance() / maxf(peek_speed, 0.2))


func _travel_time() -> float:
	return maxf(0.05, _travel_distance() / maxf(peek_speed, 0.2))


func _tick_exposing(dt: float) -> void:
	_timer -= dt
	_progress = clampf(_progress + dt / maxf(_travel_time(), 0.0001), 0.0, 1.0)
	var eased := MathX.smoothstep01(_progress)
	velocity = _axis * (_side * expose_offset * (1.0 - eased) * 4.0)
	if _crouch_active:
		_crouch_depth = eased * 0.42
	partially_hidden = eased < (0.45 if behaviour == Behaviour.SHOULDER else 0.25)
	if _progress >= 1.0:
		state = State.EXPOSED_HOLD
		_exposed = true
		_timer = _exposed_duration()
		peek_count += 1


func _tick_exposed(dt: float) -> void:
	velocity = Vector3.ZERO
	_timer -= dt
	if behaviour == Behaviour.JIGGLE:
		# Jiggle: repeated small in/out motions while staying nearly exposed. Rewards
		# holding the angle instead of waiting for a full swing.
		_progress += dt / maxf(_travel_time(), 0.0001)
		_jitter = sin(_progress * TAU * 3.0) * 0.12
		partially_hidden = false
	if _timer > 0.0:
		return
	state = State.RETREATING
	_progress = 0.0
	_timer = _travel_time() * 0.85


func _tick_retreating(dt: float) -> void:
	_timer -= dt
	_progress = clampf(_progress + dt / maxf(_travel_time(), 0.0001), 0.0, 1.0)
	var eased := MathX.smoothstep01(_progress)
	velocity = -_axis * (_side * expose_offset * eased * 4.0)
	_jitter = 0.0
	if _crouch_active:
		_crouch_depth = (1.0 - eased) * 0.42
	partially_hidden = eased > 0.6
	if _progress >= 1.0:
		_exposed = false
		_crouch_depth = 0.0
		_pending_reengage = _rng.chance("motion", _reengage_chance())
		state = State.HIDDEN_HOLD
		_timer = _next_hidden_delay()


func _next_hidden_delay() -> float:
	var span := _reengage_delay()
	if _pending_reengage:
		return _rng.roll_range("motion", span.x, span.y)
	# Without a re-peek the target stays down for a realistic lull rather than
	# instantly popping back up, but always comes back: a Peek Lab scenario must never
	# dead-end waiting for a target that will not return.
	var lull := 0.5
	if _spec != null:
		lull = clampf(_spec.direction_duration.x, 0.4, 3.0)
	return _rng.roll_range("motion", lull, lull * 1.8)


func _reengage_chance() -> float:
	if _reaction == null:
		return 0.0
	return _reaction.reengage_chance


func _reengage_delay() -> Vector2:
	if _reaction == null:
		return Vector2(0.2, 0.9)
	return _reaction.reengage_delay


func _exposed_duration() -> float:
	match behaviour:
		Behaviour.SHORT_PEEK:
			return _rng.roll_range("motion", 0.25, 0.45)
		Behaviour.WIDE_SWING:
			return _rng.roll_range("motion", 0.75, 1.4)
		Behaviour.JIGGLE:
			return _rng.roll_range("motion", 0.8, 1.6)
		Behaviour.SHOULDER:
			return _rng.roll_range("motion", 0.3, 0.6)
		Behaviour.CROUCH_PEEK:
			return _rng.roll_range("motion", 0.6, 1.1)
		Behaviour.DELAYED_PEEK:
			return _rng.roll_range("motion", 0.5, 0.9)
		Behaviour.RE_PEEK:
			return _rng.roll_range("motion", 0.4, 0.8)
		_:
			return _rng.roll_range("motion", 0.3, 1.2)


func _travel_distance() -> float:
	match behaviour:
		Behaviour.WIDE_SWING:
			return expose_offset * 1.6
		Behaviour.SHOULDER:
			return expose_offset * 0.45
		Behaviour.CROUCH_PEEK:
			return expose_offset * 0.8
		_:
			return expose_offset


## Current exposure in metres from behind cover (0 = fully hidden).
func exposure() -> float:
	match state:
		State.HIDDEN_HOLD, State.FINISHED:
			return 0.0
		State.EXPOSING, State.RETREATING:
			return expose_offset * MathX.smoothstep01(_progress)
		_:
			return expose_offset


func _position_for_state() -> Vector3:
	var base := _origin
	var lateral := 0.0
	match state:
		State.HIDDEN_HOLD, State.FINISHED:
			lateral = -_side * hidden_offset * HIDDEN_HOLD_FACTOR
		State.EXPOSING, State.EXPOSED_HOLD:
			lateral = _side * expose_offset * MathX.smoothstep01(_progress)
		State.RETREATING:
			lateral = _side * expose_offset * (1.0 - MathX.smoothstep01(_progress)) * 0.85
	base += _axis * (lateral + _jitter)
	base.y -= _crouch_depth
	return base


func is_exposed() -> bool:
	return _exposed


func behaviour_label() -> String:
	return BEHAVIOUR_LABELS[clampi(behaviour, 0, BEHAVIOUR_LABELS.size() - 1)]


func state_label() -> String:
	match state:
		State.HIDDEN_HOLD:
			return "HIDDEN"
		State.EXPOSING:
			return "EXPOSING"
		State.EXPOSED_HOLD:
			return "EXPOSED"
		State.RETREATING:
			return "RETREATING"
		_:
			return "DONE"
