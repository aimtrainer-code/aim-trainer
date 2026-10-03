class_name VantaSettings
extends RefCounted

## User settings model.
##
## Responsibilities: hold values, validate them, and serialise them. It deliberately
## does **not** touch the engine (no DisplayServer calls, no viewport changes) — that
## is `DisplayService`'s job — so this class stays fully unit-testable and can never
## be the reason a gameplay frame stalls.
##
## Every field has an explicit type, an explicit default and an explicit validation
## rule in `_sanitise()`. Unknown keys in a saved file are ignored rather than
## rejected, so a file written by a newer build does not destroy a player's setup.

const SCHEMA_VERSION: int = 1

enum Orientation { TACTICAL_CS = 0, TACTICAL_VAL = 1, RAW = 2, CUSTOM = 3 }
enum WindowMode { EXCLUSIVE_FULLSCREEN = 0, BORDERLESS = 1, WINDOWED = 2 }
enum Preset { COMPETITIVE = 0, BALANCED = 1, QUALITY = 2 }
enum VSyncMode { DISABLED = 0, ENABLED = 1, ADAPTIVE = 2, MAILBOX = 3 }

const ORIENTATION_IDS: Array[String] = ["tactical_cs", "tactical_val", "raw", "custom"]
const ORIENTATION_LABELS: Array[String] = ["TACTICAL // CS", "TACTICAL // VAL", "RAW AIM", "CUSTOM"]
const PRESET_IDS: Array[String] = ["competitive", "balanced", "quality"]

# --- meta ------------------------------------------------------------------
var schema_version: int = SCHEMA_VERSION
var created_at: int = 0
var updated_at: int = 0

# --- identity --------------------------------------------------------------
var player_name: String = "PLAYER"
var orientation: int = Orientation.RAW
var onboarding_completed: bool = false

# --- display ---------------------------------------------------------------
var window_mode: int = WindowMode.BORDERLESS
var resolution: Vector2i = Vector2i(1920, 1080)
var vsync: int = VSyncMode.ENABLED
## Frame cap. 0 = uncapped (the engine's default). Values above 0 are enforced.
var fps_cap: int = 0
var render_preset: int = Preset.COMPETITIVE
var msaa: int = 0  ## 0/2/4/8 (Viewport.MSAA_*)
var render_scale: float = 1.0  ## 0.5 - 2.0, supersampling above 1.0
var ui_scale: float = 1.0  ## 0.8 - 1.6
## Informational only: what the OS reported for the chosen display. Never used to
## claim a measured refresh rate; the HUD shows measured frames per second instead.
var reported_refresh_hz: float = 0.0

# --- mouse -----------------------------------------------------------------
var dpi: int = 800
var sensitivity: float = 2.0
## Selected conversion profile id (see VantaSensitivity.GAME_PROFILES).
var sens_profile: String = "vanta"
## Degrees per count at sensitivity 1.0. Defaults to the Source `m_yaw` value.
var yaw_coefficient: float = VantaSensitivity.YAW_COEFFICIENT_SOURCE
var vertical_scale: float = 1.0
var invert_y: bool = false
## When true, VANTA asks the engine for one input event per hardware event instead
## of letting the engine coalesce them into one per frame. VANTA still accumulates
## internally, so rotation is identical; the difference is that per-event timing
## and event-rate diagnostics become observable. Default: false (engine default).
var per_event_mouse_input: bool = false
## Scale sensitivity while scoped, using the tangent FOV ratio.
var ads_zoom_scaling: bool = true

# --- crosshair -------------------------------------------------------------
var crosshair: VantaCrosshair = VantaCrosshair.new()

# --- audio (0.0 - 1.0) -----------------------------------------------------
var audio_master: float = 0.85
var audio_weapon: float = 0.85
var audio_hit: float = 0.95
var audio_ui: float = 0.7
var audio_mute_when_unfocused: bool = true

# --- accessibility ---------------------------------------------------------
var high_contrast: bool = false
var color_vision_palette: bool = false
var reduced_motion: bool = false
var flash_reduction: bool = false
var target_color_index: int = 0
var hit_markers_enabled: bool = true
var hud_scale: float = 1.0

# --- training / HUD --------------------------------------------------------
var focus_mode: bool = false
var hud_mode: int = 1  ## 0 = off, 1 = minimal, 2 = standard
var show_session_timer: bool = true
var auto_restart_delay: float = 0.0  ## 0 = instant respawn, no animation
var crosshair_during_ads_only: bool = false

# --- advanced --------------------------------------------------------------
var log_level: int = VantaLog.Level.INFO
var write_logs: bool = false


static func default_settings() -> VantaSettings:
	var s := VantaSettings.new()
	s.created_at = int(Time.get_unix_time_from_system())
	s.updated_at = s.created_at
	s.reported_refresh_hz = 0.0
	return s


