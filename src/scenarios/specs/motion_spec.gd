class_name MotionSpec
extends RefCounted

## Target motion parameters.
##
## Motion models live in `src/simulation/motion/` and are referenced by id. The spec
## carries every parameter a model may need so that community scenarios can tune
## behaviour without new code; a model ignores what it does not use.
##
## Every model is *stateful and stepped at a fixed rate* (see SimClock) rather than
## being evaluated as a raw sine of wall-clock time. That is what allows direction
## changes, acceleration limits and reaction to the player to coexist with
## frame-rate independence.

## Motion model ids, in rough order of difficulty. See docs/TRAINING_DESIGN.md for
## what each model is intended to train.
const MODEL_IDS: Array[String] = [
	"stationary",
	"linear",
	"smooth_strafe",
	"short_strafe",
	"long_strafe",
	"acceleration_strafe",
	"deceleration_strafe",
	"reactive_strafe",
	"erratic",
	"airborne",
	"arc",
	"peek",
]
const MODEL_LABELS: Array[String] = [
	"STATIONARY", "LINEAR", "SMOOTH STRAFE", "SHORT STRAFE", "LONG STRAFE",
	"ACCELERATION STRAFE", "DECELERATION STRAFE", "REACTIVE STRAFE", "ERRATIC",
	"AIRBORNE", "ARC", "PEEK",
]

var model_id: String = "stationary"
## Metres per second.
var speed: Vector2 = Vector2(0.0, 0.0)
var acceleration: float = 12.0
var max_velocity: float = 6.0
## Seconds a direction is held, before the direction-change rule applies.
var direction_duration: Vector2 = Vector2(0.6, 1.2)
## Probability of reversing/changing direction when the timer expires.
var direction_change_probability: float = 1.0
## 0 = horizontal only, 1 = free vertical movement.
var vertical_influence: float = 0.0
## Erratic only: probability per second of an abrupt velocity spike.
var jerk_probability: float = 0.4
## Erratic only: multiplier applied to speed during a spike.
var jerk_multiplier: float = 2.5
## Reactive only: how strongly the target reacts to the player's crosshair being
## close. 0 = ignores the player (a plain strafe), 1 = actively evades.
var reactivity: float = 0.5
## Reactive only: minimum time between reactions, so the target cannot jitter.
var reaction_cooldown: float = 0.35
## Arc/airborne only: peak height of the trajectory, in metres.
var arc_height: float = 1.5
## Arc/airborne only: duration of one arc, in seconds.
var arc_duration: float = 1.4
## Peek only: the peek behaviour id from the arena's cover definition.
var peek_behaviour: String = "auto"
## Restricts motion to the axis of the spawn direction (0 = free, 1 = pure lateral).
var lateral_only: float = 1.0

var errors: Array[String] = []
var warnings: Array[String] = []


static func from_dict(data: Variant) -> MotionSpec:
	var spec := MotionSpec.new()
	var source := SpecParse.dict(data)
	var label := "motion"
	spec.model_id = SpecParse.string_value(source, "model", "stationary", 32).to_lower()
	if not MODEL_IDS.has(spec.model_id):
		spec.errors.append("motion.model '%s' is not a known motion model" % spec.model_id)
		spec.model_id = "stationary"
	spec.speed = SpecParse.range_value(source, "speed", 0.0, 0.0, 0.0, 60.0, spec.errors, label)
	spec.acceleration = SpecParse.float_value(source, "acceleration", 12.0, 0.0, 200.0, spec.errors, label)
	spec.max_velocity = SpecParse.float_value(source, "max_velocity", 6.0, 0.0, 60.0, spec.errors, label)
	spec.direction_duration = SpecParse.range_value(source, "direction_duration", 0.6, 1.2, 0.05, 30.0, spec.errors, label)
	spec.direction_change_probability = SpecParse.float_value(source, "direction_change_probability", 1.0, 0.0, 1.0, spec.errors, label)
	spec.vertical_influence = SpecParse.float_value(source, "vertical_influence", 0.0, 0.0, 1.0, spec.errors, label)
	spec.jerk_probability = SpecParse.float_value(source, "jerk_probability", 0.4, 0.0, 5.0, spec.errors, label)
	spec.jerk_multiplier = SpecParse.float_value(source, "jerk_multiplier", 2.5, 1.0, 10.0, spec.errors, label)
	spec.reactivity = SpecParse.float_value(source, "reactivity", 0.5, 0.0, 1.0, spec.errors, label)
	spec.reaction_cooldown = SpecParse.float_value(source, "reaction_cooldown", 0.35, 0.05, 5.0, spec.errors, label)
	spec.arc_height = SpecParse.float_value(source, "arc_height", 1.5, 0.1, 20.0, spec.errors, label)
	spec.arc_duration = SpecParse.float_value(source, "arc_duration", 1.4, 0.2, 10.0, spec.errors, label)
	spec.peek_behaviour = SpecParse.string_value(source, "peek_behaviour", "auto", 32).to_lower()
	spec.lateral_only = SpecParse.float_value(source, "lateral_only", 1.0, 0.0, 1.0, spec.errors, label)

	if spec.model_id == "reactive_strafe" and spec.reactivity <= 0.0:
		spec.warnings.append("reactive_strafe with reactivity 0 behaves like smooth_strafe")
	if spec.model_id != "stationary" and spec.speed.y <= 0.0:
		spec.errors.append("motion.speed must be greater than zero for a moving model")
	if spec.speed.x > spec.speed.y:
		spec.errors.append("motion.speed min is greater than max")
	return spec


func to_dict() -> Dictionary:
	return {
		"model": model_id,
		"speed": [speed.x, speed.y],
		"acceleration": acceleration,
		"max_velocity": max_velocity,
		"direction_duration": [direction_duration.x, direction_duration.y],
		"direction_change_probability": direction_change_probability,
		"vertical_influence": vertical_influence,
		"jerk_probability": jerk_probability,
		"jerk_multiplier": jerk_multiplier,
		"reactivity": reactivity,
		"reaction_cooldown": reaction_cooldown,
		"arc_height": arc_height,
		"arc_duration": arc_duration,
		"peek_behaviour": peek_behaviour,
		"lateral_only": lateral_only,
	}
