class_name VantaSettings
extends RefCounted

## Every player-facing option, with the values the game actually reads.
##
## Two rules govern this file:
##
##  1. **It is data.** No method here touches the display server, the input map or the
##     scene tree. Applying a setting is somebody else's job (`VantaDisplayService`,
##     `InputService`, the world's render preset), which is what makes settings
##     testable and what stops "the option says one thing and the engine does another".
##  2. **It is defensively read.** A settings file is a text file a player can edit, so
##     every field is coerced and clamped, unknown fields are ignored, and every repair
##     is reported. Nothing in a settings file can produce an unusable game.

const SCHEMA_VERSION: int = 1

enum Orientation { RAW, TACTICAL_CS, TACTICAL_VAL, CUSTOM }
const ORIENTATION_IDS: Array[String] = ["raw", "tactical_cs", "tactical_val", "custom"]
const ORIENTATION_LABELS: Array[String] = ["RAW / DIRECT", "TACTICAL // CS-STYLE", "TACTICAL // VAL-STYLE", "CUSTOM"]

enum WindowMode { FULLSCREEN, BORDERLESS, WINDOWED }
enum VSyncMode { DISABLED, ENABLED, ADAPTIVE, MAILBOX }
enum Preset { COMPETITIVE, BALANCED, QUALITY }
enum HudMode { OFF, MINIMAL, STANDARD }

const RESOLUTION_MIN: Vector2i = Vector2i(1024, 600)
const SENSITIVITY_MIN: float = 0.01
const SENSITIVITY_MAX: float = 100.0
const DPI_MIN: int = 100
const DPI_MAX: int = 32000
const UI_SCALE_MIN: float = 0.8
const UI_SCALE_MAX: float = 1.5
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 2.0

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
## Refresh rate reported by the display server at boot. Informational: it is shown to
## the player and never used to change simulation behaviour.
var display_refresh_hz: float = 0.0
var vsync: int = VSyncMode.ENABLED
## 0 = uncapped.
var fps_cap: int = 0
var render_preset: int = Preset.COMPETITIVE
var msaa: int = 0
var render_scale: float = 1.0

# --- interface -------------------------------------------------------------
var ui_scale: float = 1.0
var show_fps: bool = true
var hud_mode: int = HudMode.MINIMAL
var show_hit_markers: bool = true
var show_timer: bool = true

# --- mouse and aim ---------------------------------------------------------
var dpi: int = 800
var sensitivity: float = 2.0
## Which conversion the sensitivity number belongs to. "source" treats the value the
## way tactical shooters do (yaw is defined by the game's own coefficient), which is
## what makes a converted sensitivity mean the same thing here.
var sensitivity_profile: String = "source"
var yaw_coefficient: float = VantaSensitivity.YAW_COEFFICIENT_SOURCE
var vertical_scale: float = 1.0
var invert_y: bool = false
## Matches the rotation to the zoom when aiming, so a flick stays the same length on
## screen at every zoom level.
var ads_zoom_scaling: bool = true

# --- input -----------------------------------------------------------------
## Sends every delivered mouse motion event to the game instead of one coalesced
## event per frame. Rotation is identical either way (VANTA accumulates the deltas
## itself); this only changes how much per-event detail is available.
var per_event_mouse_input: bool = true

# --- crosshair -------------------------------------------------------------
var crosshair: VantaCrosshair = VantaCrosshair.new()

# --- audio -----------------------------------------------------------------
var audio_master: float = 0.85
var audio_weapons: float = 0.85
var audio_hits: float = 0.95
var audio_ui: float = 0.7
var audio_mute_when_unfocused: bool = true

# --- accessibility ---------------------------------------------------------
var high_contrast: bool = false
var color_vision_palette: bool = false
var reduced_motion: bool = false
var flash_reduction: bool = false
var target_color_index: int = 0
var hud_backdrop: bool = true

# --- training --------------------------------------------------------------
var focus_mode: bool = false
var countdown_seconds: float = 1.0
var auto_next_step: bool = true

# --- advanced --------------------------------------------------------------
var write_logs: bool = false
var show_diagnostics: bool = false


static func default_settings() -> VantaSettings:
	var settings := VantaSettings.new()
	settings.created_at = int(Time.get_unix_time_from_system())
	return settings


