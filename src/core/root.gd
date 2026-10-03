class_name VantaRoot
extends Node2D

## Public playable VANTA build.
## This is the presentation layer for the existing deterministic/content-driven core:
## scenario selection -> aim drill -> results -> replay.
##
## The first release deliberately uses a lightweight 2D renderer. It makes the project
## immediately playable on Windows without adding a physics dependency, while keeping
## the existing ScenarioDefinition/ContentLibrary/SaveService contracts intact.

const SCENARIO_ORDER := [
	"static_precision_60", "micro_flick_60", "wide_flick_60",
	"dynamic_clicking_60", "smooth_tracking_30", "reactive_tracking_30",
	"target_switching_45", "headshot_matrix_60", "movement_aim_60", "peek_lab_45",
]
const TARGET_RADIUS_MIN := 18.0
const TARGET_RADIUS_MAX := 48.0
const TARGET_LIFETIME_DEFAULT := 2.0

enum Screen { MENU, RUN, RESULTS }

var input_service: InputService
var screen: Screen = Screen.MENU
var selected := 0
var scenario_id := "static_precision_60"
var definition: ScenarioDefinition = null

var rng := RandomNumberGenerator.new()
var aim_point := Vector2.ZERO
var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO
var target_radius := 32.0
var target_alive := false
var target_spawn_time := 0.0
var session_time := 0.0
var target_count := 0
var hits := 0
var shots := 0
var score := 0
var streak := 0
var best_streak := 0
var total_reaction := 0.0
var last_result := ""
var paused := false
var hit_flash := 0.0
var miss_flash := 0.0
var finished := false
var menu_mouse := Vector2.ZERO

func _ready() -> void:
	rng.randomize()
	input_service = InputService.new()
	input_service.name = "InputService"
	add_child(input_service)
	input_service.fire_pressed.connect(_on_fire)
	input_service.action_pressed.connect(_on_action)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_load_scenario()
	input_service.release_mouse()
	queue_redraw()

func _on_resize() -> void:
	if aim_point == Vector2.ZERO:
		aim_point = get_viewport_rect().size * 0.5
	queue_redraw()

func _process(delta: float) -> void:
	if input_service == null:
		return

	if screen == Screen.MENU:
		menu_mouse = get_viewport().get_mouse_position()
	elif screen == Screen.RUN and not paused:
		var look := input_service.consume_look_delta()
		var settings := App.settings if App != null and App.settings != null else VantaSettings.default_settings()
		var angular := InputService.delta_to_angles(look, settings)
		aim_point += Vector2(angular.x, angular.y) * 7.0
		var size := get_viewport_rect().size
		aim_point.x = clampf(aim_point.x, 24.0, size.x - 24.0)
		aim_point.y = clampf(aim_point.y, 90.0, size.y - 40.0)
		session_time += delta
		_update_target(delta)
		if target_alive and session_time - target_spawn_time >= _lifetime():
			_register_expiry()
		if _duration() > 0.0 and session_time >= _duration():
			_finish_session()
	elif screen == Screen.RESULTS:
		menu_mouse = get_viewport().get_mouse_position()

	hit_flash = maxf(0.0, hit_flash - delta)
	miss_flash = maxf(0.0, miss_flash - delta)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			if screen == Screen.RUN:
				paused = not paused
				if paused:
					input_service.release_mouse()
				else:
					input_service.grab_mouse()
			elif screen == Screen.RESULTS:
				screen = Screen.MENU
				input_service.release_mouse()
			else:
				get_tree().quit()
			queue_redraw()
			return

		if screen == Screen.MENU:
			if key.keycode >= KEY_1 and key.keycode <= KEY_9:
				selected = clampi(int(key.keycode - KEY_1), 0, SCENARIO_ORDER.size() - 1)
				_load_scenario()
			if key.keycode == KEY_0:
				selected = mini(9, SCENARIO_ORDER.size() - 1)
				_load_scenario()
			if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
				_start_session()
		elif screen == Screen.RESULTS:
			if key.keycode == KEY_R or key.keycode == KEY_ENTER:
				_start_session()
			elif key.keycode == KEY_M:
				screen = Screen.MENU
				input_service.release_mouse()
			queue_redraw()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if screen == Screen.MENU:
			_handle_menu_click(mb.position)
		elif screen == Screen.RESULTS:
			_handle_results_click(mb.position)

