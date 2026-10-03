class_name AdaptiveSpec
extends RefCounted

## Transparent, rule-based difficulty adaptation.
##
## VANTA does not call this "AI". It is a documented control loop with published
## thresholds, visible to the player in the results screen and disableable in
## settings. The rules were chosen to satisfy two constraints:
##
##   1. Stay in the useful challenge band. Too easy produces no learning, too hard
##      produces noise. The default band targets 70-90% success for clicking drills
##      and 55-75% on-target time for tracking drills.
##   2. Never break rhythm. Adjustments are applied only at round or scenario
##      boundaries by default, and are rate-limited so difficulty cannot oscillate
##      from attempt to attempt.
##
## Which parameters may move is explicit: the runtime only touches the fields listed
## in `adjusts`.

const ADJUSTABLE: Array[String] = [
	"target_size", "target_lifetime", "speed", "direction_duration",
	"spawn_angle", "simultaneous_targets", "peek_difficulty",
]

var enabled: bool = false
## Rule set id. `band` keeps success inside a band; `ladder` moves one step at a time
## in a fixed order (used by Zero to Elite and by qualifications).
var rule_id: String = "band"
var difficulty_min: int = 1
var difficulty_max: int = 10
## Step taken per adjustment, expressed as a fraction of the current value.
var step_fraction: float = 0.05
## Success-rate band, in percent.
var target_success_min: float = 70.0
var target_success_max: float = 90.0
## Minimum attempts between adjustments (prevents oscillation).
var min_attempts_between_changes: int = 2
## Maximum number of steps the difficulty may change in a single session.
var max_steps_per_session: int = 3
var adjusts: Array[String] = ["target_size", "target_lifetime"]

var errors: Array[String] = []
var warnings: Array[String] = []


static func from_dict(data: Variant) -> AdaptiveSpec:
	var spec := AdaptiveSpec.new()
	var source := SpecParse.dict(data)
	var label := "adaptive"
	spec.enabled = SpecParse.bool_value(source, "enabled", false)
	spec.rule_id = SpecParse.string_value(source, "rule", "band", 16)
	if not ["band", "ladder", "off"].has(spec.rule_id):
		spec.errors.append("adaptive.rule '%s' is not supported" % spec.rule_id)
	spec.difficulty_min = SpecParse.int_value(source, "difficulty_min", 1, 1, 10, spec.errors, label)
	spec.difficulty_max = SpecParse.int_value(source, "difficulty_max", 10, 1, 10, spec.errors, label)
	if spec.difficulty_min > spec.difficulty_max:
		spec.errors.append("adaptive.difficulty_min is greater than adaptive.difficulty_max")
	spec.step_fraction = SpecParse.float_value(source, "step_fraction", 0.05, 0.005, 0.5, spec.errors, label)
	spec.target_success_min = SpecParse.float_value(source, "target_success_min", 70.0, 0.0, 100.0, spec.errors, label)
	spec.target_success_max = SpecParse.float_value(source, "target_success_max", 90.0, 0.0, 100.0, spec.errors, label)
	if spec.target_success_min >= spec.target_success_max:
		spec.errors.append("adaptive target band is empty (min must be below max)")
	spec.min_attempts_between_changes = SpecParse.int_value(source, "min_attempts_between_changes", 2, 1, 50, spec.errors, label)
	spec.max_steps_per_session = SpecParse.int_value(source, "max_steps_per_session", 3, 0, 20, spec.errors, label)
	if source.has("adjusts"):
		var raw: Variant = source["adjusts"]
		if typeof(raw) == TYPE_ARRAY:
			var cleaned: Array[String] = []
			for item in raw:
				if typeof(item) != TYPE_STRING:
					spec.errors.append("adaptive.adjusts entries must be strings")
					continue
				var value := String(item)
				if not ADJUSTABLE.has(value):
					spec.errors.append("adaptive.adjusts contains unknown parameter '%s'" % value)
					continue
				cleaned.append(value)
			if cleaned.is_empty():
				spec.errors.append("adaptive.adjusts must list at least one parameter")
			spec.adjusts = cleaned
		else:
			spec.errors.append("adaptive.adjusts must be an array")
	if spec.enabled and spec.adjusts.is_empty():
		spec.errors.append("adaptive is enabled but adjusts nothing")
	return spec


func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"rule": rule_id,
		"difficulty_min": difficulty_min,
		"difficulty_max": difficulty_max,
		"step_fraction": step_fraction,
		"target_success_min": target_success_min,
		"target_success_max": target_success_max,
		"min_attempts_between_changes": min_attempts_between_changes,
		"max_steps_per_session": max_steps_per_session,
		"adjusts": adjusts,
	}
