class_name VantaDisplayService
extends RefCounted

## Applies display settings to the window and the root viewport.
##
## This is deliberately separate from `VantaApp`: settings are data, the window server
## is a side effect, and keeping them apart means a test can validate every value in a
## settings file without touching the display server at all.
##
## Everything here is applied idempotently — `apply()` may be called on every settings
## change, so a slider drag must not produce flicker.

## Standard desktop modes, in the order a player expects to see them. Modes larger
## than the desktop are dropped rather than offered, because offering a resolution the
## monitor cannot display is how players end up with a black screen.
const CANDIDATE_MODES: Array[Vector2i] = [
	Vector2i(3840, 2160), Vector2i(3440, 1440), Vector2i(2560, 1440), Vector2i(2560, 1080),
	Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1680, 1050), Vector2i(1600, 900),
	Vector2i(1440, 900), Vector2i(1366, 768), Vector2i(1280, 1024), Vector2i(1280, 800),
	Vector2i(1280, 720), Vector2i(1024, 768),
]

var last_error: String = ""
var applied_window_mode: int = -1
var applied_resolution: Vector2i = Vector2i.ZERO


func apply(settings: VantaSettings, viewport: Viewport) -> void:
	if settings == null:
		return
	last_error = ""
	_apply_window(settings)
	_apply_vsync(settings)
	_apply_frame_cap(settings)
	if viewport != null:
		_apply_viewport(settings, viewport)


func _apply_window(settings: VantaSettings) -> void:
	match settings.window_mode:
		VantaSettings.WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		VantaSettings.WindowMode.BORDERLESS:
			# Borderless fullscreen: the desktop runs at its own resolution and the
			# window covers it, which is what competitive players expect as the
			# default (no mode switch, no display renegotiation).
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if settings.resolution.x > 0 and settings.resolution.y > 0:
				DisplayServer.window_set_size(settings.resolution)
	applied_window_mode = settings.window_mode
	applied_resolution = settings.resolution


func _apply_vsync(settings: VantaSettings) -> void:
	match settings.vsync:
		VantaSettings.VSyncMode.DISABLED:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		VantaSettings.VSyncMode.ADAPTIVE:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		VantaSettings.VSyncMode.MAILBOX:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func _apply_frame_cap(settings: VantaSettings) -> void:
	# A hard cap is never required for correctness (the simulation is frame-rate
	# independent), but a cap below the refresh rate is the honest way to trade
	# smoothness for consistent frame times on a weak machine.
	Engine.max_fps = clampi(settings.fps_cap, 0, 1000)


func _apply_viewport(settings: VantaSettings, viewport: Viewport) -> void:
	match settings.msaa:
		2:
			viewport.msaa_3d = Viewport.MSAA_2X
		4:
			viewport.msaa_3d = Viewport.MSAA_4X
		8:
			viewport.msaa_3d = Viewport.MSAA_8X
		_:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = clampf(settings.render_scale, 0.5, 2.0)
	viewport.use_taa = false


# --- information -----------------------------------------------------------

static func desktop_size() -> Vector2i:
	var screen := DisplayServer.window_get_current_screen()
	var size := DisplayServer.screen_get_size(screen)
	if size.x <= 0 or size.y <= 0:
		return Vector2i(1920, 1080)
	return size


static func refresh_rate() -> float:
	var screen := DisplayServer.window_get_current_screen()
	var rate := DisplayServer.screen_get_refresh_rate(screen)
	if rate <= 0.0:
		# Unknown refresh rate: report 0 rather than pretending it is 60 Hz. The
		# settings screen shows "unknown" for 0.
		return 0.0
	return rate


## Resolutions offered in the video settings, filtered to what the monitor can show.
static func resolution_options() -> Array[Vector2i]:
	var desktop := desktop_size()
	var options: Array[Vector2i] = []
	var exact_match := false
	for mode in CANDIDATE_MODES:
		if mode.x <= desktop.x and mode.y <= desktop.y:
			options.append(mode)
			if mode == desktop:
				exact_match = true
	if not exact_match:
		options.push_front(desktop)
	return options


static func mode_label(mode: VantaSettings.WindowMode) -> String:
	match mode:
		VantaSettings.WindowMode.FULLSCREEN:
			return "EXCLUSIVE FULLSCREEN"
		VantaSettings.WindowMode.BORDERLESS:
			return "BORDERLESS FULLSCREEN"
		_:
			return "WINDOWED"


static func describe(settings: VantaSettings) -> String:
	if settings == null:
		return ""
	var rate := refresh_rate()
	var rate_text := "refresh rate unknown" if rate <= 0.0 else "%d Hz" % int(round(rate))
	var resolution_text := "desktop" if settings.window_mode == VantaSettings.WindowMode.BORDERLESS else "%d×%d" % [settings.resolution.x, settings.resolution.y]
	return "%s · %s · %s" % [mode_label(settings.window_mode), resolution_text, rate_text]