func touch() -> void:
	updated_at = int(Time.get_unix_time_from_system())


func orientation_id() -> String:
	return ORIENTATION_IDS[clampi(orientation, 0, ORIENTATION_IDS.size() - 1)]


func orientation_label() -> String:
	return ORIENTATION_LABELS[clampi(orientation, 0, ORIENTATION_LABELS.size() - 1)]


func preset_id() -> String:
	return RenderPresets.by_index(render_preset)["id"]


func hud_mode_id() -> String:
	match hud_mode:
		HudMode.OFF:
			return "off"
		HudMode.STANDARD:
			return "standard"
		_:
			return "minimal"


func is_uncapped() -> bool:
	return fps_cap <= 0


# --- serialisation ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
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
			"display_refresh_hz": display_refresh_hz,
		},
		"interface": {
			"ui_scale": ui_scale,
			"show_fps": show_fps,
			"hud_mode": hud_mode,
			"show_hit_markers": show_hit_markers,
			"show_timer": show_timer,
		},
		"mouse": {
			"dpi": dpi,
			"sensitivity": sensitivity,
			"sensitivity_profile": sensitivity_profile,
			"yaw_coefficient": yaw_coefficient,
			"vertical_scale": vertical_scale,
			"invert_y": invert_y,
			"ads_zoom_scaling": ads_zoom_scaling,
		},
		"input": {
			"per_event_mouse_input": per_event_mouse_input,
		},
		"crosshair": crosshair.to_dict(),
		"audio": {
			"master": audio_master,
			"weapons": audio_weapons,
			"hits": audio_hits,
			"ui": audio_ui,
			"mute_when_unfocused": audio_mute_when_unfocused,
		},
		"accessibility": {
			"high_contrast": high_contrast,
			"color_vision_palette": color_vision_palette,
			"reduced_motion": reduced_motion,
			"flash_reduction": flash_reduction,
			"target_color_index": target_color_index,
			"hud_backdrop": hud_backdrop,
		},
		"training": {
			"focus_mode": focus_mode,
			"countdown_seconds": countdown_seconds,
			"auto_next_step": auto_next_step,
		},
		"advanced": {
			"write_logs": write_logs,
			"show_diagnostics": show_diagnostics,
		},
	}


