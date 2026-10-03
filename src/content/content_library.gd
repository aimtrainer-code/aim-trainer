class_name VantaContentLibrary
extends RefCounted

## Loads and validates every content file VANTA ships or the player installs.
##
## Content is split into shipped content (`res://content`, read-only, reviewed) and
## user content (`user://content`, untrusted). Both go through exactly the same
## validation: a file the player wrote by hand is held to the same standard as one
## that arrived with the game, and neither can describe a state the simulation is
## unable to run.
##
## Security rules enforced here (see SECURITY.md):
##   - an id must match `^[a-z0-9_-]{1,64}$` and must equal its file name, so no id
##     can ever be used to build a path;
##   - ids are never joined into a path when *referencing* content (arena_id,
##     weapon_id, lesson_id); references are dictionary lookups only;
##   - files larger than `MAX_FILE_BYTES` are refused before being parsed;
##   - user content cannot replace shipped content that the curriculum depends on;
##   - a file that fails validation is reported and skipped, never partially applied.

const BUILTIN_ROOT: String = "res://content"
const USER_ROOT: String = "user://content"
const WEAPONS: String = "weapons"
const ARENAS: String = "arenas"
const SCENARIOS: String = "scenarios"
const KINDS: Array[String] = [WEAPONS, ARENAS, SCENARIOS]
## A content file is a small description, not an asset bundle.
const MAX_FILE_BYTES: int = 262144
const ID_PATTERN: String = "^[a-z0-9_-]{1,64}$"

static var _id_regex: RegEx = null

var weapons: Dictionary = {}
var arenas: Dictionary = {}
var scenarios: Dictionary = {}
var errors: Array[String] = []
var warnings: Array[String] = []
var loaded_files: int = 0
var user_files: int = 0
var _builtin_ids: Dictionary = {}


## Loads everything. Returns a report; the caller decides how loudly to surface it.
## Loading is idempotent: calling it twice reloads from disk.
func load_all() -> Dictionary:
	weapons.clear()
	arenas.clear()
	scenarios.clear()
	errors.clear()
	warnings.clear()
	loaded_files = 0
	user_files = 0
	_builtin_ids = {WEAPONS: {}, ARENAS: {}, SCENARIOS: {}}

	for kind in KINDS:
		_load_kind(kind, "%s/%s" % [BUILTIN_ROOT, kind], false)
	# User content is loaded second so an id clash is detectable against shipped ids.
	for kind in KINDS:
		_load_kind(kind, "%s/%s" % [USER_ROOT, kind], true)

	_validate_references()
	return report()


func report() -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"files": loaded_files,
		"user_files": user_files,
		"weapons": weapons.size(),
		"arenas": arenas.size(),
		"scenarios": scenarios.size(),
		"errors": errors,
		"warnings": warnings,
	}


func content_counts() -> Dictionary:
	return {"weapons": weapons.size(), "arenas": arenas.size(), "scenarios": scenarios.size(), "files": loaded_files}


# --- lookup ----------------------------------------------------------------

func weapon(id: String) -> WeaponDefinition:
	var value: Variant = weapons.get(id, null)
	return value if value is WeaponDefinition else null


func arena(id: String) -> ArenaDefinition:
	var value: Variant = arenas.get(id, null)
	return value if value is ArenaDefinition else null


func scenario(id: String) -> ScenarioDefinition:
	var value: Variant = scenarios.get(id, null)
	return value if value is ScenarioDefinition else null


func has_scenario(id: String) -> bool:
	return scenarios.has(id)


## Scenario ids sorted for display: by mode, then by difficulty, then by id. The
## ordering is stable so the drill list does not reshuffle between launches.
func scenario_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in scenarios.keys():
		ids.append(String(key))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var left: ScenarioDefinition = scenarios[a]
		var right: ScenarioDefinition = scenarios[b]
		if left.mode != right.mode:
			return left.mode < right.mode
		if left.difficulty != right.difficulty:
			return left.difficulty < right.difficulty
		return a < b
	)
	return ids


func scenarios_for_mode(mode_id: String) -> Array[String]:
	var result: Array[String] = []
	for id in scenario_ids():
		var definition: ScenarioDefinition = scenarios[id]
		if definition.mode_id() == mode_id:
			result.append(id)
	return result


func is_builtin(kind: String, id: String) -> bool:
	var bucket: Dictionary = _builtin_ids.get(kind, {})
	return bucket.has(id)


# --- loading ---------------------------------------------------------------

func _load_kind(kind: String, root: String, from_user: bool) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		if from_user:
			# Not an error: most players never install community content.
			return
		errors.append("%s: content directory is missing" % root)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if directory.current_is_dir():
			file_name = directory.get_next()
			continue
		if file_name.begins_with(".") or not file_name.ends_with(".json"):
			file_name = directory.get_next()
			continue
		_load_file(kind, "%s/%s" % [root, file_name], file_name, from_user)
		file_name = directory.get_next()
	directory.list_dir_end()


