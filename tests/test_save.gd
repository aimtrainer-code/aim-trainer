extends VantaTestCase

## The save layer is the player's data, and it is the one subsystem where a bug
## destroys something that cannot be regenerated. These tests therefore treat every
## file as hostile: truncated, edited, oversized, written by a newer build, or absent.
##
## The contract under test:
##   1. the game always ends up with a usable profile, whatever is on disk;
##   2. nothing is silently discarded — a damaged file is moved aside, not deleted;
##   3. a backup copy recovers the last good state;
##   4. a file from a newer build is refused rather than guessed at;
##   5. export/import round-trips, and an edited bundle is refused.

const TEST_ROOT: String = "user://test"
const TEST_DIR: String = "user://test/saves"
const EXPORT_PATH: String = "user://test/export.vanta.json"
const ALT_DIRS: Array[String] = ["user://test/other", "user://test/other2"]

var service: VantaSaveService = null


func before_each() -> void:
	_clean()
	service = VantaSaveService.new(TEST_DIR)
	service.load_all()


func after_each() -> void:
	_clean()


# --- first run -------------------------------------------------------------

func test_first_run_uses_defaults_without_errors() -> void:
	assert_true(service.is_first_run(), "a fresh install has no save files yet")
	assert_eq(service.report["errors"].size(), 0, "a missing save file is not an error: %s" % str(service.report["errors"]))
	assert_eq(service.profile.sessions, 0, "the profile starts empty")
	assert_eq(service.progress.scenarios_played(), 0, "no scenario has been played")
	assert_eq(service.history.count(), 0, "the history is empty")
	assert_string_contains(service.status_line(), "loaded", "the status line reports the state")


# --- round trip ------------------------------------------------------------

func test_records_round_trip_through_disk() -> void:
	var summary := _summary(4242, 40, 12)
	service.profile.record_session(summary, 1700000000)
	service.progress.record_attempt(summary, 1700000000)
	service.history.record(summary, 1700000000)
	var saved := service.save_all()
	assert_true(bool(saved["ok"]), "the stores were written: %s" % str(saved))

	var reloaded := VantaSaveService.new(TEST_DIR)
	var report := reloaded.load_all()
	assert_eq(report["loaded"].size(), 3, "all three stores loaded: %s" % str(report["loaded"]))
	assert_eq(report["errors"].size(), 0, "a clean save loads without errors: %s" % str(report["errors"]))
	assert_false(reloaded.is_first_run(), "the save is no longer a first run")
	assert_eq(reloaded.profile.sessions, 1, "the session count survived")
	assert_eq(reloaded.profile.total_shots, 40, "the shot total survived")
	assert_eq(reloaded.history.count(), 1, "the history entry survived")
	assert_eq(int(reloaded.progress.personal_best("test_scenario")["score"]), 4242, "the personal best survived")
	assert_true(bool(reloaded.progress.personal_best("test_scenario")["cleared"]), "the clear flag survived")


func test_written_files_are_versioned_json() -> void:
	service.save_all()
	var text := FileAccess.get_file_as_string(service.profile_path())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "the profile file is a JSON object")
	var data: Dictionary = parsed
	assert_eq(int(data["schema_version"]), VantaVersion.SAVE_SCHEMA_VERSION, "the file carries the save schema version")
	assert_true(data.has("training_days"), "the profile payload contains its documented keys")


# --- hostile files ---------------------------------------------------------

func test_corrupt_file_is_quarantined_and_kept() -> void:
	service.profile.record_session(_summary(10, 5, 1), 1700000000)
	service.save_all()
	_write_raw(service.profile_path(), "{ this is not json at all")
	var report := service.load_all()
	assert_eq(report["quarantined"].size(), 1, "the unreadable file was moved aside")
	assert_greater(float(report["errors"].size()), 0.0, "the problem was reported: %s" % str(report["errors"]))
	assert_eq(service.profile.sessions, 0, "defaults were used instead of the damaged file")
	assert_false(FileAccess.file_exists(service.profile_path()), "the damaged file no longer occupies the real path")
	assert_greater(float(_count_matching(TEST_DIR, ".corrupt-")), 0.0, "the damaged file is kept for inspection, not deleted")


func test_empty_file_is_recovered_from_the_backup() -> void:
	service.profile.record_session(_summary(0, 0, 0), 1700000000)
	service.save_all()
	service.profile.sessions = 7
	service.save_all()
	_write_raw(service.profile_path(), "")
	var report := service.load_all()
	assert_contains(report["recovered"], "profile", "the backup copy was used")
	assert_eq(service.profile.sessions, 1, "the recovered value is the last good one (the backup holds the first write)")
	assert_true(FileAccess.file_exists(service.profile_path()), "the good copy was put back in place")


func test_oversized_file_is_refused() -> void:
	_write_raw(service.history_path(), "x".repeat(VantaSaveService.MAX_FILE_BYTES + 1))
	var report := service.load_all()
	assert_greater(float(report["errors"].size()), 0.0, "an oversized file is reported")
	assert_string_contains("\n".join(report["errors"]), "larger than", "the reason names the size limit")
	assert_eq(service.history.count(), 0, "no entries were invented from the oversized file")


