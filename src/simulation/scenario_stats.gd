class_name ScenarioStats
extends RefCounted

## Per-attempt statistics.
##
## VANTA is a trainer, not an analytics product, so the results screen shows a short
## list that answers "did I improve at the thing this drill trains". Everything here
## is deliberately cheap to compute and free of interpretation: no composite "aim
## score" that nobody can explain.
##
## Definitions used consistently everywhere in the product:
##   - shots:     accepted trigger pulls (rejected pulls, e.g. during a reload, are
##                counted separately and never counted as misses)
##   - hits:      shots that hit a target, whatever the region
##   - misses:    shots that did not hit a target (including shots blocked by cover)
##   - accuracy:  hits / shots, as a percentage
##   - ttk:       time from spawn to the hit that resolved the target
##   - reaction:  time from spawn to the *first* hit on a target

var started_at_unix: int = 0
var duration_seconds: float = 0.0
var shots: int = 0
var hits: int = 0
var misses: int = 0
var headshots: int = 0
var rejected_shots: int = 0
var absorbed_hits: int = 0  ## hits on regions that carry no damage (body hits in head-only drills)
var blocked_by_cover: int = 0
var targets_spawned: int = 0
var targets_eliminated: int = 0
var targets_expired: int = 0
var engagements: int = 0

var total_time_to_first_hit: float = 0.0
var total_time_to_kill: float = 0.0
var fastest_kill: float = -1.0
var slowest_kill: float = 0.0
var longest_streak: int = 0
var current_streak: int = 0

## Tracking drills accumulate time on and off target instead of counting clicks.
var tracking_on_target_seconds: float = 0.0
var tracking_off_target_seconds: float = 0.0
var tracking_samples: int = 0

## Per-round time-to-kill values, used for the consistency figure and for the
## timeline on the results screen. Capped so a long session cannot grow unbounded.
var kill_times: Array[float] = []
const MAX_KILL_TIMES: int = 512

## Adaptive difficulty decisions taken during this attempt (empty when disabled).
var difficulty_events: Array[Dictionary] = []


func reset() -> void:
	started_at_unix = int(Time.get_unix_time_from_system())
	duration_seconds = 0.0
	shots = 0
	hits = 0
	misses = 0
	headshots = 0
	rejected_shots = 0
	absorbed_hits = 0
	blocked_by_cover = 0
	targets_spawned = 0
	targets_eliminated = 0
	targets_expired = 0
	engagements = 0
	total_time_to_first_hit = 0.0
	total_time_to_kill = 0.0
	fastest_kill = -1.0
	slowest_kill = 0.0
	longest_streak = 0
	current_streak = 0
	tracking_on_target_seconds = 0.0
	tracking_off_target_seconds = 0.0
	tracking_samples = 0
	kill_times.clear()
	difficulty_events.clear()


func accuracy_percent() -> float:
	return MathX.percent(float(hits), float(shots))


func headshot_ratio_percent() -> float:
	return MathX.percent(float(headshots), float(hits))


func average_time_to_first_hit() -> float:
	if hits <= 0:
		return 0.0
	return total_time_to_first_hit / float(hits)


func average_time_to_kill() -> float:
	if targets_eliminated <= 0:
		return 0.0
	return total_time_to_kill / float(targets_eliminated)


## Percentage of on-target time for tracking drills.
func tracking_ratio_percent() -> float:
	var total := tracking_on_target_seconds + tracking_off_target_seconds
	return MathX.percent(tracking_on_target_seconds, total)


## Consistency: how tightly clustered the kill times are, expressed as a percentage
## where 100 means "identical every time". Reported *with* the average, because a
## fast average with poor consistency is a different problem than a slow average with
## good consistency, and the training prescription differs.
func consistency_percent() -> float:
	if kill_times.size() < 5:
		return 0.0
	var mean := 0.0
	for value in kill_times:
		mean += value
	mean /= float(kill_times.size())
	if mean <= 0.0:
		return 0.0
	var variance := 0.0
	for value in kill_times:
		variance += (value - mean) * (value - mean)
	variance /= float(kill_times.size())
	var deviation := sqrt(variance)
	# The coefficient of variation mapped onto a 0-100 scale, saturating at 60% spread.
	var cv := deviation / mean
	return clampf(100.0 - cv * 166.0, 0.0, 100.0)


func register_shot() -> void:
	shots += 1


func register_rejected_shot() -> void:
	rejected_shots += 1


func register_miss(blocked_by_cover_hit: bool = false, absorbed: bool = false) -> void:
	if absorbed:
		absorbed_hits += 1
		return
	misses += 1
	current_streak = 0
	if blocked_by_cover_hit:
		blocked_by_cover += 1


## A shot that hit a region the scenario does not count (a body hit in a head-only
## drill). Recorded separately from a clean miss so the player can tell "I was on the
## body" from "I was off the target", while still counting as a miss for accuracy.
func register_restricted_hit() -> void:
	misses += 1
	absorbed_hits += 1
	current_streak = 0


func register_hit(time_to_first_hit: float, is_headshot: bool) -> void:
	hits += 1
	if is_headshot:
		headshots += 1
	if time_to_first_hit >= 0.0:
		total_time_to_first_hit += time_to_first_hit


func register_elimination(time_to_kill: float) -> void:
	targets_eliminated += 1
	engagements += 1
	if time_to_kill >= 0.0:
		total_time_to_kill += time_to_kill
		if kill_times.size() < MAX_KILL_TIMES:
			kill_times.append(time_to_kill)
		if fastest_kill < 0.0 or time_to_kill < fastest_kill:
			fastest_kill = time_to_kill
		slowest_kill = maxf(slowest_kill, time_to_kill)
	current_streak += 1
	longest_streak = maxi(longest_streak, current_streak)


func register_expiry() -> void:
	targets_expired += 1
	engagements += 1
	current_streak = 0


func register_spawn() -> void:
	targets_spawned += 1


func register_tracking_sample(on_target: bool, step_seconds: float) -> void:
	tracking_samples += 1
	if on_target:
		tracking_on_target_seconds += step_seconds
	else:
		tracking_off_target_seconds += step_seconds


## Everything the results screen and the curriculum need, in one object.
func summary() -> Dictionary:
	return {
		"shots": shots,
		"hits": hits,
		"misses": misses,
		"headshots": headshots,
		"rejected_shots": rejected_shots,
		"absorbed_hits": absorbed_hits,
		"blocked_by_cover": blocked_by_cover,
		"accuracy_percent": accuracy_percent(),
		"headshot_ratio_percent": headshot_ratio_percent(),
		"targets_spawned": targets_spawned,
		"targets_eliminated": targets_eliminated,
		"targets_expired": targets_expired,
		"engagements": engagements,
		"average_time_to_first_hit": average_time_to_first_hit(),
		"average_time_to_kill": average_time_to_kill(),
		"fastest_kill": fastest_kill,
		"slowest_kill": slowest_kill,
		"longest_streak": longest_streak,
		"consistency_percent": consistency_percent(),
		"tracking_on_target_seconds": tracking_on_target_seconds,
		"tracking_off_target_seconds": tracking_off_target_seconds,
		"tracking_ratio_percent": tracking_ratio_percent(),
		"duration_seconds": duration_seconds,
		"difficulty_events": difficulty_events,
	}