func _load_file(kind: String, path: String, file_name: String, from_user: bool) -> void:
	var id := file_name.get_basename()
	if not is_safe_id(id):
		_record_error("%s: '%s' is not a valid content id (must match %s)" % [path, id, ID_PATTERN])
		return
	var size := _file_size(path)
	if size < 0:
		_record_error("%s: file could not be opened" % path)
		return
	if size == 0:
		_record_error("%s: file is empty" % path)
		return
	if size > MAX_FILE_BYTES:
		_record_error("%s: file is larger than %d bytes" % [path, MAX_FILE_BYTES])
		return
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_record_error("%s: file is not valid JSON" % path)
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_error("%s: file root must be a JSON object" % path)
		return
	var data: Dictionary = parsed
	var declared := String(data.get("id", ""))
	if declared.is_empty():
		_record_error("%s: content is missing an 'id'" % path)
		return
	if declared != id:
		_record_error("%s: id '%s' does not match the file name" % [path, declared])
		return
	if not VantaContentLibrary.is_safe_id(declared):
		_record_error("%s: id '%s' is not a safe id" % [path, declared])
		return
	if not _register_id(kind, id, from_user, path):
		return

	match kind:
		WEAPONS:
			_store_weapon(id, data, path)
		ARENAS:
			_store_arena(id, data, path)
		SCENARIOS:
			_store_scenario(id, data, path)


func _register_id(kind: String, id: String, from_user: bool, path: String) -> bool:
	var bucket: Dictionary = _builtin_ids[kind]
	if from_user:
		if bucket.has(id):
			_record_error("%s: user content may not replace the built-in '%s' content" % [path, id])
			return false
		user_files += 1
	else:
		if bucket.has(id):
			_record_error("%s: duplicate built-in content id '%s'" % [path, id])
			return false
		bucket[id] = true
	loaded_files += 1
	return true


func _store_weapon(id: String, data: Dictionary, path: String) -> void:
	var result := WeaponDefinition.from_dict(data, path)
	var definition: WeaponDefinition = result["weapon"]
	for problem in result["errors"]:
		_record_error("%s: %s" % [path, String(problem)])
	for note in result["warnings"]:
		warnings.append("%s: %s" % [path, String(note)])
	if not result["errors"].is_empty():
		return
	weapons[id] = definition


func _store_arena(id: String, data: Dictionary, path: String) -> void:
	var result := ArenaDefinition.from_dict(data, path)
	var definition: ArenaDefinition = result["arena"]
	for problem in result["errors"]:
		_record_error("%s: %s" % [path, String(problem)])
	for note in result["warnings"]:
		warnings.append("%s: %s" % [path, String(note)])
	if not result["errors"].is_empty():
		return
	arenas[id] = definition


func _store_scenario(id: String, data: Dictionary, path: String) -> void:
	var result := ScenarioDefinition.from_dict(data, path)
	var definition: ScenarioDefinition = result["definition"]
	for problem in result["errors"]:
		_record_error("%s: %s" % [path, String(problem)])
	for note in result["warnings"]:
		warnings.append("%s: %s" % [path, String(note)])
	if not result["errors"].is_empty():
		return
	scenarios[id] = definition


## Cross-reference check: a scenario that names an arena or weapon which does not
## exist is unusable, and finding that out at load time is much better than finding
## it out when the player presses start.
func _validate_references() -> void:
	for id in scenarios.keys():
		var definition: ScenarioDefinition = scenarios[id]
		if not arenas.has(definition.arena_id):
			_record_error("scenario '%s': unknown arena '%s'" % [id, definition.arena_id])
			scenarios.erase(id)
			continue
		if not weapons.has(definition.weapon_id):
			_record_error("scenario '%s': unknown weapon '%s'" % [id, definition.weapon_id])
			scenarios.erase(id)
	# Arena anchors must not sit inside their own cover, or a peek drill trains
	# against a target that is never visible.
	for id in arenas.keys():
		var definition: ArenaDefinition = arenas[id]
		for anchor in definition.anchors:
			if not anchor.has_cover:
				continue
			var cover := anchor.cover_box()
			if cover == null:
				continue
			var offset := (anchor.position - cover.center).abs()
			if offset.x <= cover.half_size.x and offset.y <= cover.half_size.y and offset.z <= cover.half_size.z:
				warnings.append("arena '%s': anchor '%s' sits inside its own cover" % [id, anchor.id])


static func _file_size(path: String) -> int:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return -1
	var size := int(handle.get_length())
	handle.close()
	return size


func _record_error(message: String) -> void:
	if not errors.has(message):
		errors.append(message)


# --- ids -------------------------------------------------------------------

## The single definition of a safe content id. Ids are used as dictionary keys and as
## file name stems, never as path fragments.
static func is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	if _id_regex == null:
		_id_regex = RegEx.create_from_string(ID_PATTERN)
	return _id_regex.search(value) != null
