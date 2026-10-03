extends VantaTestCase

## Scenario runtime tests.
##
## These are the tests that decide whether a drill is *mechanically correct*: shots
## land where the crosshair points, hits register once, expired targets are misses,
## head-only drills treat body hits as misses, walls stop bullets, a run ends exactly
## once, and the same seed reproduces the same run on any machine.

const STEP: float = 1.0 / 120.0

var library: VantaContentLibrary = null


func before_all() -> void:
	library = VantaContentLibrary.new()
	library.load_all()


func test_determinism_same_seed_same_run() -> void:
	var first := _run("micro_flick_60", 12.0, true, 4242)
	var second := _run("micro_flick_60", 12.0, true, 4242)
	assert_eq(first["score"], second["score"], "the same seed produces the same score")
	var stats_a: Dictionary = first["stats"]
	var stats_b: Dictionary = second["stats"]
	assert_eq(stats_a["shots"], stats_b["shots"], "the same seed produces the same number of shots")
	assert_eq(stats_a["hits"], stats_b["hits"], "the same seed produces the same number of hits")
	assert_eq(stats_a["misses"], stats_b["misses"], "the same seed produces the same number of misses")
	assert_eq(stats_a["targets_spawned"], stats_b["targets_spawned"], "the same seed produces the same spawns")
	assert_eq(stats_a["targets_eliminated"], stats_b["targets_eliminated"], "the same seed eliminates the same targets")
	assert_almost_eq(float(stats_a["accuracy_percent"]), float(stats_b["accuracy_percent"]), "the same seed produces the same accuracy", 0.0001)
	assert_almost_eq(float(stats_a["average_time_to_kill"]), float(stats_b["average_time_to_kill"]), "the same seed produces the same average time to kill", 0.0001)
	assert_eq(int(stats_a["longest_streak"]), int(stats_b["longest_streak"]), "the same seed produces the same streak")


func test_different_seeds_produce_different_runs() -> void:
	var first := _run("wide_flick_60", 12.0, true, 1)
	var second := _run("wide_flick_60", 12.0, true, 999)
	var stats_a: Dictionary = first["stats"]
	var stats_b: Dictionary = second["stats"]
	assert_not_eq(int(stats_a["targets_spawned"]), int(stats_b["targets_spawned"]), "a different seed produces a different spawn sequence")


func test_shots_land_and_score() -> void:
	var summary := _run("static_precision_60", 20.0, true, 31)
	var stats: Dictionary = summary["stats"]
	assert_greater(float(stats["shots"]), 5.0, "the scripted player fired shots")
	assert_greater(float(stats["hits"]), 0.0, "shots that are aimed at a target hit it")
	assert_greater(float(stats["targets_eliminated"]), 0.0, "targets are eliminated")
	assert_greater(float(summary["score"]), 0.0, "eliminations award score")
	assert_between(float(stats["accuracy_percent"]), 1.0, 100.0, "accuracy is a percentage")
	assert_eq(String(summary["finish_reason"]), "test_end", "the run reports why it ended")