func test_newer_save_version_is_refused_not_guessed() -> void:
	_write_raw(service.progress_path(), JSON.stringify({
		"schema_version": VantaVersion.SAVE_SCHEMA_VERSION + 1,
		"personal_bests": {"test_scenario": {"score": 999999}},
	}))
	var report := service.load_all()
	assert_false(report["loaded"].has("progress"), "a newer save version is not loaded")
	assert_string_contains("\n".join(report["errors"]), "newer than this build", "the refusal explains why")
	assert_eq(service.progress.scenarios_played(), 0, "the store is still usable with defaults")


func test_v0_progress_is_migrated() -> void:
	_write_raw(service.progress_path(), JSON.stringify({
		"completed": ["static_precision_60"],
		"pbs": {"static_precision_60": 1337},
		"runs": 4,
	}))
	var report := service.load_all()
	assert_contains(report["loaded"], "progress", "a prototype-era progress file still loads")
	assert_eq(int(service.progress.personal_best("static_precision_60")["score"]), 1337, "the v0 personal best (a bare number) was migrated to a record")
	assert_true(service.progress.lesson_states.has("static_precision_60"), "the v0 completion list became lesson states")
	assert_string_contains("\n".join(report["repairs"]), "version 0", "the migration is reported to the player")


func test_v0_profile_and_history_are_migrated() -> void:
	_write_raw(service.profile_path(), JSON.stringify({"name": "EARLY", "sessions": 3, "play_seconds": 1800.0}))
	_write_raw(service.history_path(), JSON.stringify({"runs": [
		{"scenario": "micro_flick_60", "score": 900, "accuracy": 71.5, "at": 1699999999},
	]}))
	var report := service.load_all()
	assert_contains(report["loaded"], "profile", "a v0 profile loads")
	assert_eq(service.profile.player_name, "EARLY", "the v0 name survived")
	assert_eq(service.profile.sessions, 3, "the v0 session count survived")
	assert_almost_eq(service.profile.total_play_seconds, 1800.0, "the v0 play time survived", 0.001)
	assert_contains(report["loaded"], "history", "a v0 history loads")
	assert_eq(service.history.count(), 1, "the v0 run became a history entry")
	assert_eq(int(service.history.recent(1)[0]["score"]), 900, "the v0 run score survived")


func test_history_is_bounded() -> void:
	var summary := _summary(100, 10, 5)
	for i in 600:
		service.history.record(summary, 1700000000 + i)
	assert_eq(service.history.count(), VantaHistory.MAX_ENTRIES, "the history is capped at %d entries" % VantaHistory.MAX_ENTRIES)
	assert_eq(int(service.history.recent(1)[0]["at"]), 1700000000 + 599, "the newest entry is kept")


# --- settings --------------------------------------------------------------

func test_settings_live_outside_the_save_directory() -> void:
	assert_false(service.settings_path().begins_with(TEST_DIR), "settings are not stored inside the save directory")
	var settings := VantaSettings.default_settings()
	settings.sensitivity = 3.5
	settings.dpi = 1600
	var written := service.save_settings(settings)
	assert_true(bool(written["ok"]), "settings were written: %s" % str(written))
	var loaded := service.load_settings()
	assert_eq(loaded["errors"].size(), 0, "the written settings load cleanly: %s" % str(loaded["errors"]))
	var restored: VantaSettings = loaded["settings"]
	assert_almost_eq(restored.sensitivity, 3.5, "sensitivity survived", 0.0001)
	assert_eq(restored.dpi, 1600, "dpi survived")
	assert_greater(restored.cm_per_360(), 1.0, "the loaded settings can still compute cm/360")


func test_corrupt_settings_fall_back_to_defaults() -> void:
	_write_raw(service.settings_path(), "{{{ not json")
	var loaded := service.load_settings()
	assert_greater(float(loaded["errors"].size()), 0.0, "the unreadable settings file is reported")
	var restored: VantaSettings = loaded["settings"]
	assert_almost_eq(restored.sensitivity, 2.0, "defaults were used so the game can still launch", 0.0001)
	assert_greater(float(_count_matching(TEST_ROOT, ".corrupt-")), 0.0, "the unreadable settings file was kept aside")


# --- export and import -----------------------------------------------------

func test_export_import_round_trip() -> void:
	var summary := _summary(2500, 30, 9)
	service.profile.record_session(summary, 1700000000)
	service.progress.record_attempt(summary, 1700000000)
	service.history.record(summary, 1700000000)
	service.save_all()
	var exported := service.export_bundle(EXPORT_PATH)
	assert_true(bool(exported["ok"]), "the bundle was written: %s" % str(exported))
	assert_true(FileAccess.file_exists(EXPORT_PATH), "the bundle exists on disk")
	assert_true(String(exported["checksum"]).length() == 64, "the bundle carries a SHA-256 checksum")

	var fresh := VantaSaveService.new(ALT_DIRS[0])
	fresh.load_all()
	var imported := fresh.import_bundle(EXPORT_PATH)
	assert_true(bool(imported["ok"]), "the bundle imports: %s" % str(imported))
	assert_eq((imported["repairs"] as Array).size(), 0, "a clean bundle imports without repairs: %s" % str(imported["repairs"]))
	assert_eq(fresh.profile.sessions, 1, "the imported profile has the session")
	assert_eq(fresh.history.count(), 1, "the imported history has the run")
	assert_eq(int(fresh.progress.personal_best("test_scenario")["score"]), 2500, "the imported progress has the personal best")

	# And the import is durable: a second service reading the same directory sees it.
	var reread := VantaSaveService.new(ALT_DIRS[0])
	reread.load_all()
	assert_eq(reread.profile.sessions, 1, "the import was written to disk, not just held in memory")


