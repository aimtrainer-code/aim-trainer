class_name VantaProfile
extends RefCounted

## The player's identity and lifetime counters.
##
## This is the smallest save store, and it is the one that must survive everything:
## a name the player chose and a few counters are not worth losing to a corrupted
## file, so every field is independently repaired on load rather than rejecting the
## whole object.

const SCHEMA_VERSION: int = VantaVersion.SAVE_SCHEMA_VERSION
## Training days are kept for the streak; a year of daily play plus slack is enough,
## and the cap stops the file from growing without bound.
const MAX_DAYS: int = 400

var schema_version: int = SCHEMA_VERSION
var created_at: int = 0
var updated_at: int = 0
var player_name: String = "PLAYER"
var sessions: int = 0
var total_play_seconds: float = 0.0
var total_shots: int = 0
var total_hits: int = 0
var total_targets: int = 0
var last_session_unix: int = 0
## Distinct local days (as unix day numbers) on which at least one session finished.
var training_days: Array[int] = []


func accuracy_percent() -> float:
	if total_shots <= 0:
		return 0.0
	return clampf(float(total_hits) / float(total_shots) * 100.0, 0.0, 100.0)


func average_session_minutes() -> float:
	if sessions <= 0:
		return 0.0
	return total_play_seconds / float(sessions) / 60.0


## Current consecutive-day streak, counting from the most recent training day. A gap
## of more than one day breaks it. Returns 0 when the player has never trained.
func streak_days() -> int:
	if training_days.is_empty():
		return 0
	var days := training_days.duplicate()
	days.sort()
	days.reverse()
	var streak := 1
	for index in range(1, days.size()):
		if days[index] == days[index - 1] - 1:
			streak += 1
		elif days[index] == days[index - 1]:
			continue
		else:
			break
	return streak


func best_streak() -> int:
	if training_days.is_empty():
		return 0
	var days := training_days.duplicate()
	days.sort()
	var best := 1
	var run := 1
	for index in range(1, days.size()):
		if days[index] == days[index - 1]:
			continue
		if days[index] == days[index - 1] + 1:
			run += 1
			best = maxi(best, run)
		else:
			run = 1
	return best


func day_number(unix_seconds: int) -> int:
	return int(floor(float(unix_seconds) / 86400.0))


## Folds one finished session into the lifetime counters. Takes the same summary
## dictionary the results screen shows, so there is one description of "a session".
func record_session(summary: Dictionary, now_unix: int) -> void:
	sessions += 1
	total_play_seconds += float(summary.get("duration_seconds", 0.0))
	var stats: Dictionary = summary.get("stats", {})
	total_shots += int(stats.get("shots", 0))
	total_hits += int(stats.get("hits", 0))
	total_targets += int(stats.get("targets_eliminated", 0))
	last_session_unix = now_unix
	updated_at = now_unix
	var today := day_number(now_unix)
	if not training_days.has(today):
		training_days.append(today)
		if training_days.size() > MAX_DAYS:
			training_days.sort()
			training_days = training_days.slice(training_days.size() - MAX_DAYS)


func to_dict() -> Dictionary:
	var days: Array = []
	for day in training_days:
		days.append(int(day))
	return {
		"schema_version": schema_version,
		"created_at": created_at,
		"updated_at": updated_at,
		"player_name": player_name,
		"sessions": sessions,
		"total_play_seconds": round_to(total_play_seconds, 3),
		"total_shots": total_shots,
		"total_hits": total_hits,
		"total_targets": total_targets,
		"last_session_unix": last_session_unix,
		"training_days": days,
	}


## Repairs anything invalid and returns the repaired object plus a list of notes.
## Never fails: a profile that cannot be read is a profile with default values.
static func from_dict(data: Variant) -> Dictionary:
	var profile := VantaProfile.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			repairs.append("profile root is not an object; using defaults")
		return {"profile": profile, "repairs": repairs}
	var root: Dictionary = data
	profile.schema_version = _int(root.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION, 1, 999)
	profile.created_at = _int(root.get("created_at", 0), 0, 0, 4102444800)
	profile.updated_at = _int(root.get("updated_at", 0), 0, 0, 4102444800)
	var name_value := _string(root.get("player_name", "PLAYER"), "PLAYER").strip_edges()
	if name_value.length() > 24:
		name_value = name_value.substr(0, 24)
		repairs.append("player name was longer than 24 characters and was truncated")
	if name_value.is_empty():
		name_value = "PLAYER"
		repairs.append("player name was empty and was reset")
	profile.player_name = name_value
	profile.sessions = _int(root.get("sessions", 0), 0, 0, 100000000)
	profile.total_play_seconds = _float(root.get("total_play_seconds", 0.0), 0.0, 0.0, 1000000000.0)
	profile.total_shots = _int(root.get("total_shots", 0), 0, 0, 100000000)
	profile.total_hits = _int(root.get("total_hits", 0), 0, 0, 100000000)
	profile.total_targets = _int(root.get("total_targets", 0), 0, 0, 100000000)
	profile.last_session_unix = _int(root.get("last_session_unix", 0), 0, 0, 4102444800)
	if profile.total_hits > profile.total_shots:
		repairs.append("total hits exceeded total shots; counters were clamped")
		profile.total_hits = profile.total_shots
	var raw_days: Variant = root.get("training_days", [])
	if typeof(raw_days) == TYPE_ARRAY:
		var days: Array[int] = []
		for value in (raw_days as Array):
			var day := _int(value, -1, -1, 200000)
			if day >= 0 and not days.has(day):
				days.append(day)
		if days.size() > MAX_DAYS:
			days.sort()
			days = days.slice(days.size() - MAX_DAYS)
			repairs.append("training day list was trimmed to the last %d days" % MAX_DAYS)
		profile.training_days = days
	elif raw_days != null:
		repairs.append("training_days was not an array; the streak was reset")
	if profile.created_at == 0:
		profile.created_at = int(Time.get_unix_time_from_system())
	return {"profile": profile, "repairs": repairs}


func duplicate_profile() -> VantaProfile:
	return from_dict(to_dict())["profile"]


static func round_to(value: float, decimals: int) -> float:
	var factor := pow(10.0, float(decimals))
	return roundf(value * factor) / factor


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


static func _string(value: Variant, fallback: String) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	return fallback
