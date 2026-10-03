class_name VantaProgress
extends RefCounted

## Persistent progression: personal bests, curriculum state, placement and
## qualification results, and the per-scenario difficulty the adaptive engine left
## behind.
##
## Keys are content ids that have already been validated as safe ids by the content
## library, so a save file cannot smuggle a path through this store. Every value is
## bounded, because this file is user-editable and a malformed one must not be able to
## make the UI allocate something absurd.

const SCHEMA_VERSION: int = VantaVersion.SAVE_SCHEMA_VERSION
## A community content pack can add scenarios, but a save file should not be able to
## grow a dictionary without bound.
const MAX_TRACKED_SCENARIOS: int = 512
const MAX_TRACKED_LESSONS: int = 512
const MAX_UNLOCKS: int = 512

var schema_version: int = SCHEMA_VERSION
var created_at: int = 0
var updated_at: int = 0
## scenario_id -> {score, accuracy_percent, consistency_percent, kills, at}
var personal_bests: Dictionary = {}
## lesson_id -> {completed, attempts, best_score, completed_at}
var lesson_states: Dictionary = {}
## skill_id -> level index (0-based, matching the curriculum's level list)
var skill_levels: Dictionary = {}
## The most recent placement result, as produced by the placement test.
var placement: Dictionary = {}
## qualification_id -> {passed, score, attempts, at}
var qualification_results: Dictionary = {}
var unlocked: Array[String] = []
## scenario_id -> {"difficulty_index": int, "attempts": int, "successes": int}
var adaptive_state: Dictionary = {}


# --- attempts --------------------------------------------------------------

## Records one finished attempt. Returns what the results screen needs to know:
## whether this was a personal best, by how much, and whether it was the first time
## the scenario was cleared successfully.
func record_attempt(summary: Dictionary, now_unix: int) -> Dictionary:
	var scenario_id := String(summary.get("scenario_id", ""))
	var result := {
		"personal_best": false,
		"first_clear": false,
		"previous_score": 0,
		"improvement": 0,
	}
	if scenario_id.is_empty():
		return result
	var stats: Dictionary = summary.get("stats", {})
	var score := int(summary.get("score", 0))
	var previous: Dictionary = personal_bests.get(scenario_id, {})
	if not previous.is_empty():
		result["previous_score"] = int(previous.get("score", 0))
	var entry := {
		"score": score,
		"accuracy_percent": float(stats.get("accuracy_percent", 0.0)),
		"consistency_percent": float(stats.get("consistency_percent", 0.0)),
		"average_time_to_kill": float(stats.get("average_time_to_kill", 0.0)),
		"kills": int(stats.get("targets_eliminated", 0)),
		"at": now_unix,
	}
	var success: Dictionary = summary.get("success", {})
	if bool(success.get("met", false)) and not bool(previous.get("cleared", false)):
		result["first_clear"] = true
		entry["cleared"] = true
	elif bool(previous.get("cleared", false)):
		entry["cleared"] = true

	if previous.is_empty() or score > int(previous.get("score", 0)):
		result["personal_best"] = previous.is_empty() == false
		result["improvement"] = score - int(previous.get("score", 0))
		if _can_track(personal_bests, scenario_id, MAX_TRACKED_SCENARIOS):
			personal_bests[scenario_id] = entry
	elif bool(entry["cleared"]) and not bool(previous.get("cleared", false)):
		previous["cleared"] = true
		personal_bests[scenario_id] = previous
	updated_at = now_unix
	return result


