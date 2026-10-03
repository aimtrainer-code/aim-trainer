class_name VantaRoot
extends Node2D

## First playable VANTA shell.
##
## This view intentionally stays thin: it owns presentation and the training loop,
## while App/InputService remain responsible for settings and raw mouse input.
## The first milestone is a dependency-free, playable click drill that boots directly
## from the existing root.tscn and can later be replaced by the full 3D arena without
## changing the simulation contracts.

const TARGET_RADIUS := 34.0
const TARGET_MIN := 70.0
const TARGET_MAX := 150.0
const TARGET_LIFETIME := 2.5
const TARGETS_TO_PLAY := 30
const HIT_FLASH_SECONDS := 0.08

var input_service: InputService
var target_position := Vector2.ZERO
var target_radius := TARGET_RADIUS
var target_alive := false
var target_spawn_time := 0.0
var target_count := 0
var hits := 0
var shots := 0
var score := 0
var streak := 0
var best_streak := 0
var total_reaction := 0.0
var running := false
var paused := false
var finished := false
var hit_flash := 0.0
var miss_flash := 0.0
var session_time := 0.0
var rng := RandomNumberGenerator.new()
var aim_point := Vector2.ZERO
var status_text := "CLICK TO START"
var status_detail := "30 targets  •  left click to shoot  •  R to restart  •  ESC to release mouse"
var last_result := ""

func _ready() -> void:
	set_process(true)
	rng.seed = 0x56414E5441
	input_service = InputService.new()
	input_service.name = "InputService"
	add_child(input_service)
	input_service.fire_pressed.connect(_on_fire)
	input_service.action_pressed.connect(_on_action)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	queue_redraw()

func _on_viewport_resized() -> void:
	if aim_point == Vector2.ZERO:
		aim_point = get_viewport_rect().size * 0.5
	else:
		aim_point.x = clampf(aim_point.x, 0.0, get_viewport_rect().size.x)
		aim_point.y = clampf(aim_point.y, 0.0, get_viewport_rect().size.y)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			paused = not paused if running else false
			input_service.release_mouse() if paused else input_service.grab_mouse()
			status_text = "PAUSED" if paused else "LIVE"
			queue_redraw()

func _process(delta: float) -> void:
	if input_service == null:
		return
	if not paused:
		var look := input_service.consume_look_delta()
		if running:
			# The simulation's sensitivity conversion remains the single source of truth.
			# A small presentation scale maps degrees to screen-space aim movement.
			var settings := App.settings if App != null else VantaSettings.default_settings()
			var angular := InputService.delta_to_angles(look, settings)
			aim_point += Vector2(angular.x, angular.y) * 7.0
			aim_point.x = clampf(aim_point.x, 24.0, get_viewport_rect().size.x - 24.0)
			aim_point.y = clampf(aim_point.y, 24.0, get_viewport_rect().size.y - 24.0)
		if running:
			session_time += delta
			if target_alive and session_time - target_spawn_time >= TARGET_LIFETIME:
				_register_miss("EXPIRED")
		if hit_flash > 0.0:
			hit_flash = maxf(0.0, hit_flash - delta)
		if miss_flash > 0.0:
			miss_flash = maxf(0.0, miss_flash - delta)
	queue_redraw()

func _on_fire() -> void:
	if finished or paused:
		return
	if not running:
		_start_session()
		return
	shots += 1
	if target_alive and aim_point.distance_to(target_position) <= target_radius:
		var reaction := session_time - target_spawn_time
		total_reaction += reaction
		hits += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		score += 100 + mini(streak, 10) * 10
		hit_flash = HIT_FLASH_SECONDS
		last_result = "HIT  %.0f ms" % (reaction * 1000.0)
		_spawn_target()
	else:
		streak = 0
		miss_flash = HIT_FLASH_SECONDS
		last_result = "MISS"
		status_text = "KEEP GOING"

func _on_action(action: String) -> void:
	match action:
		"restart_step":
			_start_session()
		"pause":
			paused = not paused
			if paused:
				input_service.release_mouse()
			else:
				input_service.grab_mouse()
			status_text = "PAUSED" if paused else "LIVE"
		"toggle_hud":
			queue_redraw()

func _start_session() -> void:
	target_count = 0
	hits = 0
	shots = 0
	score = 0
	streak = 0
	best_streak = 0
	total_reaction = 0.0
	session_time = 0.0
	finished = false
	running = true
	paused = false
	status_text = "LIVE"
	last_result = ""
	input_service.grab_mouse()
	_spawn_target()

