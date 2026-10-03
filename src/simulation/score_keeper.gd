class_name ScoreKeeper
extends RefCounted

## Applies `ScoreSpec` to events. Pure integer arithmetic, no floating point, so two
## identical runs always produce identical numbers and a score cannot drift by a
## rounding error between platforms.
##
## Anti-farming review (docs/SCORING.md walks through each scenario):
##   - Every positive term is tied to a target that was actually acquired.
##   - `miss_penalty` and `max_shots_per_target` remove the incentive to spray at a
##     spawn point; spawn positions are randomised anyway (SpawnDirector), so
##     pre-aiming a fixed location is not a strategy.
##   - `time_bonus_*` rewards fast *resolution*, which cannot be increased by firing
##     more shots (each shot costs spread and, when configured, accuracy).
##   - Streak bonuses are capped, so a lucky run cannot run away with the score.

var spec: ScoreSpec = null
var score: int = 0
var streak: int = 0
## Breakdown for the results screen: what actually contributed, in order of size.
var breakdown: Dictionary = {}


func _init(score_spec: ScoreSpec = null) -> void:
	spec = score_spec
	reset()


func reset() -> void:
	score = 0
	streak = 0
	breakdown = {}


func _add(term: String, value: int) -> void:
	if value == 0:
		return
	score += value
	breakdown[term] = int(breakdown.get(term, 0)) + value


func register_hit(is_headshot: bool, damage_ratio: float = 1.0) -> int:
	if spec == null:
		return 0
	var before := score
	var points := spec.hit_points
	if is_headshot:
		points += spec.headshot_points
	if damage_ratio < 1.0:
		points = int(round(float(points) * clampf(damage_ratio, 0.0, 1.0)))
	_add("hit", points)
	return score - before


func register_elimination(time_to_kill: float, is_headshot: bool) -> int:
	if spec == null:
		return 0
	var before := score
	var points := spec.kill_points
	if is_headshot:
		points += spec.headshot_points
	if spec.time_bonus_base > 0 and time_to_kill >= 0.0:
		var bonus: int = spec.time_bonus_base - int(round(time_to_kill * float(spec.time_bonus_rate)))
		points += maxi(0, bonus)
	if spec.streak_bonus > 0:
		points += spec.streak_bonus * mini(streak, spec.streak_cap)
	streak += 1
	_add("elimination", points)
	return score - before


func register_miss() -> int:
	if spec == null:
		return 0
	var before := score
	_add("miss_penalty", -spec.miss_penalty)
	streak = 0
	_apply_floor()
	return score - before


func register_expiry() -> int:
	if spec == null:
		return 0
	var before := score
	_add("expiry_penalty", -spec.expiry_penalty)
	streak = 0
	_apply_floor()
	return score - before


## Tracking drills accrue score from time on target, applied in whole steps so the
## score stays an integer.
func register_tracking(seconds: float, on_target: bool) -> void:
	if spec == null:
		return
	if on_target and spec.tracking_points_per_second > 0:
		_add("tracking", int(round(seconds * float(spec.tracking_points_per_second))))
	elif not on_target and spec.tracking_off_target_penalty_per_second > 0:
		_add("off_target", -int(round(seconds * float(spec.tracking_off_target_penalty_per_second))))
		_apply_floor()


## Accuracy bonus is applied once, at the end of the attempt, from the final stats.
func apply_accuracy_bonus(accuracy_percent: float) -> void:
	if spec == null or spec.accuracy_bonus_rate <= 0:
		return
	_add("accuracy_bonus", int(round(accuracy_percent * float(spec.accuracy_bonus_rate) / 100.0)))


func _apply_floor() -> void:
	if spec == null:
		return
	if score < spec.score_floor:
		score = spec.score_floor


func breakdown_sorted() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key in breakdown.keys():
		entries.append({"term": String(key), "value": int(breakdown[key])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absi(int(a["value"])) > absi(int(b["value"]))
	)
	return entries
