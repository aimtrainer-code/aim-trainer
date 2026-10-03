class_name SuccessSpec
extends RefCounted

## What counts as a successful attempt.
##
## A scenario always produces a result object; "success" is a separate judgement used
## by the curriculum, by qualifications and by the adaptive difficulty rules. Keeping
## the requirements in data means a coach can publish a drill with their own pass
## line, and the same drill can be reused at several levels by tightening the numbers.
##
## A requirement value of 0 disables that requirement. If every requirement is
## disabled the scenario can never be "passed", which is valid (score-only practice)
## and is reported as a warning so authors notice.

var min_accuracy: float = 0.0  ## percent, 0-100
var min_score: int = 0
var max_average_time_to_kill: float = 0.0  ## seconds, 0 = disabled
var min_headshot_ratio: float = 0.0  ## percent, 0-100
var min_targets: int = 0
var max_misses: int = 0
var min_consistency: float = 0.0  ## percent of rounds within a variance band

var errors: Array[String] = []
var warnings: Array[String] = []


static func from_dict(data: Variant) -> SuccessSpec:
	var spec := SuccessSpec.new()
	var source := SpecParse.dict(data)
	var label := "success"
	spec.min_accuracy = SpecParse.float_value(source, "min_accuracy", 0.0, 0.0, 100.0, spec.errors, label)
	spec.min_score = SpecParse.int_value(source, "min_score", 0, 0, 10000000, spec.errors, label)
	spec.max_average_time_to_kill = SpecParse.float_value(source, "max_average_time_to_kill", 0.0, 0.0, 60.0, spec.errors, label)
	spec.min_headshot_ratio = SpecParse.float_value(source, "min_headshot_ratio", 0.0, 0.0, 100.0, spec.errors, label)
	spec.min_targets = SpecParse.int_value(source, "min_targets", 0, 0, 100000, spec.errors, label)
	spec.max_misses = SpecParse.int_value(source, "max_misses", 0, 0, 100000, spec.errors, label)
	spec.min_consistency = SpecParse.float_value(source, "min_consistency", 0.0, 0.0, 100.0, spec.errors, label)
	if not spec.any_requirement():
		spec.warnings.append("no success requirement is set, so the attempt can never be passed")
	return spec


func any_requirement() -> bool:
	return min_accuracy > 0.0 or min_score > 0 or max_average_time_to_kill > 0.0 \
		or min_headshot_ratio > 0.0 or min_targets > 0 or max_misses > 0 or min_consistency > 0.0


func to_dict() -> Dictionary:
	return {
		"min_accuracy": min_accuracy,
		"min_score": min_score,
		"max_average_time_to_kill": max_average_time_to_kill,
		"min_headshot_ratio": min_headshot_ratio,
		"min_targets": min_targets,
		"max_misses": max_misses,
		"min_consistency": min_consistency,
	}