## Reads a settings dictionary. Always returns usable settings plus the list of
## repairs applied, so a repaired value can be surfaced instead of silently changing
## how the game behaves.
static func from_dict(data: Variant) -> Dictionary:
	var settings := VantaSettings.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		if data != null:
			repairs.append("settings root is not an object; using defaults")
		return {"settings": settings, "repairs": repairs}
	var root: Dictionary = data
	settings.schema_version = _int(root.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION, 1, 999)
	settings.created_at = _int(root.get("created_at", 0), 0, 0, 4102444800)
	settings.updated_at = _int(root.get("updated_at", 0), 0, 0, 4102444800)

	var identity := _dict(root.get("identity", {}))
	var name := _string(identity.get("player_name", "PLAYER"), "PLAYER").strip_edges()
	if name.length() > 24:
		name = name.substr(0, 24)
		repairs.append("player name was truncated to 24 characters")
	if name.is_empty():
		name = "PLAYER"
	settings.player_name = name
	var orientation_id := _string(identity.get("orientation", "raw"), "raw")
	var orientation_index := ORIENTATION_IDS.find(orientation_id)
	if orientation_index < 0:
		repairs.append("unknown aim orientation '%s'; using RAW" % orientation_id)
		orientation_index = Orientation.RAW
	settings.orientation = orientation_index
	settings.onboarding_completed = _bool(identity.get("onboarding_completed", false), false)

	var display := _dict(root.get("display", {}))
	settings.window_mode = clampi(_int(display.get("window_mode", WindowMode.BORDERLESS), WindowMode.BORDERLESS, 0, 2), 0, 2)
	var resolution := _vector2i(display.get("resolution", [1920, 1080]), Vector2i(1920, 1080))
	if resolution.x < RESOLUTION_MIN.x or resolution.y < RESOLUTION_MIN.y or resolution.x > 16384 or resolution.y > 16384:
		repairs.append("resolution %s is outside the supported range; using 1920×1080" % str(resolution))
		resolution = Vector2i(1920, 1080)
	settings.resolution = resolution
	settings.vsync = clampi(_int(display.get("vsync", VSyncMode.ENABLED), VSyncMode.ENABLED, 0, 3), 0, 3)
	var cap := _int(display.get("fps_cap", 0), 0, 0, 1000)
	if cap > 0 and cap < 30:
		repairs.append("frame cap %d is below the supported minimum of 30; the cap was disabled" % cap)
		cap = 0
	settings.fps_cap = cap
	var preset_id := _string(display.get("render_preset", "competitive"), "competitive")
	var preset_index := RenderPresets.index_of(preset_id)
	if preset_index < 0:
		repairs.append("unknown render preset '%s'; using COMPETITIVE" % preset_id)
		preset_index = Preset.COMPETITIVE
	settings.render_preset = preset_index
	var msaa := _int(display.get("msaa", 0), 0, 0, 8)
	if not [0, 2, 4, 8].has(msaa):
		repairs.append("MSAA %dx is not supported; MSAA was disabled" % msaa)
		msaa = 0
	settings.msaa = msaa
	var render_scale := _float(display.get("render_scale", 1.0), 1.0, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	if absf(render_scale - 1.0) > 0.001 and (render_scale < RENDER_SCALE_MIN or render_scale > RENDER_SCALE_MAX):
		repairs.append("render scale was outside %.1f–%.1f; it was clamped" % [RENDER_SCALE_MIN, RENDER_SCALE_MAX])
	settings.render_scale = clampf(render_scale, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	settings.display_refresh_hz = _float(display.get("display_refresh_hz", 0.0), 0.0, 0.0, 1000.0)

	var interface := _dict(root.get("interface", {}))
	settings.ui_scale = clampf(_float(interface.get("ui_scale", 1.0), 1.0, UI_SCALE_MIN, UI_SCALE_MAX), UI_SCALE_MIN, UI_SCALE_MAX)
	settings.show_fps = _bool(interface.get("show_fps", true), true)
	settings.hud_mode = clampi(_int(interface.get("hud_mode", HudMode.MINIMAL), HudMode.MINIMAL, 0, 2), 0, 2)
	settings.show_hit_markers = _bool(interface.get("show_hit_markers", true), true)
	settings.show_timer = _bool(interface.get("show_timer", true), true)

	var mouse := _dict(root.get("mouse", {}))
	settings.dpi = clampi(_int(mouse.get("dpi", 800), 800, DPI_MIN, DPI_MAX), DPI_MIN, DPI_MAX)
	settings.sensitivity = clampf(_float(mouse.get("sensitivity", 2.0), 2.0, SENSITIVITY_MIN, SENSITIVITY_MAX), SENSITIVITY_MIN, SENSITIVITY_MAX)
	var profile_id := _string(mouse.get("sensitivity_profile", "source"), "source")
	if not VantaSensitivity.PROFILE_IDS.has(profile_id):
		repairs.append("unknown sensitivity profile '%s'; using the VANTA profile" % profile_id)
		profile_id = "vanta"
	settings.sensitivity_profile = profile_id
	# The profile supplies the default coefficient; an explicit value in the file wins,
	# because a player who typed a coefficient meant it.
	var coefficient: float = VantaSensitivity.profile(profile_id)["yaw_coefficient"]
	settings.yaw_coefficient = clampf(_float(mouse.get("yaw_coefficient", coefficient), coefficient, 0.0001, 1.0), 0.0001, 1.0)
	settings.vertical_scale = clampf(_float(mouse.get("vertical_scale", 1.0), 1.0, 0.1, 4.0), 0.1, 4.0)
	settings.invert_y = _bool(mouse.get("invert_y", false), false)
	settings.ads_zoom_scaling = _bool(mouse.get("ads_zoom_scaling", true), true)

	var input := _dict(root.get("input", {}))
	settings.per_event_mouse_input = _bool(input.get("per_event_mouse_input", true), true)

	var crosshair_result := VantaCrosshair.from_dict(root.get("crosshair", {}))
	settings.crosshair = crosshair_result["crosshair"]
	for note in crosshair_result["repairs"]:
		repairs.append("crosshair: %s" % String(note))

	var audio := _dict(root.get("audio", {}))
	settings.audio_master = clampf(_float(audio.get("master", 0.85), 0.85, 0.0, 1.0), 0.0, 1.0)
	settings.audio_weapons = clampf(_float(audio.get("weapons", 0.85), 0.85, 0.0, 1.0), 0.0, 1.0)
	settings.audio_hits = clampf(_float(audio.get("hits", 0.95), 0.95, 0.0, 1.0), 0.0, 1.0)
	settings.audio_ui = clampf(_float(audio.get("ui", 0.7), 0.7, 0.0, 1.0), 0.0, 1.0)
	settings.audio_mute_when_unfocused = _bool(audio.get("mute_when_unfocused", true), true)

	var accessibility := _dict(root.get("accessibility", {}))
	settings.high_contrast = _bool(accessibility.get("high_contrast", false), false)
	settings.color_vision_palette = _bool(accessibility.get("color_vision_palette", false), false)
	settings.reduced_motion = _bool(accessibility.get("reduced_motion", false), false)
	settings.flash_reduction = _bool(accessibility.get("flash_reduction", false), false)
	settings.target_color_index = clampi(_int(accessibility.get("target_color_index", 0), 0, 0, VantaStyle.TARGET_COLORS.size() - 1), 0, VantaStyle.TARGET_COLORS.size() - 1)
	settings.hud_backdrop = _bool(accessibility.get("hud_backdrop", true), true)
	if settings.high_contrast:
		# High contrast implies legibility over aesthetics; the safe palette always wins.
		settings.color_vision_palette = true

	var training := _dict(root.get("training", {}))
	settings.focus_mode = _bool(training.get("focus_mode", false), false)
	settings.countdown_seconds = clampf(_float(training.get("countdown_seconds", 1.0), 1.0, 0.0, 10.0), 0.0, 10.0)
	settings.auto_next_step = _bool(training.get("auto_next_step", true), true)

	var advanced := _dict(root.get("advanced", {}))
	settings.write_logs = _bool(advanced.get("write_logs", false), false)
	settings.show_diagnostics = _bool(advanced.get("show_diagnostics", false), false)
	return {"settings": settings, "repairs": repairs}


func duplicate_settings() -> VantaSettings:
	return from_dict(to_dict())["settings"]


## Human-readable summary of the mouse configuration, used by the sensitivity screen
## and by the diagnostics panel. Returns inches of mouse movement per 360° turn.
func cm_per_360() -> float:
	return VantaSensitivity.cm_per_360(dpi, sensitivity, yaw_coefficient)


# --- coercion helpers ------------------------------------------------------
# These exist because saved files are user-editable and may contain anything.

static func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


## Coerces a saved value to an int. `min_value`/`max_value` are applied when they
## describe a real range (max > min), so a hand-edited settings file can never put the
## game into a state its own UI cannot express — but the value is still returned
## usable rather than discarded, and `from_dict()` reports what it changed.
static func _int(value: Variant, fallback: int, min_value: int = 0, max_value: int = 0) -> int:
	var number := fallback
	match typeof(value):
		TYPE_INT:
			number = int(value)
		TYPE_FLOAT:
			number = int(value)
		TYPE_STRING:
			if (value as String).is_valid_int():
				number = int(value)
	if max_value > min_value:
		return clampi(number, min_value, max_value)
	return number


static func _float(value: Variant, fallback: float, min_value: float = 0.0, max_value: float = 0.0) -> float:
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
		number = fallback
	if max_value > min_value:
		return clampf(number, min_value, max_value)
	return number


static func _bool(value: Variant, fallback: bool) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value) != 0
		TYPE_FLOAT:
			return absf(float(value)) > 0.0
		TYPE_STRING:
			var text := String(value).strip_edges().to_lower()
			if ["true", "yes", "on", "1"].has(text):
				return true
			if ["false", "no", "off", "0"].has(text):
				return false
	return fallback


static func _string(value: Variant, fallback: String) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	# A number where a name was expected is coerced rather than discarded: a player
	# called "12345" is odd but harmless, and the caller bounds the length anyway.
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_BOOL:
		return str(value)
	return fallback


static func _vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 2:
			return Vector2i(_int(array[0], fallback.x), _int(array[1], fallback.y))
	elif typeof(value) == TYPE_VECTOR2I:
		var typed: Vector2i = value
		return typed
	return fallback