func _handle_menu_click(position: Vector2) -> void:
	var size := get_viewport_rect().size
	var list_top := 170.0
	var row_h := 48.0
	if position.x >= 80.0 and position.x <= size.x * 0.58:
		var index := int(floor((position.y - list_top) / row_h))
		if index >= 0 and index < SCENARIO_ORDER.size():
			selected = index
			_load_scenario()
			queue_redraw()
			return
	var button := Rect2(size.x * 0.68, size.y - 125.0, 260.0, 58.0)
	if button.has_point(position):
		_start_session()

func _handle_results_click(position: Vector2) -> void:
	var size := get_viewport_rect().size
	if Rect2(size.x * 0.5 - 150.0, size.y * 0.67, 300.0, 56.0).has_point(position):
		_start_session()
	elif Rect2(size.x * 0.5 - 150.0, size.y * 0.67 + 70.0, 300.0, 48.0).has_point(position):
		screen = Screen.MENU
		input_service.release_mouse()
		queue_redraw()

func _load_scenario() -> void:
	if selected < 0 or selected >= SCENARIO_ORDER.size():
		selected = 0
	scenario_id = SCENARIO_ORDER[selected]
	definition = null
	if App != null and App.content != null:
		definition = App.content.scenario(scenario_id)

func _start_session() -> void:
	_load_scenario()
	if definition == null:
		return
	screen = Screen.RUN
	paused = false
	finished = false
	target_alive = false
	target_count = 0
	hits = 0
	shots = 0
	score = 0
	streak = 0
	best_streak = 0
	total_reaction = 0.0
	session_time = 0.0
	last_result = "READY"
	input_service.grab_mouse()
	_spawn_target()

func _on_action(action: String) -> void:
	match action:
		"restart_step":
			if screen == Screen.RUN:
				_start_session()
			elif screen == Screen.RESULTS:
				_start_session()
		"pause":
			if screen == Screen.RUN:
				paused = not paused
				if paused:
					input_service.release_mouse()
				else:
					input_service.grab_mouse()
		"next_step":
			if screen == Screen.MENU:
				selected = (selected + 1) % SCENARIO_ORDER.size()
				_load_scenario()

func _on_fire() -> void:
	if screen == Screen.MENU:
		return
	if screen == Screen.RESULTS:
		_start_session()
		return
	if paused or finished:
		return
	shots += 1
	if target_alive and aim_point.distance_to(target_position) <= target_radius:
		var reaction := session_time - target_spawn_time
		total_reaction += reaction
		hits += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		var speed_bonus := maxi(0, 250 - int(round(reaction * 60.0)))
		score += 100 + speed_bonus + mini(streak, 10) * 10
		hit_flash = 0.08
		last_result = "HIT   %d ms" % int(round(reaction * 1000.0))
		_spawn_target()
	else:
		streak = 0
		score = maxi(0, score - 5)
		miss_flash = 0.08
		last_result = "MISS"

func _spawn_target() -> void:
	if definition == null:
		return
	var size := get_viewport_rect().size
	var margin := 90.0
	var horizontal := _azimuth_range()
	var vertical := _vertical_range()
	var centre := Vector2(size.x * 0.5, size.y * 0.5 + 20.0)
	var angle_x := rng.randf_range(horizontal.x, horizontal.y)
	var angle_y := rng.randf_range(vertical.x, vertical.y)
	var radius_factor := clampf(_target_size(), 0.35, 1.25)
	target_radius = clampf(34.0 * radius_factor, TARGET_RADIUS_MIN, TARGET_RADIUS_MAX)
	var span_x := maxf(80.0, size.x * 0.36)
	var span_y := maxf(70.0, size.y * 0.28)
	target_position = centre + Vector2(angle_x / 60.0 * span_x, angle_y / 20.0 * span_y)
	target_position.x = clampf(target_position.x, margin, size.x - margin)
	target_position.y = clampf(target_position.y, 120.0, size.y - margin)
	if target_position.distance_to(aim_point) < 120.0:
		target_position.x = clampf(target_position.x + signf(target_position.x - centre.x + 0.01) * 150.0, margin, size.x - margin)
	target_velocity = _movement_velocity()
	target_spawn_time = session_time
	target_alive = true
	target_count += 1

