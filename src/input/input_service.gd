class_name InputService
extends Node

## The single entry point for player input.
##
## Responsibilities:
##  - Own the mouse-motion accumulator. Nothing else in the codebase reads
##    `InputEventMouseMotion` directly, so there is exactly one place where a delta
##    can be scaled, and that place applies the user's sensitivity and nothing else.
##  - Turn raw counts into an angular delta (degrees of yaw/pitch) exactly once per
##    frame, using `VantaSensitivity`. No smoothing, no acceleration, no clamping of
##    accumulated motion other than the pitch limit applied by the rig.
##  - Timestamp discrete combat input (fire / ADS) at the moment the engine delivers
##    it, so the shot is resolved in the same frame it was pressed.
##  - Feed `InputDiagnostics`.
##
## What this class deliberately does NOT do: apply any curve, filter, dead zone or
## interpolation to mouse movement. If a value is modified, it is in `VantaSettings`
## and it is visible to the player.

signal fire_pressed()
signal fire_released()
signal aim_pressed()
signal aim_released()
signal action_pressed(action: String)
signal action_released(action: String)

## Actions that are one-shot by nature; they are forwarded as `action_pressed`.
const DISCRETE_ACTIONS: Array[String] = [
	"restart_step", "next_step", "pause", "focus_mode", "toggle_hud",
	"diagnostics", "toggle_fullscreen", "screenshot", "reload",
]

## Set by the app: true while mouse look should be captured (in training).
var capture_mouse: bool = false:
	set(value):
		if capture_mouse == value:
			return
		capture_mouse = value
		_apply_mouse_mode()

var diagnostics: InputDiagnostics = InputDiagnostics.new()

var _look_accum: Vector2 = Vector2.ZERO
var _bindings: Dictionary = {}
var _last_frame_look: Vector2 = Vector2.ZERO

## Mouse delta of the most recent frame in counts, exposed for the rig and for
## movement-accuracy modelling (shooting while moving).
var last_frame_delta: Vector2:
	get:
		return _last_frame_look


func _ready() -> void:
	# Engine coalescing is disabled so that every delivered motion event reaches
	# `_input`. Rotation is identical either way (VANTA sums the deltas itself), but
	# per-event delivery makes the event-rate diagnostics real and keeps sub-frame
	# timing available for future frame-pacing work.
	Input.use_accumulated_input = false
	apply_bindings(InputBindings.default_bindings())
	diagnostics.reset()
	set_process(true)


func apply_bindings(table: Dictionary) -> void:
	var sanitised: Dictionary = InputBindings.sanitise(table)
	_bindings = sanitised["bindings"]
	InputBindings.apply_to_input_map(_bindings)
	for repair in sanitised["repairs"]:
		VantaLog.warn("input", String(repair))


func bindings() -> Dictionary:
	return _bindings


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# `relative` is what the operating system reported for this event. VANTA
		# never rescales it here; scaling happens once, in `consume_angular_delta`.
		_look_accum += motion.relative
		if capture_mouse:
			diagnostics.on_motion(motion.relative)
		return

	# Discrete combat and interface actions are resolved *here*, not in `_process`:
	# a click that arrives during this frame must be able to produce a shot in the
	# same frame. `is_action_pressed` respects the InputMap we installed, so a user
	# who rebound fire to a keyboard key gets identical behaviour.
	if event.is_action_pressed("fire"):
		fire_pressed.emit()
		return
	if event.is_action_released("fire"):
		fire_released.emit()
		return
	if event.is_action_pressed("aim"):
		aim_pressed.emit()
		return
	if event.is_action_released("aim"):
		aim_released.emit()
		return
	for action in DISCRETE_ACTIONS:
		if event.is_action_pressed(action):
			action_pressed.emit(action)
			return


## Frames are sampled once per rendered frame by the HUD/diagnostics owner.
func sample_frame(motion_delta: Vector2) -> void:
	diagnostics.on_frame(motion_delta)


## Returns the accumulated mouse motion for this frame and clears the accumulator.
## Called exactly once per frame by the player rig.
func consume_look_delta() -> Vector2:
	var delta := _look_accum
	_look_accum = Vector2.ZERO
	_last_frame_look = delta
	return delta


## Converts a mouse delta (counts) into a yaw/pitch delta (degrees).
##
## This is the only conversion in the product. `zoom_multiplier` is 1.0 unless the
## player is aiming down sights and has enabled FOV-based zoom scaling.
static func delta_to_angles(delta: Vector2, settings: VantaSettings, zoom_multiplier: float = 1.0) -> Vector2:
	var yaw_per_count := VantaSensitivity.yaw_per_count(settings.sensitivity, settings.yaw_coefficient)
	if settings.ads_zoom_scaling:
		yaw_per_count *= maxf(zoom_multiplier, 0.0)
	return VantaSensitivity.rotation_for_delta(delta, yaw_per_count, settings.vertical_scale, settings.invert_y)


## Combat buttons: the *press* arrives as a signal from `_input`; holding the button
## is polled here so automatic weapons can fire continuously without the engine
## generating a signal per frame.
func poll_combat() -> void:
	pass


func is_firing() -> bool:
	return Input.is_action_pressed("fire")


func is_aiming() -> bool:
	return Input.is_action_pressed("aim")


func _process(delta: float) -> void:
	sample_frame(last_frame_delta)
	if delta < 0.0:
		return


func _apply_mouse_mode() -> void:
	if capture_mouse:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func release_mouse() -> void:
	capture_mouse = false


func grab_mouse() -> void:
	capture_mouse = true
