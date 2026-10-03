class_name ScoreSpec
extends RefCounted

## Scoring rules.
##
## Design rule: a high score must correlate with the mechanical ability the scenario
## claims to train. Concretely, in click-timing scenarios the dominant term is
## *time to hit* rather than raw hit count, so a fast accurate player always beats a
## slow accurate player, and neither can be beaten by spraying (miss penalties and
## shot limits take care of the rest).
##
## All terms are integers: no floating point in the score means two identical runs
## always produce identical numbers.

## Points for hitting a target at all (non-lethal hit).
var hit_points: int = 0
## Points for eliminating a target.
var kill_points: int = 100
## Additional points for a headshot.
var headshot_points: int = 50
## Points removed per miss (0 = no penalty).
var miss_penalty: int = 0
## Points removed when a target expires un-hit.
var expiry_penalty: int = 0
## Time-to-kill bonus: `time_bonus_base - round(time * time_bonus_rate)`, floored at
## zero. This is what makes speed matter in clicking scenarios.
var time_bonus_base: int = 0
var time_bonus_rate: int = 0
## Flat bonus per consecutive elimination, capped at `streak_cap` steps.
var streak_bonus: int = 0
var streak_cap: int = 10
## End-of-run accuracy bonus: `round(accuracy_percent * accuracy_bonus_rate)`.
var accuracy_bonus_rate: int = 0
## Damage-per-second style scoring for tracking: points per second spent on target.
var tracking_points_per_second: int = 0
## Points per second spent *off* target (negative to punish sloppiness).
var tracking_off_target_penalty_per_second: int = 0
## Score cannot go below this value (zero or negative).
var score_floor: int = 0

var errors: Array[String] = []
var warnings: Array[String] = []


static func from_dict(data: Variant) -> ScoreSpec:
	var spec := ScoreSpec.new()
	var source := SpecParse.dict(data)
	var label := "scoring"
	spec.hit_points = SpecParse.int_value(source, "hit_points", 0, 0, 10000, spec.errors, label)
	spec.kill_points = SpecParse.int_value(source, "kill_points", 100, 0, 100000, spec.errors, label)
	spec.headshot_points = SpecParse.int_value(source, "headshot_points", 50, 0, 100000, spec.errors, label)
	spec.miss_penalty = SpecParse.int_value(source, "miss_penalty", 0, 0, 10000, spec.errors, label)
	spec.expiry_penalty = SpecParse.int_value(source, "expiry_penalty", 0, 0, 10000, spec.errors, label)
	spec.time_bonus_base = SpecParse.int_value(source, "time_bonus_base", 0, 0, 100000, spec.errors, label)
	spec.time_bonus_rate = SpecParse.int_value(source, "time_bonus_rate", 0, 0, 100000, spec.errors, label)
	spec.streak_bonus = SpecParse.int_value(source, "streak_bonus", 0, 0, 10000, spec.errors, label)
	spec.streak_cap = SpecParse.int_value(source, "streak_cap", 10, 1, 1000, spec.errors, label)
	spec.accuracy_bonus_rate = SpecParse.int_value(source, "accuracy_bonus_rate", 0, 0, 100000, spec.errors, label)
	spec.tracking_points_per_second = SpecParse.int_value(source, "tracking_points_per_second", 0, 0, 10000, spec.errors, label)
	spec.tracking_off_target_penalty_per_second = SpecParse.int_value(source, "tracking_off_target_penalty_per_second", 0, 0, 10000, spec.errors, label)
	spec.score_floor = SpecParse.int_value(source, "floor", 0, -1000000, 1000000, spec.errors, label)

	# Exploit guards. These are the failure modes that would let a scenario be
	# farmed rather than trained, so they are errors rather than warnings.
	if spec.kill_points == 0 and spec.hit_points == 0 and spec.tracking_points_per_second == 0:
		spec.errors.append("scoring has no positive term; the scenario could never award a score")
	if spec.miss_penalty == 0 and spec.time_bonus_base == 0 and spec.time_bonus_rate == 0 and spec.kill_points > 0:
		spec.warnings.append("no miss penalty and no time bonus: spamming may out-score careful aim")
	if spec.streak_bonus > 0 and spec.streak_cap > 200:
		spec.warnings.append("streak_cap above 200 makes streak bonuses dominate the score")
	if spec.score_floor > 0:
		spec.errors.append("scoring.floor must be zero or negative so a bad run cannot be turned into points")
	return spec


func to_dict() -> Dictionary:
	return {
		"hit_points": hit_points,
		"kill_points": kill_points,
		"headshot_points": headshot_points,
		"miss_penalty": miss_penalty,
		"expiry_penalty": expiry_penalty,
		"time_bonus_base": time_bonus_base,
		"time_bonus_rate": time_bonus_rate,
		"streak_bonus": streak_bonus,
		"streak_cap": streak_cap,
		"accuracy_bonus_rate": accuracy_bonus_rate,
		"tracking_points_per_second": tracking_points_per_second,
		"tracking_off_target_penalty_per_second": tracking_off_target_penalty_per_second,
		"floor": score_floor,
	}