func _update_target(delta: float) -> void:
	if not target_alive:
		return
	if _is_moving_mode():
		target_position += target_velocity * delta
		var size := get_viewport_rect().size
		if target_position.x < 90.0 or target_position.x > size.x - 90.0:
			target_velocity.x *= -1.0
			target_position.x = clampf(target_position.x, 90.0, size.x - 90.0)
		if target_position.y < 120.0 or target_position.y > size.y - 90.0:
			target_velocity.y *= -1.0
			target_position.y = clampf(target_position.y, 120.0, size.y - 90.0)

func _register_expiry() -> void:
	if not target_alive:
		return
	target_alive = false
	streak = 0
	last_result = "EXPIRED"
	_spawn_target()

func _finish_session() -> void:
	if finished:
		return
	finished = true
	target_alive = false
	input_service.release_mouse()
	var accuracy := _accuracy()
	var avg_ms := (total_reaction / float(hits) * 1000.0) if hits > 0 else 0.0
	last_result = "SESSION COMPLETE"
	var summary := {
		"scenario_id": scenario_id,
		"scenario_name": definition.name if definition != null else scenario_id,
		"mode": definition.mode_id() if definition != null else "custom",
		"score": score,
		"stats": {
			"shots": shots,
			"hits": hits,
			"misses": maxi(0, shots - hits),
			"accuracy_percent": accuracy,
			"average_reaction_ms": avg_ms,
			"targets_eliminated": hits,
			"best_streak": best_streak,
			"duration_seconds": session_time,
		},
	}
	if App != null and App.boot_finished:
		App.record_session(summary)
	screen = Screen.RESULTS
	queue_redraw()

func _duration() -> float:
	return definition.duration_seconds if definition != null else 60.0

func _lifetime() -> float:
	if definition == null:
		return TARGET_LIFETIME_DEFAULT
	return definition.lifetime.min_seconds if definition.lifetime.min_seconds > 0.0 else TARGET_LIFETIME_DEFAULT

func _target_size() -> float:
	if definition == null or definition.target_groups.is_empty():
		return 1.0
	return definition.target_groups[0].size

func _azimuth_range() -> Vector2:
	if definition == null:
		return Vector2(-25.0, 25.0)
	var a := definition.spawn.azimuth_degrees
	return Vector2(a.x, a.y)

func _vertical_range() -> Vector2:
	if definition == null:
		return Vector2(-8.0, 8.0)
	var a := definition.spawn.elevation_degrees
	return Vector2(a.x, a.y)

func _movement_velocity() -> Vector2:
	if not _is_moving_mode():
		return Vector2.ZERO
	var speed := 110.0
	if definition != null:
		if definition.mode_id() == "reactive_tracking":
			speed = 190.0
		elif definition.mode_id() == "smooth_tracking":
			speed = 135.0
		elif definition.mode_id() == "movement_aim":
			speed = 155.0
	return Vector2.from_angle(rng.randf_range(0.0, TAU)) * speed

func _is_moving_mode() -> bool:
	if definition == null:
		return false
	return definition.mode_id() in ["dynamic_clicking", "smooth_tracking", "reactive_tracking", "movement_aim"]

func _accuracy() -> float:
	return float(hits) / float(shots) * 100.0 if shots > 0 else 0.0

func _mode_label() -> String:
	return definition.mode_label() if definition != null else "CUSTOM"

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#070a0e"))
	_draw_grid(size)
	if screen == Screen.MENU:
		_draw_menu(size)
	elif screen == Screen.RUN:
		_draw_run(size)
	else:
		_draw_results(size)