func orientation_id() -> String:
	return ORIENTATION_IDS[clampi(orientation, 0, ORIENTATION_IDS.size() - 1)]


func orientation_label() -> String:
	return ORIENTATION_LABELS[clampi(orientation, 0, ORIENTATION_LABELS.size() - 1)]


func preset_id() -> String:
	return PRESET_IDS[clampi(render_preset, 0, PRESET_IDS.size() - 1)]


func touch() -> void:
	updated_at = int(Time.get_unix_time_from_system())


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"created_at": created_at,
		"updated_at": updated_at,
		"identity": {
			"player_name": player_name,
			"orientation": orientation_id(),
			"onboarding_completed": onboarding_completed,
		},
		"display": {
			"window_mode": window_mode,
			"resolution": [resolution.x, resolution.y],
			"vsync": vsync,
			"fps_cap": fps_cap,
			"render_preset": preset_id(),
			"msaa": msaa,
			"render_scale": render_scale,
			"ui_scale": ui_scale,
			"reported_refresh_hz": reported_refresh_hz,
		},
		"mouse": {
			"dpi": dpi,
			"sensitivity": sensitivity,
			"sens_profile": sens_profile,
			"yaw_coefficient": yaw_coefficient,
			"vertical_scale": vertical_scale,
			"invert_y": invert_y,
			"per_event_mouse_input": per_event_mouse_input,
			"ads_zoom_scaling": ads_zoom_scaling,
		},
		"crosshair": crosshair.to_dict(),
		"audio": {
			"master": audio_master,
			"weapon": audio_weapon,
			"hit": audio_hit,
			"ui": audio_ui,
			"mute_when_unfocused": audio_mute_when_unfocused,
		},
		"accessibility": {
			"high_contrast": high_contrast,
			"color_vision_palette": color_vision_palette,
			"reduced_motion": reduced_motion,
			"flash_reduction": flash_reduction,
			"target_color_index": target_color_index,
			"hit_markers_enabled": hit_markers_enabled,
			"hud_scale": hud_scale,
		},
		"training": {
			"focus_mode": focus_mode,
			"hud_mode": hud_mode,
			"show_session_timer": show_session_timer,
			"auto_restart_delay": auto_restart_delay,
			"crosshair_during_ads_only": crosshair_during_ads_only,
		},
		"advanced": {
			"log_level": log_level,
			"write_logs": write_logs,
		},
	}


