class_name VantaHistory
extends RefCounted

## A rolling log of finished attempts.
##
## History is the evidence behind every claim the progress screens make: "you are
## faster on micro flicks than last week" has to be answerable from stored data, not
## from a feeling. It is capped and stored newest-first so the cap drops the oldest
## attempts, and each entry is a small, fixed-shape record so the file cannot grow
## with whatever a summary happened to contain.

const SCHEMA_VERSION: int = VantaVersion.SAVE_SCHEMA_VERSION
const MAX_ENTRIES: int = 500

var schema_version: int = SCHEMA_VERSION
var entries: Array[Dictionary] = []


## Records a finished attempt. `summary` is the dictionary produced by
## `ScenarioRuntime.build_summary()`, so there is exactly one description of an
## attempt in the whole project.
func record(summary: Dictionary, now_unix: int) -> Dictionary:
	var stats: Dictionary = summary.get("stats", {})
	var entry := {
		"scenario_id": String(summary.get("scenario_id", "")),
		"mode": String(summary.get("mode", "")),
		"skill": String(summary.get("skill", "")),
		"score": int(summary.get("score", 0)),
		"accuracy_percent": float(stats.get("accuracy_percent", 0.0)),
		"kills": int(stats.get("targets_eliminated", 0)),
		"shots": int(stats.get("shots", 0)),
		"average_time_to_kill": float(stats.get("average_time_to_kill", 0.0)),
		"consistency_percent": float(stats.get("consistency_percent", 0.0)),
		"duration_seconds": float(stats.get("duration_seconds", 0.0)),
		"passed": bool((summary.get("success", {}) as Dictionary).get("met", false)),
		"finish_reason": String(summary.get("finish_reason", "")),
		"at": now_unix,
	}
	entries.push_front(entry)
	while entries.size() > MAX_ENTRIES:
		entries.pop_back()
	return entry


func count() -> int:
	return entries.size()


## Most recent entries, newest first.
func recent(limit: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in mini(limit, entries.size()):
		result.append(entries[index])
	return result


## Entries for one scenario, newest first.
func for_scenario(scenario_id: String, limit: int = 50) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if String(entry.get("scenario_id", "")) == scenario_id:
			result.append(entry)
			if result.size() >= limit:
				break
	return result


## The most recent `window` attempts for one scenario, as a trend summary. Used by the
## progress screen and by the adaptive engine's "is this player improving" question.
func trend(scenario_id: String, window: int = 10) -> Dictionary:
	var history := for_scenario(scenario_id, window)
	if history.is_empty():
		return {"samples": 0, "average_score": 0.0, "average_accuracy": 0.0, "best_score": 0}
	var score_total := 0
	var accuracy_total := 0.0
	var best := 0
	for entry in history:
		score_total += int(entry.get("score", 0))
		accuracy_total += float(entry.get("accuracy_percent", 0.0))
		best = maxi(best, int(entry.get("score", 0)))
	return {
		"samples": history.size(),
		"average_score": float(score_total) / float(history.size()),
		"average_accuracy": accuracy_total / float(history.size()),
		"best_score": best,
		"latest_score": int(history[0].get("score", 0)),
	}


## Aggregate over a time window ending at `now_unix`. `days` of 0 means "all time".
func aggregate(days: int, now_unix: int) -> Dictionary:
	var cutoff := 0 if days <= 0 else now_unix - days * 86400
	var attempts := 0
	var shots := 0
	var kills := 0
	var seconds := 0.0
	var score := 0
	for entry in entries:
		if int(entry.get("at", 0)) < cutoff:
			continue
		attempts += 1
		shots += int(entry.get("shots", 0))
		kills += int(entry.get("kills", 0))
		seconds += float(entry.get("duration_seconds", 0.0))
		score += int(entry.get("score", 0))
	return {
		"attempts": attempts,
		"shots": shots,
		"kills": kills,
		"seconds": seconds,
		"score": score,
	}


func to_dict() -> Dictionary:
	var rows: Array = []
	for entry in entries:
		rows.append(entry)
	return {"schema_version": schema_version, "entries": rows}


static func from_dict(data: Variant) -> Dictionary:
	var history := VantaHistory.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			repairs.append("history root is not an object; history was reset")
		return {"history": history, "repairs": repairs}
	var root: Dictionary = data
	history.schema_version = _int(root.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION, 1, 999)
	var raw: Variant = root.get("entries", [])
	if typeof(raw) != TYPE_ARRAY:
		if raw != null:
			repairs.append("history entries were not an array; history was reset")
		return {"history": history, "repairs": repairs}
	var rows: Array[Dictionary] = []
	var dropped := 0
	for value in (raw as Array):
		if typeof(value) != TYPE_DICTIONARY:
			dropped += 1
			continue
		if rows.size() >= MAX_ENTRIES:
			dropped += 1
			continue
		var source: Dictionary = value
		var scenario_id := String(source.get("scenario_id", ""))
		if not VantaProgress._is_safe_key(scenario_id):
			dropped += 1
			continue
		rows.append({
			"scenario_id": scenario_id,
			"mode": String(source.get("mode", "")),
			"skill": String(source.get("skill", "")),
			"score": _int(source.get("score", 0), 0, 0, 100000000),
			"accuracy_percent": _float(source.get("accuracy_percent", 0.0), 0.0, 0.0, 100.0),
			"kills": _int(source.get("kills", 0), 0, 0, 10000000),
			"shots": _int(source.get("shots", 0), 0, 0, 10000000),
			"average_time_to_kill": _float(source.get("average_time_to_kill", 0.0), 0.0, 0.0, 3600.0),
			"consistency_percent": _float(source.get("consistency_percent", 0.0), 0.0, 0.0, 100.0),
			"duration_seconds": _float(source.get("duration_seconds", 0.0), 0.0, 0.0, 86400.0),
			"passed": bool(source.get("passed", false)),
			"finish_reason": String(source.get("finish_reason", "")),
			"at": _int(source.get("at", 0), 0, 0, 4102444800),
		})
	if dropped > 0:
		repairs.append("%d invalid history entries were dropped" % dropped)
	history.entries = rows
	return {"history": history, "repairs": repairs}


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