func personal_best(scenario_id: String) -> Dictionary:
	var entry: Variant = personal_bests.get(scenario_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	return entry


func scenarios_played() -> int:
	return personal_bests.size()


func total_personal_best_score() -> int:
	var total := 0
	for value in personal_bests.values():
		if typeof(value) == TYPE_DICTIONARY:
			total += int((value as Dictionary).get("score", 0))
	return total


# --- curriculum ------------------------------------------------------------

func lesson_state(lesson_id: String) -> Dictionary:
	var entry: Variant = lesson_states.get(lesson_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {"completed": false, "attempts": 0, "best_score": 0, "completed_at": 0}
	return entry


func is_lesson_complete(lesson_id: String) -> bool:
	return bool(lesson_state(lesson_id).get("completed", false))


func mark_lesson_attempt(lesson_id: String, score: int, passed: bool, now_unix: int) -> void:
	if lesson_id.is_empty() or not _can_track(lesson_states, lesson_id, MAX_TRACKED_LESSONS):
		return
	var entry := lesson_state(lesson_id)
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	entry["best_score"] = maxi(int(entry.get("best_score", 0)), score)
	if passed and not bool(entry.get("completed", false)):
		entry["completed"] = true
		entry["completed_at"] = now_unix
	lesson_states[lesson_id] = entry
	updated_at = now_unix


func skill_level(skill_id: String) -> int:
	return int(skill_levels.get(skill_id, 0))


func set_skill_level(skill_id: String, level: int) -> void:
	if skill_id.is_empty() or not _can_track(skill_levels, skill_id, MAX_TRACKED_LESSONS):
		return
	skill_levels[skill_id] = clampi(level, 0, 999)


# --- competitive workflow --------------------------------------------------

func record_placement(result: Dictionary, now_unix: int) -> void:
	placement = {
		"rating": int(result.get("rating", 0)),
		"confidence": float(result.get("confidence", 0.0)),
		"seed": int(result.get("seed", 0)),
		"at": now_unix,
		"scenarios": int(result.get("scenarios", 0)),
	}
	updated_at = now_unix


func has_placement() -> bool:
	return not placement.is_empty()


func record_qualification(qualification_id: String, result: Dictionary, now_unix: int) -> void:
	if qualification_id.is_empty():
		return
	var entry: Dictionary = qualification_results.get(qualification_id, {})
	var attempts := int(entry.get("attempts", 0)) + 1
	qualification_results[qualification_id] = {
		"passed": bool(result.get("passed", false)),
		"score": int(result.get("score", 0)),
		"attempts": attempts,
		"at": now_unix,
	}
	updated_at = now_unix


func qualification(qualification_id: String) -> Dictionary:
	var entry: Variant = qualification_results.get(qualification_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	return entry


func qualification_passed(qualification_id: String) -> bool:
	return bool(qualification(qualification_id).get("passed", false))


# --- unlocks ---------------------------------------------------------------

func unlock(unlock_id: String) -> bool:
	if unlock_id.is_empty() or unlocked.has(unlock_id):
		return false
	if unlocked.size() >= MAX_UNLOCKS:
		return false
	unlocked.append(unlock_id)
	return true


func is_unlocked(unlock_id: String) -> bool:
	return unlocked.has(unlock_id)


# --- adaptive difficulty ---------------------------------------------------

func adaptive_entry(scenario_id: String) -> Dictionary:
	var entry: Variant = adaptive_state.get(scenario_id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		return {"difficulty_index": 0, "attempts": 0, "successes": 0}
	return entry


func set_adaptive(scenario_id: String, entry: Dictionary) -> void:
	if scenario_id.is_empty() or not _can_track(adaptive_state, scenario_id, MAX_TRACKED_SCENARIOS):
		return
	adaptive_state[scenario_id] = {
		"difficulty_index": clampi(int(entry.get("difficulty_index", 0)), 0, 64),
		"attempts": clampi(int(entry.get("attempts", 0)), 0, 1000000),
		"successes": clampi(int(entry.get("successes", 0)), 0, 1000000),
	}


# --- summary and serialisation ---------------------------------------------

func summary() -> Dictionary:
	var completed_lessons := 0
	for value in lesson_states.values():
		if typeof(value) == TYPE_DICTIONARY and bool((value as Dictionary).get("completed", false)):
			completed_lessons += 1
	var passed_qualifications := 0
	for value in qualification_results.values():
		if typeof(value) == TYPE_DICTIONARY and bool((value as Dictionary).get("passed", false)):
			passed_qualifications += 1
	return {
		"scenarios_played": scenarios_played(),
		"lessons_completed": completed_lessons,
		"lessons_tracked": lesson_states.size(),
		"qualifications_passed": passed_qualifications,
		"rating": int(placement.get("rating", 0)),
		"has_placement": has_placement(),
		"total_personal_best_score": total_personal_best_score(),
	}


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"created_at": created_at,
		"updated_at": updated_at,
		"personal_bests": personal_bests,
		"lesson_states": lesson_states,
		"skill_levels": skill_levels,
		"placement": placement,
		"qualification_results": qualification_results,
		"unlocked": unlocked,
		"adaptive_state": adaptive_state,
	}


static func from_dict(data: Variant) -> Dictionary:
	var progress := VantaProgress.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			repairs.append("progress root is not an object; progression was reset")
		return {"progress": progress, "repairs": repairs}
	var root: Dictionary = data
	progress.schema_version = _int(root.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION, 1, 999)
	progress.created_at = _int(root.get("created_at", 0), 0, 0, 4102444800)
	progress.updated_at = _int(root.get("updated_at", 0), 0, 0, 4102444800)

	progress.personal_bests = _clean_map(root.get("personal_bests", {}), MAX_TRACKED_SCENARIOS, repairs, "personal bests")
	for key in progress.personal_bests.keys():
		var entry: Dictionary = progress.personal_bests[key]
		if not _is_safe_key(String(key)):
			progress.personal_bests.erase(key)
			repairs.append("personal best with an unsafe id was dropped")
			continue
		progress.personal_bests[key] = {
			"score": _int(entry.get("score", 0), 0, 0, 100000000),
			"accuracy_percent": _float(entry.get("accuracy_percent", 0.0), 0.0, 0.0, 100.0),
			"consistency_percent": _float(entry.get("consistency_percent", 0.0), 0.0, 0.0, 100.0),
			"average_time_to_kill": _float(entry.get("average_time_to_kill", 0.0), 0.0, 0.0, 3600.0),
			"kills": _int(entry.get("kills", 0), 0, 0, 10000000),
			"at": _int(entry.get("at", 0), 0, 0, 4102444800),
			"cleared": bool(entry.get("cleared", false)),
		}

	progress.lesson_states = _clean_map(root.get("lesson_states", {}), MAX_TRACKED_LESSONS, repairs, "lesson states")
	progress.skill_levels = _clean_map(root.get("skill_levels", {}), MAX_TRACKED_LESSONS, repairs, "skill levels")
	progress.qualification_results = _clean_map(root.get("qualification_results", {}), MAX_TRACKED_LESSONS, repairs, "qualification results")
	progress.adaptive_state = _clean_map(root.get("adaptive_state", {}), MAX_TRACKED_SCENARIOS, repairs, "adaptive state")

	var placement_value: Variant = root.get("placement", {})
	if typeof(placement_value) == TYPE_DICTIONARY:
		progress.placement = (placement_value as Dictionary).duplicate(true)
	elif placement_value != null:
		repairs.append("placement was not an object and was discarded")

	var unlock_value: Variant = root.get("unlocked", [])
	if typeof(unlock_value) == TYPE_ARRAY:
		var unlocks: Array[String] = []
		for value in (unlock_value as Array):
			if typeof(value) != TYPE_STRING:
				continue
			var unlock_id := String(value)
			if _is_safe_key(unlock_id) and not unlocks.has(unlock_id) and unlocks.size() < MAX_UNLOCKS:
				unlocks.append(unlock_id)
		progress.unlocked = unlocks
	elif unlock_value != null:
		repairs.append("unlocks were not an array; unlock state was reset")
	return {"progress": progress, "repairs": repairs}


func _can_track(target: Dictionary, key: String, limit: int) -> bool:
	return target.has(key) or target.size() < limit


## Ids in a save file are only used as dictionary keys, but keeping the same shape as
## content ids means a save can never contain something a content file could not.
static func _is_safe_key(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var is_lower := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_separator := code == 95 or code == 45
		if not (is_lower or is_digit or is_separator):
			return false
	return true


static func _clean_map(value: Variant, limit: int, repairs: Array[String], label: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		if value != null:
			repairs.append("%s was not an object; it was reset" % label)
		return {}
	var source: Dictionary = value
	var result := {}
	var dropped := 0
	for key in source.keys():
		if result.size() >= limit:
			dropped += 1
			continue
		if typeof(key) != TYPE_STRING or not _is_safe_key(String(key)):
			dropped += 1
			continue
		if typeof(source[key]) != TYPE_DICTIONARY:
			dropped += 1
			continue
		result[key] = (source[key] as Dictionary).duplicate(true)
	if dropped > 0:
		repairs.append("%d invalid or excess entries were dropped from %s" % [dropped, label])
	return result


static func _int(value: Variant, fallback: int, min_value: int, max_value: int) -> int:
	var number := fallback
	match typeof(value):
		TYPE_INT:
			number = int(value)
		TYPE_FLOAT:
			number = int(value)
		TYPE_STRING:
			if (value as String).is_valid_int():
				number = int(value)
	return clampi(number, min_value, max_value)


static func _float(value: Variant, fallback: float, min_value: float, max_value: float) -> float:
	var number := fallback
	match typeof(value):
		TYPE_INT:
			number = float(value)
		TYPE_FLOAT:
			number = float(value)
		TYPE_STRING:
			if (value as String).is_valid_float():
				number = float(value)
	if is_nan(number) or is_inf(number):
		return fallback
	return clampf(number, min_value, max_value)
