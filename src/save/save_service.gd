class_name VantaSaveService
extends RefCounted

## Offline-first persistence.
##
## Requirements this file exists to satisfy, and how:
##
##   - **Versioned saves with migration.** Every store carries a `schema_version`;
##     `migrate()` upgrades the pre-release (v0) shape in place and refuses files
##     written by a newer build instead of mangling them.
##   - **Corrupt-file tolerance.** A file that cannot be parsed, or whose root is the
##     wrong type, is quarantined (renamed, never deleted) and replaced by defaults.
##     The player loses the bad file, not their progress: the `.bak` copy is tried
##     first.
##   - **Atomic writes.** Saves go to a temporary file, which is verified by reading it
##     back before it replaces the real one, so a crash mid-write cannot produce a
##     half-written save.
##   - **Backup and recovery.** The previous good file is kept as `<name>.bak.json`.
##   - **Export and import.** One JSON bundle with a checksum, so progress can move
##     between machines without an account.

## Where saves live by default. Every path below is derived from `save_dir`, which a
## test (or a "portable mode" build) can point somewhere else; nothing else in the
## project is allowed to build a save path by hand.
const DEFAULT_DIR: String = "user://saves"
const BUNDLE_MARKER: String = "vanta_bundle"
const BUNDLE_VERSION: int = 1
## A save file larger than this is not a save file. The cap exists so a malformed or
## hostile file cannot be used to exhaust memory on load.
const MAX_FILE_BYTES: int = 8 * 1024 * 1024

var profile: VantaProfile = null
var progress: VantaProgress = null
var history: VantaHistory = null
var save_dir: String = DEFAULT_DIR
## Per-load diagnostics for the settings screen and the self tests.
var report: Dictionary = {}
var dirty: bool = false


func _init(dir_path: String = DEFAULT_DIR) -> void:
	save_dir = dir_path
	profile = VantaProfile.new()
	progress = VantaProgress.new()
	history = VantaHistory.new()
	report = _empty_report()


func profile_path() -> String:
	return save_dir.path_join("profile.json")


func progress_path() -> String:
	return save_dir.path_join("progress.json")


func history_path() -> String:
	return save_dir.path_join("history.json")


## Settings live next to the save directory, not inside it: deleting a profile must
## never silently change how the mouse feels.
func settings_path() -> String:
	return save_dir.get_base_dir().path_join("settings.json")


func _empty_report() -> Dictionary:
	return {
		"loaded": [],
		"repairs": [],
		"errors": [],
		"recovered": [],
		"quarantined": [],
	}


# --- loading ---------------------------------------------------------------

## Loads every store. Always returns a usable set of stores, whatever the files
## contain. The returned dictionary is the report.
func load_all() -> Dictionary:
	report = _empty_report()
	_ensure_dir()
	# Start from empty stores. Every store is replaced only when its file loads, so a
	# file that cannot be read leaves the *defaults* in place — never the values that
	# happened to be in memory before the reload.
	profile = VantaProfile.new()
	progress = VantaProgress.new()
	history = VantaHistory.new()
	var profile_data := _read_with_recovery("profile", profile_path())
	var progress_data := _read_with_recovery("progress", progress_path())
	var history_data := _read_with_recovery("history", history_path())

	if profile_data["ok"]:
		var migrated := migrate("profile", profile_data["data"])
		if migrated["ok"]:
			var parsed := VantaProfile.from_dict(migrated["data"])
			profile = parsed["profile"]
			record_repairs("profile", parsed["repairs"])
			report["loaded"].append("profile")
	if progress_data["ok"]:
		var migrated_progress := migrate("progress", progress_data["data"])
		if migrated_progress["ok"]:
			var parsed_progress := VantaProgress.from_dict(migrated_progress["data"])
			progress = parsed_progress["progress"]
			record_repairs("progress", parsed_progress["repairs"])
			report["loaded"].append("progress")
	if history_data["ok"]:
		var migrated_history := migrate("history", history_data["data"])
		if migrated_history["ok"]:
			var parsed_history := VantaHistory.from_dict(migrated_history["data"])
			history = parsed_history["history"]
			record_repairs("history", parsed_history["repairs"])
			report["loaded"].append("history")
	dirty = false
	return report


func record_repairs(label: String, repairs: Array) -> void:
	for repair in repairs:
		report["repairs"].append("%s: %s" % [label, String(repair)])


func is_first_run() -> bool:
	return report["loaded"].is_empty()


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(save_dir):
		var error := DirAccess.make_dir_recursive_absolute(save_dir)
		if error != OK:
			report["errors"].append("could not create the save directory (error %d)" % error)