func _draw_grid(size: Vector2) -> void:
	for x in range(0, int(size.x), 80):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.08, 0.10, 0.13, 0.45), 1.0)
	for y in range(0, int(size.y), 80):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.08, 0.10, 0.13, 0.45), 1.0)

func _draw_menu(size: Vector2) -> void:
	_draw_text(Vector2(64, 74), "VANTA", 42, Color("#f1f4f6"))
	_draw_text(Vector2(66, 101), "TRAIN WHAT MATTERS.", 14, Color("#7d8995"))
	_draw_text(Vector2(66, 142), "SELECT A DRILL", 13, Color("#a9b4be"))

	for i in SCENARIO_ORDER.size():
		var id: String = SCENARIO_ORDER[i]
		var def: ScenarioDefinition = App.content.scenario(id) if App != null and App.content != null else null
		var y := 170.0 + float(i) * 48.0
		var selected_row := i == selected
		draw_rect(Rect2(56, y - 29, size.x * 0.56, 40), Color("#151c24") if selected_row else Color("#0d1218"), true)
		var number := str(i + 1)
		_draw_text(Vector2(72, y - 4), number, 12, Color("#ff4655") if selected_row else Color("#64717d"))
		_draw_text(Vector2(106, y - 4), def.name if def != null else id.to_upper(), 16, Color("#f0f4f7") if selected_row else Color("#a9b4be"))
		_draw_text(Vector2(390, y - 4), def.mode_label() if def != null else "CUSTOM", 11, Color("#778590"))
		_draw_text(Vector2(size.x * 0.58, y - 4), ("DIFF %d" % def.difficulty) if def != null else "", 11, Color("#778590"))

	draw_rect(Rect2(size.x * 0.66, 160, size.x * 0.29, 270), Color("#0d1218"), true)
	_draw_text(Vector2(size.x * 0.69, 198), _mode_label(), 21, Color("#f0f4f7"))
	_draw_text(Vector2(size.x * 0.69, 228), definition.description if definition != null else "Choose a scenario.", 13, Color("#8895a1"))
	_draw_text(Vector2(size.x * 0.69, 300), "OFFLINE", 12, Color("#78f2a4"))
	_draw_text(Vector2(size.x * 0.69, 325), "NO ACCOUNT", 12, Color("#78f2a4"))
	_draw_text(Vector2(size.x * 0.69, 350), "NO TELEMETRY", 12, Color("#78f2a4"))
	draw_rect(Rect2(size.x * 0.68, size.y - 125, 260, 58), Color("#dce6ed"), true)
	_draw_text(Vector2(size.x * 0.68 + 72, size.y - 90), "START DRILL  [ENTER]", 14, Color("#0a0d11"))
	_draw_text(Vector2(64, size.y - 30), "1–0 SELECT    ENTER START    ESC EXIT", 12, Color("#65727e"))

