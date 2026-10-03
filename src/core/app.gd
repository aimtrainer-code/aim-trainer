class_name VantaApp
extends Node

## The application singleton (autoloaded as `App`).
##
## It owns exactly the things that must exist before any screen does: settings, the
## content library, the save service and the frame diagnostics. It contains no UI and
## no gameplay: screens read `App.content`, gameplay reads what the screen hands it.
## That keeps the dependency graph a tree (App → screen → world → simulation) instead
## of the free-for-all that autoload singletons usually become.

const SETTINGS_FLUSH_DELAY: float = 1.5
const DIAGNOSTICS_FLUSH_INTERVAL: float = 0.25

var settings: VantaSettings = null
var content: VantaContentLibrary = null
var save: VantaSaveService = null
var frame_diagnostics: FrameDiagnostics = null

var content_ready: bool = false
var boot_finished: bool = false
var boot_report: Dictionary = {}

var _settings_dirty: bool = false
var _settings_flush_timer: float = 0.0
var _diagnostics_timer: float = 0.0
var _last_session_summary: Dictionary = {}


func _ready() -> void:
	VantaLog.info("app", "VANTA %s starting" % VantaVersion.string())
	frame_diagnostics = FrameDiagnostics.new()
	frame_diagnostics.begin()

	save = VantaSaveService.new()
	settings = _load_settings()
	VantaLog.set_file_logging(settings.write_logs)

	var save_report := save.load_all()
	for error in save_report["errors"]:
		VantaLog.warn("save", String(error))
	for repair in save_report["repairs"]:
		VantaLog.info("save", String(repair))

	content = VantaContentLibrary.new()
	boot_report["content"] = content.load_all()
	content_ready = bool(boot_report["content"]["ok"])
	for error in content.errors:
		VantaLog.error("content", String(error))
	for warning in content.warnings:
		VantaLog.warn("content", String(warning))
	VantaLog.info("app", "content: %d weapons, %d arenas, %d scenarios (%d file(s))" % [
		content.weapons.size(), content.arenas.size(), content.scenarios.size(), content.loaded_files,
	])

	if not settings.player_name.is_empty() and settings.player_name != "PLAYER":
		save.profile.player_name = settings.player_name

	if Events != null:
		Events.settings_changed.connect(_on_settings_changed)
	boot_finished = true
	VantaLog.info("app", "boot complete in %d ms" % int(Time.get_ticks_msec()))
	if Events != null:
		Events.app_ready.emit()


func _process(delta: float) -> void:
	if frame_diagnostics != null:
		frame_diagnostics.on_frame(delta)
	_diagnostics_timer += delta
	if _diagnostics_timer >= DIAGNOSTICS_FLUSH_INTERVAL:
		_diagnostics_timer = 0.0
		if Events != null:
			Events.diagnostics_updated.emit(frame_diagnostics.snapshot())
	if _settings_dirty:
		_settings_flush_timer += delta
		if _settings_flush_timer >= SETTINGS_FLUSH_DELAY:
			flush_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush_settings()
		if save != null:
			save.save_all()


# --- settings --------------------------------------------------------------

func _load_settings() -> VantaSettings:
	var result := save.load_settings()
	for error in result["errors"]:
		VantaLog.warn("settings", String(error))
	for repair in result["repairs"]:
		VantaLog.info("settings", String(repair))
	return result["settings"]


## Marks settings as changed and schedules a write. Every settings control calls this,
## so dragging a slider produces one write instead of fifty.
func mark_settings_dirty(section: String = "") -> void:
	_settings_dirty = true
	_settings_flush_timer = 0.0
	if Events != null and not section.is_empty():
		Events.settings_changed.emit(section)


func flush_settings() -> void:
	if not _settings_dirty or settings == null:
		return
	_settings_dirty = false
	_settings_flush_timer = 0.0
	var result := save.save_settings(settings)
	if not bool(result["ok"]):
		VantaLog.error("settings", String(result["error"]))


func _on_settings_changed(_section: String) -> void:
	# Screens that need to react (the crosshair preview, for example) listen to the
	# bus themselves; App only owns persistence.
	pass


# --- sessions --------------------------------------------------------------

## Records a finished attempt into every store that cares and returns what the results
## screen should say about it ("new personal best", "first clear").
func record_session(summary: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	save.profile.record_session(summary, now)
	var attempt := save.progress.record_attempt(summary, now)
	save.history.record(summary, now)
	save.dirty = true
	save.save_all()
	_last_session_summary = summary
	if Events != null:
		Events.session_finished.emit(summary)
	return attempt


func last_session_summary() -> Dictionary:
	return _last_session_summary


func player_name() -> String:
	return save.profile.player_name if save != null else "PLAYER"


func set_player_name(value: String) -> void:
	var cleaned := value.strip_edges()
	if cleaned.length() > 24:
		cleaned = cleaned.substr(0, 24)
	if cleaned.is_empty():
		cleaned = "PLAYER"
	save.profile.player_name = cleaned
	settings.player_name = cleaned
	mark_settings_dirty("identity")
	save.save_all()


# --- saves -----------------------------------------------------------------

func export_save_bundle(path: String) -> Dictionary:
	return save.export_bundle(path)


func import_save_bundle(path: String) -> Dictionary:
	return save.import_bundle(path)


func reset_progress() -> void:
	save.reset_progress()


# --- lifecycle -------------------------------------------------------------

func quit_game() -> void:
	flush_settings()
	save.save_all()
	VantaLog.info("app", "quit requested")
	get_tree().quit()


## A compact description of the running build for the diagnostics screen and for bug
## reports. Deliberately honest: it reports what is enabled, not what is claimed.
func build_info() -> Dictionary:
	return {
		"version": VantaVersion.string(),
		"engine": Engine.get_version_info()["string"],
		"platform": OS.get_name(),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"content_ready": content_ready,
		"content": content.content_counts() if content != null else {},
		"save": save.status_line() if save != null else "",
	}