## Reads a store, falling back to its backup and then to nothing. Never throws and
## never leaves the user without a file: a bad file is renamed, not deleted.
func _read_with_recovery(label: String, path: String) -> Dictionary:
	var primary := _read_json(path)
	if primary["ok"]:
		return primary
	if primary["missing"]:
		return {"ok": false, "missing": true, "data": null}
	report["errors"].append("%s: %s" % [label, String(primary["error"])])

	var backup_path := _backup_path(path)
	var backup := _read_json(backup_path)
	if backup["ok"]:
		report["recovered"].append(label)
		report["errors"].append("%s: recovered from backup %s" % [label, backup_path])
		# Put the good copy back in place so the next load is clean.
		_write_json(path, backup["data"], false)
		return backup

	var quarantine := _quarantine(path)
	if not quarantine.is_empty():
		report["quarantined"].append(quarantine)
	return {"ok": false, "missing": false, "data": null}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "error": "file does not exist", "data": null}
	var size := _file_size(path)
	if size <= 0:
		return {"ok": false, "missing": false, "error": "file is empty", "data": null}
	if size > MAX_FILE_BYTES:
		return {"ok": false, "missing": false, "error": "file is larger than %d bytes" % MAX_FILE_BYTES, "data": null}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "missing": false, "error": "file could not be read", "data": null}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "missing": false, "error": "file is not valid JSON", "data": null}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "missing": false, "error": "file root is not an object", "data": null}
	return {"ok": true, "missing": false, "error": "", "data": parsed}


static func _file_size(path: String) -> int:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return -1
	var size := int(handle.get_length())
	handle.close()
	return size


static func _backup_path(path: String) -> String:
	var stem := path.get_basename()
	return "%s.bak.json" % stem


## Renames an unreadable file out of the way. Returns the new path, or "" when the
## rename failed (the caller still uses defaults, so a failure here is not fatal).
func _quarantine(path: String) -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var target := "%s.corrupt-%d.json" % [path.get_basename(), stamp]
	var error := DirAccess.rename_absolute(path, target)
	if error != OK:
		report["errors"].append("could not quarantine %s (error %d)" % [path, error])
		return ""
	report["errors"].append("%s was unreadable and was moved to %s" % [path, target])
	return target


# --- saving ----------------------------------------------------------------

func save_all() -> Dictionary:
	_ensure_dir()
	var errors: Array[String] = []
	if not save_profile()["ok"]:
		errors.append("profile")
	if not save_progress()["ok"]:
		errors.append("progress")
	if not save_history()["ok"]:
		errors.append("history")
	dirty = errors.is_empty()
	return {"ok": errors.is_empty(), "failed": errors}


func save_profile() -> Dictionary:
	return _write_json(profile_path(), profile.to_dict(), true)


func save_progress() -> Dictionary:
	return _write_json(progress_path(), progress.to_dict(), true)


func save_history() -> Dictionary:
	return _write_json(history_path(), history.to_dict(), true)


## Atomic-ish write: the payload goes to `<path>.tmp`, is read back and parsed, and
## only then replaces the real file (whose previous contents become the backup).
func _write_json(path: String, data: Dictionary, keep_backup: bool) -> Dictionary:
	var text := JSON.stringify(data, "\t")
	var temporary := "%s.tmp" % path
	var handle := FileAccess.open(temporary, FileAccess.WRITE)
	if handle == null:
		var message := "could not open %s for writing (error %d)" % [temporary, FileAccess.get_open_error()]
		report["errors"].append(message)
		return {"ok": false, "error": message}
	handle.store_string(text)
	handle.flush()
	handle.close()

	var verification := _read_json(temporary)
	if not verification["ok"]:
		DirAccess.remove_absolute(temporary)
		var reason := "written file failed verification: %s" % String(verification["error"])
		report["errors"].append(reason)
		return {"ok": false, "error": reason}

	if keep_backup and FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, _backup_path(path))
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		var rename_message := "could not replace %s (error %d)" % [path, rename_error]
		report["errors"].append(rename_message)
		return {"ok": false, "error": rename_message}
	return {"ok": true, "error": "", "bytes": text.length()}


# --- settings --------------------------------------------------------------