func test_first_shot_of_a_fresh_weapon_hits_where_it_is_aimed() -> void:
	# The single most important property of the whole simulation: with the crosshair on
	# the target's centre and a settled weapon, the shot must register as a hit.
	var runtime := _runtime_for("static_precision_60", 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var target := _nearest(runtime, player)
	assert_not_null(target, "a target spawned")
	_aim_at(player, target)
	var result := runtime.try_fire(player)
	assert_true(bool(result["fired"]), "the shot was fired: %s" % str(result.get("reason", "")))
	assert_eq(String(result["result"]), HitRegistry.HIT_TARGET, "a settled first shot aimed at the centre is a hit")
	assert_eq(String(result["region_id"]), HitRegion.BODY, "the sphere target has a single body region")


func test_cover_stops_shots() -> void:
	var runtime := _runtime_for("static_precision_60", 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	# Turn around and shoot the wall behind the player.
	player.yaw += 180.0
	player.pitch = 0.0
	player.forward = MathX.direction_from_angles(player.yaw, player.pitch)
	var result := runtime.try_fire(player)
	assert_true(bool(result["fired"]), "the shot was fired")
	assert_eq(String(result["result"]), HitRegistry.HIT_COVER, "the wall stops the shot")
	assert_eq(String(result["outcome"]), "cover", "the shot is recorded as blocked by cover")
	var stats: Dictionary = runtime.stats.summary()
	assert_eq(int(stats["blocked_by_cover"]), 1, "the cover hit is counted")
	assert_eq(int(stats["misses"]), 1, "a shot into a wall is a miss")


func test_region_restricted_head_only_drill_counts_body_hits_as_misses() -> void:
	var runtime := _runtime_for("headshot_matrix_60", 11)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var target := _nearest(runtime, player)
	assert_not_null(target, "a humanoid target spawned")
	# Body shot first: the scenario declares that only head hits count.
	assert_true(_aim_at_region(player, target, HitRegion.TORSO), "the humanoid has a torso region")
	var body := runtime.try_fire(player)
	assert_eq(String(body["outcome"]), "restricted", "a body hit is a restricted hit, not damage")
	var stats_after_body: Dictionary = runtime.stats.summary()
	assert_eq(int(stats_after_body["misses"]), 1, "the body hit counts as a miss")
	assert_eq(int(stats_after_body["absorbed_hits"]), 1, "the body hit is also recorded as an absorbed hit")
	assert_true(int(runtime.score_keeper.score) <= 0, "a restricted hit awards no points (score %d)" % runtime.score_keeper.score)
	assert_eq(int(runtime.score_keeper.breakdown.get("hit", 0)), 0, "no hit points were awarded")
	# Head shot: the same target, aimed at the head instead.
	runtime.weapon.last_shot_time = -1000.0
	assert_true(_aim_at_region(player, target, HitRegion.HEAD, runtime.view_recoil_degrees()), "the humanoid has a head region")
	var head := runtime.try_fire(player)
	assert_eq(String(head["outcome"]), "hit", "a head hit is accepted")
	assert_true(bool(head["is_headshot"]), "the head hit is flagged as a headshot")
	assert_greater(float(head["points"]), 0.0, "the head hit awards points")


func test_expiry_counts_as_a_miss_and_targets_respawn() -> void:
	var definition := _synthetic_scenario({
		"lifetime": {"seconds": [0.3, 0.3], "counts_as_miss": true, "die_on_first_hit": true},
		"duration_seconds": 5.0,
	})
	var runtime := _runtime_for_definition(definition, 3)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var elapsed := 0.0
	while elapsed < 2.5:
		runtime.step(STEP, player)
		elapsed += STEP
	var stats := runtime.stats.summary()
	assert_greater(float(stats["targets_expired"]), 0.0, "targets expired")
	assert_greater(float(stats["targets_spawned"]), float(stats["targets_expired"]), "expired targets are replaced")
	# Accuracy counts *shots*, so an expiry must not move it: the player never fired. It is
	# still an engagement failure for the scenario's own fail conditions, which is exactly
	# what `lifetime.counts_as_miss` controls.
	assert_eq(int(stats["misses"]), 0, "an expiry is not a shot, so it is not an accuracy miss")
	assert_greater(float(runtime.engagement_failures()), 0.0, "the expiry is an engagement failure")


func test_expiry_does_not_count_as_a_miss_when_the_scenario_says_so() -> void:
	var definition := _synthetic_scenario({
		"lifetime": {"seconds": [0.3, 0.3], "counts_as_miss": false, "die_on_first_hit": true},
		"duration_seconds": 5.0,
	})
	var runtime := _runtime_for_definition(definition, 3)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var elapsed := 0.0
	while elapsed < 1.5:
		runtime.step(STEP, player)
		elapsed += STEP
	assert_greater(float(runtime.stats.summary()["targets_expired"]), 0.0, "targets expired")
	assert_eq(int(runtime.stats.summary()["misses"]), 0, "expiry was not counted as a miss")


func test_a_run_ends_exactly_once() -> void:
	var runtime := _runtime_for("static_precision_60", 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var finishes := [0]
	runtime.finished.connect(func(_summary: Dictionary) -> void: finishes[0] += 1)
	var elapsed := 0.0
	while elapsed < 61.0 and not runtime.finished_flag:
		runtime.step(STEP, player)
		elapsed += STEP
	assert_true(runtime.finished_flag, "the run ended when the duration elapsed")
	assert_eq(String(runtime.finish_reason), "duration", "the run ended because the timer ran out")
	assert_eq(finishes[0], 1, "the finished signal was emitted once")
	var second := runtime.finish("again")
	assert_true(second.is_empty(), "a second finish call is ignored")
	assert_eq(finishes[0], 1, "the finished signal was still emitted only once")
	var frozen := runtime.clock.time
	runtime.step(STEP, player)
	assert_almost_eq(runtime.clock.time, frozen, "stepping after the end does not advance the clock", 0.0001)


func test_max_misses_ends_the_run() -> void:
	var definition := _synthetic_scenario({
		"rules": {"max_misses": 3, "lock_player_position": true},
		"duration_seconds": 60.0,
	})
	var runtime := _runtime_for_definition(definition, 8)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	# Fire at the ceiling: three misses end the run.
	player.pitch = 70.0
	player.forward = MathX.direction_from_angles(player.yaw, player.pitch)
	var guard := 0
	while not runtime.finished_flag and guard < 4000:
		runtime.step(STEP, player)
		if runtime.weapon.can_fire(runtime.clock.time):
			runtime.try_fire(player)
		guard += 1
	assert_true(runtime.finished_flag, "the run ended")
	assert_eq(String(runtime.finish_reason), "max_misses", "it ended on the miss limit")


func test_stationary_rule_refuses_shots_while_moving() -> void:
	var runtime := _runtime_for("movement_aim_60", 6)
	var player := _player_at_start(runtime)
	player.speed = 4.0
	runtime.prime(player)
	var blocked := runtime.try_fire(player)
	assert_false(bool(blocked["fired"]), "a shot while moving is refused")
	assert_eq(String(blocked["reason"]), "STOP MOVING TO SHOOT", "the refusal explains why")
	assert_eq(int(runtime.stats.summary()["rejected_shots"]), 1, "the refused shot is recorded")
	player.speed = 0.0
	runtime.weapon.last_shot_time = -1000.0
	var allowed := runtime.try_fire(player)
	assert_true(bool(allowed["fired"]), "the same shot standing still is accepted")


func test_success_requires_the_scenario_requirements() -> void:
	var runtime := _runtime_for("static_precision_60", 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	# No shots fired at all: accuracy is undefined and the minimum is not met.
	var summary := runtime.build_summary()
	var success: Dictionary = summary["success"]
	assert_false(bool(success["met"]), "an untouched drill does not count as passed")
	assert_false(bool(success["practice_only"]), "a drill with requirements is not practice-only")
	assert_greater(float((success["failures"] as Array).size()), 0.0, "the failure is explained")


func test_scenarios_without_requirements_are_practice_only() -> void:
	var definition := _synthetic_scenario({"success": {}})
	var runtime := _runtime_for_definition(definition, 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var success: Dictionary = runtime.build_summary()["success"]
	assert_true(bool(success["practice_only"]), "a drill with no requirements is practice, not a test")
	assert_false(bool(success["met"]), "a practice-only drill has not been passed")


func test_beam_weapon_damages_continuously() -> void:
	var runtime := _runtime_for("smooth_tracking_30", 17)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var target := _nearest(runtime, player)
	assert_not_null(target, "a tracking target spawned")
	var starting_hp: float = target.hp
	player.firing = true
	var elapsed := 0.0
	while elapsed < 1.0:
		_aim_at(player, target, runtime.view_recoil_degrees())
		runtime.step(STEP, player)
		elapsed += STEP
	assert_less(target.hp, starting_hp, "holding the beam on the target removed health (%.1f -> %.1f)" % [starting_hp, target.hp])
	assert_greater(float(runtime.stats.summary()["tracking_on_target_seconds"]), 0.0, "time on target was recorded")


func test_spread_grows_with_sustained_fire() -> void:
	var runtime := _runtime_for("static_precision_60", 5)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var target := _nearest(runtime, player)
	var settled := runtime.current_spread_degrees()
	var elapsed := 0.0
	while elapsed < 1.0:
		_aim_at(player, target, runtime.view_recoil_degrees())
		runtime.step(STEP, player)
		if runtime.weapon.can_fire(runtime.clock.time):
			runtime.try_fire(player)
		elapsed += STEP
	assert_greater(runtime.current_spread_degrees(), settled, "the cone of fire grew while firing")


# --- helpers ---------------------------------------------------------------

func _run(scenario_id: String, seconds: float, shoot: bool, seed_value: int) -> Dictionary:
	var runtime := _runtime_for(scenario_id, seed_value)
	var player := _player_at_start(runtime)
	runtime.prime(player)
	var elapsed := 0.0
	while elapsed < seconds and not runtime.finished_flag:
		var target := _nearest(runtime, player)
		if target != null:
			_aim_at(player, target, runtime.view_recoil_degrees())
		runtime.step(STEP, player)
		if shoot and not runtime.finished_flag and runtime.weapon.can_fire(runtime.clock.time):
			runtime.try_fire(player)
		elapsed += STEP
	return runtime.finish("test_end")


func _runtime_for(scenario_id: String, seed_value: int) -> ScenarioRuntime:
	var definition := library.scenario(scenario_id)
	assert_not_null(definition, "scenario '%s' exists" % scenario_id)
	return _runtime_for_definition(definition, seed_value)


func _runtime_for_definition(definition: ScenarioDefinition, seed_value: int) -> ScenarioRuntime:
	var runtime := ScenarioRuntime.new()
	runtime.start(definition, library.arena(definition.arena_id), library.weapon(definition.weapon_id), seed_value)
	return runtime


## A player standing at the arena's start, looking into the arena.
func _player_at_start(runtime: ScenarioRuntime) -> PlayerState:
	var position: Vector3 = runtime.arena.player_start
	var yaw := 180.0
	var to_centre := Vector3.ZERO - position
	if Vector2(to_centre.x, to_centre.z).length_squared() > 0.01:
		yaw = MathX.angles_from_direction(to_centre.normalized()).x
	return PlayerState.make(position, yaw, 0.0)


## A scripted player that aims at a target: used instead of a mouse so the tests are
## deterministic and check the *simulation*, not the input layer. `recoil` is the
## weapon's current view displacement, subtracted so the scripted player compensates
## for it the way a human looking through the reticle would.
func _aim_at(player: PlayerState, target: TargetInstance, recoil: Vector2 = Vector2.ZERO) -> void:
	_aim_at_point(player, target, TargetShape.local_center(target.group, target.size_scale), recoil)


func _aim_at_region(player: PlayerState, target: TargetInstance, region_id: String, recoil: Vector2 = Vector2.ZERO) -> bool:
	for region in target.regions:
		if region.id == region_id:
			_aim_at_point(player, target, _region_center_local(region), recoil)
			return true
	return false


func _region_center_local(region: HitRegion) -> Vector3:
	if region.kind == HitRegion.Kind.CAPSULE:
		return (region.capsule_a + region.capsule_b) * 0.5
	return region.center


func _aim_at_point(player: PlayerState, target: TargetInstance, local_offset: Vector3, recoil: Vector2 = Vector2.ZERO) -> void:
	var point := target.world_position() + target.basis * local_offset
	var delta := point - player.position
	if delta.length_squared() < 0.000001:
		return
	var angles := MathX.angles_from_direction(delta.normalized())
	player.yaw = angles.x - recoil.x
	player.pitch = clampf(angles.y - recoil.y, -89.0, 89.0)
	player.forward = MathX.direction_from_angles(player.yaw, player.pitch)


func _nearest(runtime: ScenarioRuntime, player: PlayerState) -> TargetInstance:
	var best: TargetInstance = null
	var best_distance := INF
	for target in runtime.targets:
		if not target.alive:
			continue
		var distance := target.world_position().distance_to(player.position)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


## A minimal valid scenario, so a test can vary one section without repeating the
## whole schema. Uses shipped content for its arena and weapon.
func _synthetic_scenario(overrides: Dictionary) -> ScenarioDefinition:
	var data := {
		"schema_version": 1,
		"id": "synthetic_test",
		"name": "SYNTHETIC TEST",
		"mode": "static_precision",
		"arena": "dojo_open",
		"weapon": "tactical_rifle",
		"training": {"skill": "aim_control.precision", "transfer_stage": "isolation", "difficulty": 1},
		"targets": [{"type": "sphere", "size": 0.45, "hp": 1.0, "weight": 1.0}],
		"simultaneous_targets": 1,
		"spawn": {"region": "sphere_cap", "azimuth_degrees": [-20.0, 20.0], "distance_min": 8.0, "distance_max": 12.0},
		"lifetime": {"seconds": [2.0, 2.0], "counts_as_miss": true, "die_on_first_hit": true},
		"motion": {"model": "stationary"},
		"ammo": {"infinite": true},
		"rules": {"lock_player_position": true},
		"scoring": {"kill_points": 100, "time_bonus_base": 200, "time_bonus_rate": 40},
		"duration_seconds": 30.0,
	}
	for key in overrides.keys():
		data[key] = overrides[key]
	var parsed := ScenarioDefinition.from_dict(data)
	var definition: ScenarioDefinition = parsed["definition"]
	assert_eq((parsed["errors"] as Array).size(), 0, "the synthetic scenario is valid: %s" % str(parsed["errors"]))
	return definition