func _spawn_target() -> void:
	if target_count >= TARGETS_TO_PLAY:
		_finish_session()
		return
	var size := get_viewport_rect().size
	var margin := 110.0
	var candidate := size * 0.5
	for _i in 12:
		candidate = Vector2(
			rng.randf_range(margin, maxf(margin, size.x - margin)),
			rng.randf_range(120.0, maxf(120.0, size.y - 90.0))
		)
		if candidate.distance_to(aim_point) > 150.0:
			break
	target_position = candidate
	target_radius = rng.randf_range(28.0, 42.0)
	target_count += 1
	target_spawn_time = session_time
	target_alive = true
	status_detail = "%d / %d targets  •  left click to shoot" % [target_count, TARGETS_TO_PLAY]

func _register_miss(reason: String) -> void:
	if not target_alive:
		return
	target_alive = false
	streak = 0
	last_result = reason
	_spawn_target()

func _finish_session() -> void:
	running = false
	finished = true
	target_alive = false
	input_service.release_mouse()
	var accuracy := (float(hits) / float(shots) * 100.0) if shots > 0 else 0.0
	var avg := (total_reaction / float(hits)) if hits > 0 else 0.0
	status_text = "SESSION COMPLETE"
	status_detail = "Accuracy %.1f%%  •  Avg reaction %.0f ms  •  Best streak %d  •  Score %d" % [
		accuracy, avg * 1000.0, best_streak, score
	]
	last_result = "PRESS R TO RUN AGAIN"

func _draw() -> void:
	var size := get_viewport_rect().size
	# Dark competitive backdrop.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080b10"))
	for x in range(0, int(size.x), 80):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.08, 0.10, 0.13, 0.55), 1.0)
	for y in range(0, int(size.y), 80):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.08, 0.10, 0.13, 0.55), 1.0)

	# Header.
	draw_string(ThemeDB.fallback_font, Vector2(32, 48), "VANTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#f2f5f7"))
	draw_string(ThemeDB.fallback_font, Vector2(32, 74), "TRAIN WHAT MATTERS.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#7f8b98"))
	var score_text := "SCORE  %06d    ACC  %.1f%%    STREAK  %02d" % [score, _accuracy(), streak]
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 32, 48), score_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 16, Color("#d9e0e6"))

	# Target.
	if target_alive and running and not paused:
		draw_circle(target_position, target_radius + 5.0, Color(0.05, 0.06, 0.08, 0.95))
		draw_circle(target_position, target_radius, Color("#dce6ed"))
		draw_circle(target_position, target_radius * 0.72, Color("#121820"))
		draw_circle(target_position, target_radius * 0.45, Color("#dce6ed"))
		draw_circle(target_position, target_radius * 0.20, Color("#121820"))

	# Crosshair and click feedback.
	var cross := aim_point
	var cross_color := Color("#f2f5f7")
	if hit_flash > 0.0:
		cross_color = Color("#78f2a4")
	elif miss_flash > 0.0:
		cross_color = Color("#ff6b78")
	draw_line(cross + Vector2(-18, 0), cross + Vector2(-5, 0), cross_color, 2.0)
	draw_line(cross + Vector2(5, 0), cross + Vector2(18, 0), cross_color, 2.0)
	draw_line(cross + Vector2(0, -18), cross + Vector2(0, -5), cross_color, 2.0)
	draw_line(cross + Vector2(0, 5), cross + Vector2(0, 18), cross_color, 2.0)
	draw_circle(cross, 2.0, cross_color)

	# Centre status.
	var status_y := size.y * 0.52
	draw_string(ThemeDB.fallback_font, Vector2(0, status_y), status_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 25, Color("#e7edf2"))
	draw_string(ThemeDB.fallback_font, Vector2(0, status_y + 30), status_detail, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color("#8794a1"))
	if not last_result.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(0, status_y + 56), last_result, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, cross_color)

	# Footer.
	draw_string(ThemeDB.fallback_font, Vector2(32, size.y - 28), "STATIC PRECISION  •  30 TARGETS  •  OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#697582"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 32, size.y - 28), "LMB SHOOT   R RESTART   ESC PAUSE", HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color("#697582"))

func _accuracy() -> float:
	return float(hits) / float(shots) * 100.0 if shots > 0 else 0.0