func test_edited_bundle_is_refused() -> void:
	service.profile.record_session(_summary(100, 10, 5), 1700000000)
	service.save_all()
	service.export_bundle(EXPORT_PATH)
	var text := FileAccess.get_file_as_string(EXPORT_PATH)
	var parsed: Dictionary = JSON.parse_string(text)
	(parsed["profile"] as Dictionary)["sessions"] = 9999
	_write_raw(EXPORT_PATH, JSON.stringify(parsed))

	var fresh := VantaSaveService.new(ALT_DIRS[1])
	fresh.load_all()
	var imported := fresh.import_bundle(EXPORT_PATH)
	assert_false(bool(imported["ok"]), "an edited bundle is refused")
	assert_string_contains(String(imported["error"]), "checksum", "the refusal names the checksum")
	assert_eq(fresh.profile.sessions, 0, "the edited data was not applied")


func test_non_bundle_file_is_refused() -> void:
	_write_raw(EXPORT_PATH, JSON.stringify({"hello": "world"}))
	var fresh := VantaSaveService.new(ALT_DIRS[1])
	fresh.load_all()
	var imported := fresh.import_bundle(EXPORT_PATH)
	assert_false(bool(imported["ok"]), "a file that is not a bundle is refused")
	assert_string_contains(String(imported["error"]), "not a VANTA save bundle", "the refusal explains what it expected")


func test_export_refuses_a_directory_path() -> void:
	var exported := service.export_bundle("user://test/")
	assert_false(bool(exported["ok"]), "a directory path is not a valid export target")


# --- reset -----------------------------------------------------------------

func test_reset_progress_keeps_a_copy() -> void:
	service.profile.record_session(_summary(500, 20, 6), 1700000000)
	service.progress.record_attempt(_summary(500, 20, 6), 1700000000)
	service.save_all()
	service.reset_progress()
	assert_eq(service.profile.sessions, 0, "the profile was reset")
	assert_eq(service.history.count(), 0, "the history was reset")
	assert_eq(service.progress.scenarios_played(), 0, "the progress was reset")
	assert_greater(float(_count_matching(TEST_DIR, ".reset-")), 0.0, "the pre-reset data was kept as a copy")


# --- helpers ---------------------------------------------------------------

## A results summary shaped exactly like `ScenarioRuntime.build_summary()`.
func _summary(score: int, shots: int, kills: int) -> Dictionary:
	return {
		"scenario_id": "test_scenario",
		"scenario_name": "TEST SCENARIO",
		"mode": "static_precision",
		"skill": "aim_control.precision",
		"transfer_stage": "isolation",
		"weapon_id": "tactical_rifle",
		"arena_id": "dojo_open",
		"seed": 4242,
		"score": score,
		"score_breakdown": {"elimination": score},
		"finish_reason": "duration",
		"duration_seconds": 60.0,
		"stats": {
			"shots": shots,
			"hits": maxi(1, shots - 2),
			"misses": 2,
			"targets_eliminated": kills,
			"targets_spawned": kills + 1,
			"accuracy_percent": 83.5,
			"headshot_ratio_percent": 25.0,
			"consistency_percent": 42.0,
			"average_time_to_kill": 0.9,
			"longest_streak": kills,
			"duration_seconds": 60.0,
		},
		"success": {"met": true, "practice_only": false, "failures": []},
	}


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		assert_fail("could not write test file %s" % path)
		return
	handle.store_string(text)
	handle.close()


## Number of entries in `path` whose name contains `needle` (quarantine/reset copies).
func _count_matching(path: String, needle: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not directory.current_is_dir() and entry.contains(needle):
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


func _clean() -> void:
	for dir in ALT_DIRS:
		_remove_dir_contents(dir)
	_remove_dir_contents(TEST_DIR)
	for name in ["settings.json", "settings.bak.json", "export.vanta.json"]:
		_remove_file("%s/%s" % [TEST_ROOT, name])
	# Quarantine copies of settings live in the root as well.
	var root := DirAccess.open(TEST_ROOT)
	if root == null:
		return
	root.list_dir_begin()
	var entry := root.get_next()
	while entry != "":
		if not root.current_is_dir() and entry.contains(".corrupt-"):
			root.remove(entry)
		entry = root.get_next()
	root.list_dir_end()


func _remove_dir_contents(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not directory.current_is_dir():
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