## Builds a settings object from arbitrary (possibly hostile) data. Never throws:
## every value is clamped, coerced or replaced by its default, and the result is
## always usable. Returns the object plus a list of repairs for the caller to log.
static func from_dict(data: Variant) -> Dictionary:
	var s := VantaSettings.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		repairs.append("settings root is not an object; using defaults")
		return {"settings": default_settings(), "repairs": repairs}

	var root: Dictionary = data
	s.schema_version = _int(root.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION)
	s.created_at = _int(root.get("created_at", 0), 0)
	s.updated_at = _int(root.get("updated_at", 0), 0)

	var identity := _dict(root.get("identity", {}))
	s.player_name = _string(identity.get("player_name", "PLAYER"), "PLAYER").strip_edges()
	if s.player_name.length() > 24:
		s.player_name = s.player_name.substr(0, 24)
	s.orientation = ORIENTATION_IDS.find(_string(identity.get("orientation", "raw"), "raw"))
	if s.orientation < 0:
		s.orientation = Orientation.RAW
		repairs.append("unknown orientation; defaulted to RAW AIM")
	s.onboarding_completed = _bool(identity.get("onboarding_completed", false), false)

	var display := _dict(root.get("display", {}))
	s.window_mode = clampi(_int(display.get("window_mode", WindowMode.BORDERLESS), WindowMode.BORDERLESS), 0, WindowMode.size() - 1)
	s.resolution = _vector2i(display.get("resolution", [1920, 1080]), Vector2i(1920, 1080))
	s.resolution.x = clampi(s.resolution.x, 640, 7680)
	s.resolution.y = clampi(s.resolution.y, 480, 4320)
	s.vsync = clampi(_int(display.get("vsync", VSyncMode.ENABLED), VSyncMode.ENABLED), 0, VSyncMode.size() - 1)
	s.fps_cap = clampi(_int(display.get("fps_cap", 0), 0), 0, 1000)
	var preset_index := PRESET_IDS.find(_string(display.get("render_preset", "competitive"), "competitive"))
	s.render_preset = Preset.COMPETITIVE if preset_index < 0 else preset_index
	s.msaa = _int(display.get("msaa", 0), 0)
	if not [0, 2, 4, 8].has(s.msaa):
		s.msaa = 0
	s.render_scale = clampf(_float(display.get("render_scale", 1.0), 1.0), 0.5, 2.0)
	s.ui_scale = clampf(_float(display.get("ui_scale", 1.0), 1.0), 0.8, 1.6)
	s.reported_refresh_hz = clampf(_float(display.get("reported_refresh_hz", 0.0), 0.0), 0.0, 1000.0)

	var mouse := _dict(root.get("mouse", {}))
	s.dpi = clampi(_int(mouse.get("dpi", 800), 800), VantaSensitivity.DPI_MIN, VantaSensitivity.DPI_MAX)
	s.sensitivity = clampf(_float(mouse.get("sensitivity", 2.0), 2.0), VantaSensitivity.SENS_MIN, VantaSensitivity.SENS_MAX)
	s.sens_profile = _string(mouse.get("sens_profile", "vanta"), "vanta")
	s.yaw_coefficient = clampf(_float(mouse.get("yaw_coefficient", VantaSensitivity.YAW_COEFFICIENT_SOURCE), VantaSensitivity.YAW_COEFFICIENT_SOURCE), 0.0005, 1.0)
	s.vertical_scale = clampf(_float(mouse.get("vertical_scale", 1.0), 1.0), 0.1, 4.0)
	s.invert_y = _bool(mouse.get("invert_y", false), false)
	s.per_event_mouse_input = _bool(mouse.get("per_event_mouse_input", false), false)
	s.ads_zoom_scaling = _bool(mouse.get("ads_zoom_scaling", true), true)

	var ch := VantaCrosshair.from_dict(root.get("crosshair", {}))
	s.crosshair = ch["crosshair"]
	for r in ch["repairs"]:
		repairs.append("crosshair: %s" % r)

	var audio := _dict(root.get("audio", {}))
	s.audio_master = clampf(_float(audio.get("master", 0.85), 0.85), 0.0, 1.0)
	s.audio_weapon = clampf(_float(audio.get("weapon", 0.85), 0.85), 0.0, 1.0)
	s.audio_hit = clampf(_float(audio.get("hit", 0.95), 0.95), 0.0, 1.0)
	s.audio_ui = clampf(_float(audio.get("ui", 0.7), 0.7), 0.0, 1.0)
	s.audio_mute_when_unfocused = _bool(audio.get("mute_when_unfocused", true), true)

	var access := _dict(root.get("accessibility", {}))
	s.high_contrast = _bool(access.get("high_contrast", false), false)
	s.color_vision_palette = _bool(access.get("color_vision_palette", false), false)
	s.reduced_motion = _bool(access.get("reduced_motion", false), false)
	s.flash_reduction = _bool(access.get("flash_reduction", false), false)
	s.target_color_index = clampi(_int(access.get("target_color_index", 0), 0), 0, VantaStyle.TARGET_COLORS.size() - 1)
	s.hit_markers_enabled = _bool(access.get("hit_markers_enabled", true), true)
	s.hud_scale = clampf(_float(access.get("hud_scale", 1.0), 1.0), 0.8, 1.6)

	var training := _dict(root.get("training", {}))
	s.focus_mode = _bool(training.get("focus_mode", false), false)
	s.hud_mode = clampi(_int(training.get("hud_mode", 1), 1), 0, 2)
	s.show_session_timer = _bool(training.get("show_session_timer", true), true)
	s.auto_restart_delay = clampf(_float(training.get("auto_restart_delay", 0.0), 0.0), 0.0, 2.0)
	s.crosshair_during_ads_only = _bool(training.get("crosshair_during_ads_only", false), false)

	var advanced := _dict(root.get("advanced", {}))
	s.log_level = clampi(_int(advanced.get("log_level", VantaLog.Level.INFO), VantaLog.Level.INFO), 0, VantaLog.Level.TRACE)
	s.write_logs = _bool(advanced.get("write_logs", false), false)

	if s.high_contrast:
		# High contrast implies legibility over aesthetics; force the safe palette.
		s.color_vision_palette = true

	return {"settings": s, "repairs": repairs}


func duplicate_settings() -> VantaSettings:
	var copy := from_dict(to_dict())
	return copy["settings"]


# --- coercion helpers ------------------------------------------------------
# These exist because saved files are user-editable and may contain anything.

static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _int(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return int(value) if value.is_valid_int() else fallback
		TYPE_BOOL:
			return 1 if value else 0
		_:
			return fallback


static func _float(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_FLOAT:
			return value
		TYPE_INT:
			return float(value)
		TYPE_STRING:
			return float(value) if value.is_valid_float() else fallback
		_:
			return fallback


static func _bool(value: Variant, fallback: bool) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_STRING:
			return value.to_lower() in ["true", "1", "yes"]
		_:
			return fallback


static func _string(value: Variant, fallback: String) -> String:
	match typeof(value):
		TYPE_STRING:
			return value
		TYPE_STRING_NAME:
			return String(value)
		TYPE_NIL:
			return fallback
		_:
			return str(value)


static func _vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(_int(arr[0], fallback.x), _int(arr[1], fallback.y))
	return fallback