## Reads settings with the same recovery rules as the save stores: a corrupt file is
## recovered from the backup if possible and quarantined if not, and the game always
## ends up with usable settings.
func load_settings() -> Dictionary:
	var errors: Array[String] = []
	var repairs: Array[String] = []
	var defaults := VantaSettings.new()
	if not FileAccess.file_exists(settings_path()):
		return {"settings": defaults, "errors": errors, "repairs": repairs}
	var read := _read_json(settings_path())
	if not read["ok"]:
		errors.append("settings: %s" % String(read["error"]))
		var backup := _read_json(_backup_path(settings_path()))
		if backup["ok"]:
			read = backup
			repairs.append("settings were recovered from the backup copy")
		else:
			_quarantine(settings_path())
			errors.append("settings were unreadable and were reset to defaults")
			return {"settings": defaults, "errors": errors, "repairs": repairs}
	var parsed := VantaSettings.from_dict(read["data"])
	for note in parsed["repairs"]:
		repairs.append(String(note))
	return {"settings": parsed["settings"], "errors": errors, "repairs": repairs}


func save_settings(settings: VantaSettings) -> Dictionary:
	if settings == null:
		return {"ok": false, "error": "no settings to write"}
	return _write_json(settings_path(), settings.to_dict(), true)


# --- migration -------------------------------------------------------------

