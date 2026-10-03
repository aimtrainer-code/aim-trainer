class_name PlayerState
extends RefCounted

## A snapshot of everything the simulation needs to know about the player for one
## frame or one shot.
##
## The runtime never reaches into the player rig or the scene tree. It receives this
## value object, which means:
##   - the same simulation code runs in a test with a hand-built state and in the
##     game with a real rig;
##   - there is no hidden coupling where a scenario reads the mouse or the camera
##     directly, and therefore no way for a drill to be affected by anything that is
##     not in this struct.

## Eye position in world space.
var position: Vector3 = Vector3.ZERO
## Forward direction of the view, normalised.
var forward: Vector3 = Vector3.FORWARD
var yaw: float = 0.0
var pitch: float = 0.0
## Horizontal speed in metres per second (used by movement-inaccuracy rules).
var speed: float = 0.0
var velocity: Vector3 = Vector3.ZERO
var airborne: bool = false
var crouching: bool = false
var aiming: bool = false
## Latched true while the fire button is held (beam weapons and automatic fire).
var firing: bool = false
## Field of view currently applied, which zoom scaling depends on.
var fov: float = 90.0
## Sensitivity multiplier from zoom/ADS, 1.0 when not zoomed.
var zoom_multiplier: float = 1.0
## Seconds since the session started, for rules that care about time.
var session_time: float = 0.0

## Convenience for tests and for the Rival.
static func make(position_value: Vector3, yaw_value: float, pitch_value: float, fov_value: float = 90.0) -> PlayerState:
	var state := PlayerState.new()
	state.position = position_value
	state.yaw = yaw_value
	state.pitch = pitch_value
	state.forward = MathX.direction_from_angles(yaw_value, pitch_value)
	state.fov = fov_value
	return state


func eye_direction() -> Vector3:
	return MathX.direction_from_angles(yaw, pitch)


func copy() -> PlayerState:
	var state := PlayerState.new()
	state.position = position
	state.forward = forward
	state.yaw = yaw
	state.pitch = pitch
	state.speed = speed
	state.velocity = velocity
	state.airborne = airborne
	state.crouching = crouching
	state.aiming = aiming
	state.firing = firing
	state.fov = fov
	state.zoom_multiplier = zoom_multiplier
	state.session_time = session_time
	return state