func _draw_run(size: Vector2) -> void:
	_draw_text(Vector2(28, 42), "VANTA", 22, Color("#f1f4f6"))
	_draw_text(Vector2(28, 67), _mode_label(), 12, Color("#7d8995"))
	_draw_text(Vector2(size.x - 28, 42), "SCORE %06d   ACC %.1f%%   STREAK %02d" % [score, _accuracy(), streak], 15, Color("#dce3e8"), true, size.x - 28)
	_draw_text(Vector2(size.x - 28, 67), "%02d:%02d" % [int(session_time) / 60, int(session_time) % 60], 12, Color("#7d8995"), true, size.x - 28)

	if target_alive and not paused:
		draw_circle(target_position, target_radius + 5, Color(0.04, 0.05, 0.07, 0.9))
		draw_circle(target_position, target_radius, Color("#dce6ed"))
		draw_circle(target_position, target_radius * 0.66, Color("#121820"))
		draw_circle(target_position, target_radius * 0.37, Color("#ff4655"))
		draw_circle(target_position, target_radius * 0.13, Color("#121820"))

	var cross_color := Color("#f1f4f6")
	if hit_flash > 0.0:
		cross_color = Color("#78f2a4")
	elif miss_flash > 0.0:
		cross_color = Color("#ff6675")
	_draw_crosshair(aim_point, cross_color)

	_draw_text(Vector2(28, size.y - 30), "LMB SHOOT    R RESTART    ESC PAUSE", 12, Color("#65727e"))
	_draw_text(Vector2(size.x - 28, size.y - 30), "%d / %d TARGETS" % [target_count, maxi(1, int(_duration() / maxf(0.1, _lifetime())))], 12, Color("#65727e"), true, size.x - 28)
	if paused:
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.0, 0.0, 0.0, 0.55))
		_draw_text(Vector2(0, size.y * 0.48), "PAUSED", 30, Color("#f1f4f6"), true, size.x)
		_draw_text(Vector2(0, size.y * 0.53), "ESC TO RESUME", 13, Color("#87949f"), true, size.x)
	else:
		_draw_text(Vector2(size.x * 0.5, size.y * 0.82), last_result, 14, Color("#8b98a3"), true, size.x * 0.5)

func _draw_results(size: Vector2) -> void:
	_draw_text(Vector2(0, 115), "SESSION COMPLETE", 32, Color("#f1f4f6"), true, size.x)
	_draw_text(Vector2(0, 148), definition.name if definition != null else scenario_id, 14, Color("#7d8995"), true, size.x)
	var avg := (total_reaction / float(hits) * 1000.0) if hits > 0 else 0.0
	_draw_text(Vector2(0, 230), "%06d" % score, 52, Color("#dce6ed"), true, size.x)
	_draw_text(Vector2(0, 260), "SCORE", 12, Color("#65727e"), true, size.x)
	_draw_metric(Vector2(size.x * 0.25, 350), "ACCURACY", "%.1f%%" % _accuracy())
	_draw_metric(Vector2(size.x * 0.5, 350), "AVG REACTION", "%.0f ms" % avg)
	_draw_metric(Vector2(size.x * 0.75, 350), "BEST STREAK", "%d" % best_streak)
	_draw_text(Vector2(0, 520), "%d hits / %d shots" % [hits, shots], 14, Color("#a8b3bd"), true, size.x)
	_draw_text(Vector2(0, 545), "Your run was saved locally.", 12, Color("#65727e"), true, size.x)
	draw_rect(Rect2(size.x * 0.5 - 150, size.y * 0.67, 300, 56), Color("#dce6ed"), true)
	_draw_text(Vector2(size.x * 0.5 - 100, size.y * 0.67 + 35), "RUN AGAIN  [R]", 14, Color("#090c10"))
	draw_rect(Rect2(size.x * 0.5 - 150, size.y * 0.67 + 70, 300, 48), Color("#151c24"), true)
	_draw_text(Vector2(size.x * 0.5 - 80, size.y * 0.67 + 100), "MAIN MENU  [M]", 13, Color("#dce6ed"))

func _draw_crosshair(pos: Vector2, color: Color) -> void:
	draw_line(pos + Vector2(-18, 0), pos + Vector2(-5, 0), color, 2)
	draw_line(pos + Vector2(5, 0), pos + Vector2(18, 0), color, 2)
	draw_line(pos + Vector2(0, -18), pos + Vector2(0, -5), color, 2)
	draw_line(pos + Vector2(0, 5), pos + Vector2(0, 18), color, 2)
	draw_circle(pos, 2, color)

func _draw_text(pos: Vector2, text: String, size_px: int, color: Color, right: bool = false, right_edge: float = 0.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var width := right_edge - pos.x if right and right_edge > pos.x else -1.0
	draw_string(ThemeDB.fallback_font, pos, text, align, width, size_px, color)

func _draw_metric(pos: Vector2, label: String, value: String) -> void:
	_draw_text(pos, value, 28, Color("#f1f4f6"), true, pos.x + 140)
	_draw_text(pos, label, 11, Color("#65727e"), true, pos.x + 140)