## Upgrades an older payload to the current schema. A file from a newer build is
## refused: guessing at a format we do not know is how saves get destroyed.
func migrate(label: String, data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version > VantaVersion.SAVE_SCHEMA_VERSION:
		report["errors"].append("%s: save version %d is newer than this build supports (%d)" % [label, version, VantaVersion.SAVE_SCHEMA_VERSION])
		return {"ok": false, "data": data}
	if version == VantaVersion.SAVE_SCHEMA_VERSION:
		return {"ok": true, "data": data}
	var upgraded := data.duplicate(true)
	match version:
		0:
			upgraded = _migrate_v0(label, upgraded)
			upgraded["schema_version"] = 1
			report["repairs"].append("%s: migrated from save version 0" % label)
		_:
			report["errors"].append("%s: unknown save version %d" % [label, version])
			return {"ok": false, "data": data}
	return {"ok": true, "data": upgraded}


## Version 0 is the pre-release prototype format: flat keys, ids where the v1 format
## keeps objects. It is kept as a real migration rather than a note because a
## developer build and an early test build both wrote it.
func _migrate_v0(label: String, data: Dictionary) -> Dictionary:
	match label:
		"profile":
			var migrated := {
				"schema_version": 1,
				"created_at": int(data.get("created", 0)),
				"updated_at": int(data.get("updated", 0)),
				"player_name": String(data.get("name", "PLAYER")),
				"sessions": int(data.get("sessions", 0)),
			}
			if data.has("play_seconds"):
				migrated["total_play_seconds"] = float(data["play_seconds"])
			return migrated
		"progress":
			var lessons := {}
			var completions: Variant = data.get("completed", [])
			if typeof(completions) == TYPE_ARRAY:
				for value in (completions as Array):
					var lesson_id := String(value)
					lessons[lesson_id] = {"completed": true, "attempts": 1, "best_score": 0, "completed_at": 0}
			var bests := {}
			var pbs: Variant = data.get("pbs", {})
			if typeof(pbs) == TYPE_DICTIONARY:
				for key in (pbs as Dictionary).keys():
					bests[String(key)] = {"score": int((pbs as Dictionary)[key])}
			return {"schema_version": 1, "lesson_states": lessons, "personal_bests": bests}
		"history":
			var entries: Array = []
			var runs: Variant = data.get("runs", [])
			if typeof(runs) == TYPE_ARRAY:
				for value in (runs as Array):
					if typeof(value) != TYPE_DICTIONARY:
						continue
					var row: Dictionary = value
					entries.append({
						"scenario_id": String(row.get("scenario", "")),
						"score": int(row.get("score", 0)),
						"accuracy_percent": float(row.get("accuracy", 0.0)),
						"at": int(row.get("at", 0)),
					})
			return {"schema_version": 1, "entries": entries}
	return data


# --- export and import -----------------------------------------------------

## Writes every store into one bundle. `target_path` is a user-chosen location; the
## only constraint is that it is a file path, never a directory.
func export_bundle(target_path: String) -> Dictionary:
	if target_path.is_empty() or target_path.ends_with("/"):
		return {"ok": false, "error": "export path must be a file path"}
	var payload := {
		BUNDLE_MARKER: BUNDLE_VERSION,
		"app_version": VantaVersion.string(),
		"save_version": VantaVersion.SAVE_SCHEMA_VERSION,
		"exported_at": int(Time.get_unix_time_from_system()),
		"profile": profile.to_dict(),
		"progress": progress.to_dict(),
		"history": history.to_dict(),
	}
	# The checksum is taken over the *normalised* payload — the text as it will be read
	# back — because a JSON round trip changes representations (Godot's parser returns
	# every number as a float, so `12` comes back as `12.0`). Checksumming the freshly
	# built dictionary instead would make a healthy bundle look edited on import.
	var body := JSON.stringify(payload)
	var normalised: Variant = JSON.parse_string(body)
	var checksum := _checksum(JSON.stringify(normalised) if normalised != null else body)
	payload["checksum"] = checksum
	var text := JSON.stringify(payload, "\t")
	var handle := FileAccess.open(target_path, FileAccess.WRITE)
	if handle == null:
		return {"ok": false, "error": "could not write %s (error %d)" % [target_path, FileAccess.get_open_error()]}
	handle.store_string(text)
	handle.close()
	return {"ok": true, "error": "", "path": target_path, "bytes": text.length(), "checksum": checksum}


## Reads a bundle and replaces the stores with it. Everything inside the bundle is
## re-validated through the same repair paths as a normal load, so importing cannot
## produce a state that loading from disk could not.
func import_bundle(source_path: String) -> Dictionary:
	var read := _read_json(source_path)
	if not read["ok"]:
		return {"ok": false, "error": "bundle could not be read: %s" % String(read["error"]), "repairs": []}
	var root: Dictionary = read["data"]
	if int(root.get(BUNDLE_MARKER, 0)) <= 0:
		return {"ok": false, "error": "file is not a VANTA save bundle", "repairs": []}
	var save_version := int(root.get("save_version", 0))
	if save_version > VantaVersion.SAVE_SCHEMA_VERSION:
		return {"ok": false, "error": "bundle was written by a newer version of VANTA (save version %d)" % save_version, "repairs": []}
	if save_version <= 0:
		return {"ok": false, "error": "bundle does not declare a save version", "repairs": []}
	var checksum := String(root.get("checksum", ""))
	var payload := root.duplicate()
	payload.erase("checksum")
	if not payload.has("save_version"):
		return {"ok": false, "error": "bundle is missing its save version", "repairs": []}
	if not checksum.is_empty() and checksum != _checksum(JSON.stringify(payload)):
		return {"ok": false, "error": "bundle checksum does not match; the file is damaged or edited", "repairs": []}

	var repairs: Array[String] = []
	var profile_result := _import_store("profile", root.get("profile", {}), repairs)
	var progress_result := _import_store("progress", root.get("progress", {}), repairs)
	var history_result := _import_store("history", root.get("history", {}), repairs)
	# A store this build cannot read aborts the whole import: applying two of three
	# stores would leave the player with a profile that does not match its history.
	for result in [profile_result, progress_result, history_result]:
		var outcome: Dictionary = result
		if not bool(outcome.get("ok", false)):
			return {"ok": false, "error": String(outcome.get("error", "bundle contains unreadable stores")), "repairs": repairs}
	var parsed_profile := VantaProfile.from_dict(profile_result["data"])
	var parsed_progress := VantaProgress.from_dict(progress_result["data"])
	var parsed_history := VantaHistory.from_dict(history_result["data"])
	for note in parsed_profile["repairs"]:
		repairs.append(String(note))
	for note in parsed_progress["repairs"]:
		repairs.append(String(note))
	for note in parsed_history["repairs"]:
		repairs.append(String(note))
	profile = parsed_profile["profile"]
	progress = parsed_progress["progress"]
	history = parsed_history["history"]
	var save_result := save_all()
	return {
		"ok": bool(save_result["ok"]),
		"error": "" if bool(save_result["ok"]) else "imported data could not be written to disk",
		"repairs": repairs,
	}


## Runs an imported store through the same migration path as a load from disk, so an
## import can never produce a state that loading could not.
func _import_store(label: String, value: Variant, repairs: Array[String]) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		repairs.append("%s was missing from the bundle and was reset" % label)
		return {"ok": true, "data": {}}
	return migrate(label, (value as Dictionary).duplicate(true))


## Wipes progression back to a fresh profile while keeping a copy of what was there.
func reset_progress() -> void:
	var stamp := int(Time.get_unix_time_from_system())
	for path in [profile_path(), progress_path(), history_path()]:
		if FileAccess.file_exists(path):
			DirAccess.copy_absolute(path, "%s.reset-%d.json" % [path.get_basename(), stamp])
	profile = VantaProfile.new()
	progress = VantaProgress.new()
	history = VantaHistory.new()
	save_all()


static func _checksum(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func status_line() -> String:
	var loaded: Array = report.get("loaded", [])
	var errors: Array = report.get("errors", [])
	if errors.is_empty():
		return "saves: %d store(s) loaded" % loaded.size()
	return "saves: %d loaded, %d issue(s)" % [loaded.size(), errors.size()]
