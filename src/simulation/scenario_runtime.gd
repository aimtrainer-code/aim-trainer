class_name ScenarioRuntime
extends RefCounted

## Runs one attempt at one scenario.
##
## The runtime owns the rules and nothing else: no nodes, no rendering, no input
## polling. It is handed a `PlayerState` each frame and each shot, and it emits
## signals that the world, the HUD and the audio layer listen to. That separation is
## what makes the whole training loop testable headlessly, and it keeps menu code out
## of gameplay logic.
##
## Lifecycle
##   start()             → reset clock, stats, score, spawn director
##   prime(state)        → spawn the opening wave relative to a known eye position
##   step(delta, state)  → advance the fixed-step simulation, spawn/expire targets
##   try_fire(state)     → resolve a shot if the weapon and the rules allow it
##   finish(reason)      → stop, produce a summary (idempotent)
##
## Every randomness source is the scenario's `VantaRng`, so a fixed seed reproduces
## the run exactly. `tests/test_scenario_runtime.gd` verifies that claim rather than
## assuming it.

signal target_spawned(target: TargetInstance)
signal target_retired(target: TargetInstance, reason: String)
signal shot_resolved(shot: Dictionary)
signal score_changed(score: int)
signal finished(summary: Dictionary)
signal notice(text: String, kind: String)

## Hard ceiling on simultaneous targets. A malformed community scenario cannot ask
## the runtime to spawn an unbounded number of targets.
const MAX_ACTIVE_TARGETS: int = 64
## A target closer than this to the eye is not a training target, it is a bug.
const MIN_SPAWN_DISTANCE: float = 1.0

var definition: ScenarioDefinition = null
var arena: ArenaDefinition = null
var weapon_definition: WeaponDefinition = null
var weapon: WeaponRuntime = null
var clock: SimClock = null
var rng: VantaRng = null
var stats: ScenarioStats = null
var score_keeper: ScoreKeeper = null
var hit_registry: HitRegistry = null
var spawn_director: SpawnDirector = null

## Live targets. The world layer reads this list every frame to update transforms and
## nothing else iterates it, so there is exactly one owner of target lifetime.
var targets: Array[TargetInstance] = []
var seed: int = 0
var finished_flag: bool = false
var finish_reason: String = ""
var last_player_state: PlayerState = null

var _pool: Array[TargetInstance] = []
var _next_target_id: int = 1
var _next_spawn_at: float = 0.0
var _pending_respawn: int = 0
var _misses: int = 0
var _consecutive_misses: int = 0
var _engagements_resolved: int = 0
var _tracking_accumulator: float = 0.0
var _last_hit_headshot: bool = false


## The yaw/pitch the crosshair actually points along, including the weapon's current
## recoil displacement. `weapon.recoil` is (horizontal, vertical) in degrees, so the
## horizontal component moves yaw and the vertical component moves pitch.
##
## Every consumer of the player's aim — bullets, beam ticks and tracking samples — goes
## through this one function, so they cannot disagree about where the player was aiming.
func _aim_angles(player_state: PlayerState) -> Vector2:
	var yaw: float = player_state.yaw
	var pitch: float = player_state.pitch
	if weapon != null:
		yaw += weapon.recoil.x
		pitch += weapon.recoil.y
	return Vector2(yaw, clampf(pitch, -89.0, 89.0))


func _aim_direction(player_state: PlayerState) -> Vector3:
	var angles := _aim_angles(player_state)
	return MathX.direction_from_angles(angles.x, angles.y)


func start(scenario: ScenarioDefinition, arena_definition: ArenaDefinition, weapon_def: WeaponDefinition, run_seed: int) -> void:
	definition = scenario
	arena = arena_definition
	weapon_definition = weapon_def
	seed = run_seed
	rng = VantaRng.new(run_seed)
	clock = SimClock.new()
	stats = ScenarioStats.new()
	stats.reset()
	score_keeper = ScoreKeeper.new(scenario.scoring)
	hit_registry = HitRegistry.new()
	if arena != null:
		hit_registry.configure(ArenaBuilder.cover_boxes(arena))
	weapon = WeaponRuntime.new(weapon_def, rng)
	if scenario.ammo.infinite and weapon != null:
		# Infinite ammo is expressed as a magazine larger than any attempt could
		# consume rather than as a special case inside the weapon, so the weapon
		# still has one code path for ammunition.
		weapon.ammo = 1000000
	spawn_director = SpawnDirector.new()
	spawn_director.setup(scenario, arena, rng)
	targets.clear()
	_pool.clear()
	finished_flag = false
	finish_reason = ""
	_next_target_id = 1
	_next_spawn_at = 0.0
	_pending_respawn = 0
	_misses = 0
	_consecutive_misses = 0
	_engagements_resolved = 0
	_tracking_accumulator = 0.0
	_last_hit_headshot = false


## Spawns the opening wave. The world calls this once it knows where the player is,
## so the first target is placed relative to a real eye position.
func prime(player_state: PlayerState) -> void:
	last_player_state = player_state
	while active_count() < definition.simultaneous_targets and active_count() < MAX_ACTIVE_TARGETS:
		if not _spawn_one(player_state):
			break


func active_count() -> int:
	var count := 0
	for target in targets:
		if target.alive:
			count += 1
	return count


# --- simulation ------------------------------------------------------------

func step(delta: float, player_state: PlayerState) -> void:
	last_player_state = player_state
	if finished_flag:
		return
	stats.duration_seconds = clock.time
	var step_count := clock.advance(delta)
	var context := TargetMotion.Context.new()
	context.player_position = player_state.position
	context.player_forward = player_state.forward

	for _i in step_count:
		_simulate(SimClock.STEP_SECONDS, player_state, context)
		if finished_flag:
			break

	# Interpolated positions are what the renderer *and* the hit registry use, so the
	# two can never disagree about where a target was when the shot was taken.
	for target in targets:
		if target.motion != null:
			target.motion.update_interpolated(clock.alpha)

	if not finished_flag:
		var weapon_state := WeaponRuntime.State.new()
		weapon_state.moving_speed = player_state.speed
		weapon_state.airborne = player_state.airborne
		weapon_state.aiming = player_state.aiming
		weapon_state.stationary = player_state.speed <= definition.rules.stationary_threshold
		weapon.step(delta, weapon_state)
		_check_end_conditions(player_state)


func _simulate(step_seconds: float, player_state: PlayerState, context: TargetMotion.Context) -> void:
	var now := clock.time
	for target in targets:
		if not target.alive:
			continue
		if target.motion != null:
			context.age = target.age(now)
			context.fading_in = definition.lifetime.spawn_fade > 0.0 and context.age < definition.lifetime.spawn_fade
			target.motion.step(step_seconds, context)
		if target.has_expired(now):
			_expire(target, now)
	_spawn_pending(player_state, now)
	_sample_tracking(step_seconds, player_state)
	_apply_beam(step_seconds, player_state)


func _spawn_pending(player_state: PlayerState, now: float) -> void:
	if _pending_respawn > 0:
		_pending_respawn -= 1
		if _pending_respawn > 0:
			return
	if active_count() >= definition.simultaneous_targets or active_count() >= MAX_ACTIVE_TARGETS:
		return
	if stats.targets_spawned == 0:
		# A drill must never start with dead time: the first target is available on
		# the very first simulation step.
		_next_spawn_at = now
	if now < _next_spawn_at:
		return
	while active_count() < definition.simultaneous_targets and active_count() < MAX_ACTIVE_TARGETS:
		if not _spawn_one(player_state):
			break


func _spawn_one(player_state: PlayerState) -> bool:
	if spawn_director == null or definition.target_groups.is_empty():
		return false
	var plan := spawn_director.next_plan(player_state.position, player_state.forward, clock.time)
	if plan == null:
		return false
	if plan.position.distance_to(player_state.position) < MIN_SPAWN_DISTANCE:
		return false
	var group_index := clampi(plan.group_index, 0, definition.target_groups.size() - 1)
	var group: TargetGroup = definition.target_groups[group_index]
	var target := _obtain_target()
	target.setup(_next_target_id, group, plan.size_scale, plan.position, plan.basis, clock.time, plan.lifetime)
	target.group_index = group_index
	target.spawn_anchor = plan.anchor_id
	_next_target_id += 1

	var delta := plan.position - player_state.position
	var distance := maxf(delta.length(), 0.1)
	var azimuth_half := maxf(absf(definition.spawn.azimuth_degrees.x), absf(definition.spawn.azimuth_degrees.y))
	var elevation_half := maxf(absf(definition.spawn.elevation_degrees.x), absf(definition.spawn.elevation_degrees.y))
	var motion := TargetMotion.new()
	motion.setup(
		definition.motion,
		definition.reaction,
		rng,
		plan.position,
		player_state.forward,
		ArenaBuilder.corridor_half_width(distance, azimuth_half),
		ArenaBuilder.vertical_band(distance, elevation_half),
		plan.peek_axis
	)
	motion.interpolated = plan.position
	target.motion = motion
	targets.append(target)
	stats.register_spawn()
	target_spawned.emit(target)
	return true


func _obtain_target() -> TargetInstance:
	if not _pool.is_empty():
		return _pool.pop_back()
	return TargetInstance.new()


func _release(target: TargetInstance) -> void:
	targets.erase(target)
	target.motion = null
	if _pool.size() < MAX_ACTIVE_TARGETS:
		_pool.append(target)


func _expire(target: TargetInstance, now: float) -> void:
	target.retire("expired", now)
	stats.register_expiry()
	if definition.lifetime.counts_as_miss:
		_register_miss()
	var penalty := score_keeper.register_expiry()
	if penalty != 0:
		score_changed.emit(score_keeper.score)
	notice.emit("EXPIRED", "miss")
	_engagements_resolved += 1
	target_retired.emit(target, "expired")
	_release(target)
	_schedule_respawn(now)
	check_round_completion()


## A respawn replaces exactly one retired target after the scenario's respawn delay,
## so `simultaneous_targets` is maintained without ever exceeding it.
func _schedule_respawn(now: float) -> void:
	if active_count() >= definition.simultaneous_targets:
		return
	var delay: float = maxf(definition.lifetime.respawn_delay, 0.0)
	_pending_respawn = int(ceil(delay / SimClock.STEP_SECONDS))
	_next_spawn_at = maxf(_next_spawn_at, now + delay)


# --- shooting --------------------------------------------------------------

## Attempts to fire. Returns a dictionary describing the shot; `fired` is false and
## `reason` is set when the shot was refused.
##
## Recoil note: `weapon.recoil` is a displacement of the *view*, and this method
## applies it to the shot direction. The world layer must therefore drive the camera
## (and the reticle) from the same `weapon.recoil`, which is what keeps "shots go
## where the crosshair points" true even while the weapon climbs.
func try_fire(player_state: PlayerState) -> Dictionary:
	if finished_flag or weapon == null:
		return {"fired": false, "reason": "finished"}
	last_player_state = player_state
	var now := clock.time
	if not weapon.can_fire(now):
		return {"fired": false, "reason": weapon.blocked_reason()}
	var rule_check := _shot_allowed(player_state)
	if not rule_check["allowed"]:
		var reason := String(rule_check["reason"])
		stats.register_rejected_shot()
		notice.emit(reason, "warn")
		return {"fired": false, "reason": reason, "rejected": true}

	var weapon_state := WeaponRuntime.State.new()
	weapon_state.moving_speed = player_state.speed
	weapon_state.airborne = player_state.airborne
	weapon_state.aiming = player_state.aiming
	weapon_state.stationary = player_state.speed <= definition.rules.stationary_threshold
	var shot := weapon.fire(now, weapon_state)
	if shot.is_empty():
		return {"fired": false, "reason": "weapon_refused"}
	weapon.register_shot()
	stats.register_shot()

	var offsets: Array[Vector2] = shot["spread_offsets_deg"]
	var result := _resolve_pellets(player_state, offsets, now)
	result["shot"] = shot
	result["fired"] = true
	result["time"] = now
	shot_resolved.emit(result)
	return result


## Resolves every pellet of one trigger pull.
##
## The first pellet decides the shot's recorded outcome (hit, miss or cover), because
## one trigger pull is one shot in every statistic VANTA reports. Additional pellets
## can still deal damage, which is what makes a spread weapon's damage vary with
## range; they cannot award a second hit or a second kill.
func _resolve_pellets(player_state: PlayerState, offsets: Array[Vector2], now: float) -> Dictionary:
	var primary := _resolve_one(player_state, offsets[0], now)
	for index in range(1, offsets.size()):
		if finished_flag:
			break
		_resolve_one(player_state, offsets[index], now, true)
	return primary


func _resolve_one(player_state: PlayerState, offset: Vector2, now: float, secondary: bool = false) -> Dictionary:
	# The spread offset is angular, so it is added to the aim angles rather than to the
	# direction vector. `_aim_angles` already folds in the weapon's recoil.
	var angles := _aim_angles(player_state)
	var direction := MathX.direction_from_angles(angles.x + offset.x, clampf(angles.y + offset.y, -89.0, 89.0))
	var origin := player_state.position
	var resolution := hit_registry.resolve(origin, direction, targets)
	resolution["origin"] = origin
	resolution["direction"] = direction
	resolution["time"] = now

	match String(resolution["result"]):
		HitRegistry.HIT_TARGET:
			_apply_target_hit(resolution, secondary)
		HitRegistry.HIT_COVER:
			if not secondary:
				stats.register_miss(true, false)
				_register_miss()
				var cover_penalty := score_keeper.register_miss()
				resolution["outcome"] = "cover"
				if cover_penalty != 0:
					score_changed.emit(score_keeper.score)
			else:
				resolution["outcome"] = "cover"
		_:
			if not secondary:
				stats.register_miss(false, false)
				_register_miss()
				var miss_penalty := score_keeper.register_miss()
				resolution["outcome"] = "miss"
				if miss_penalty != 0:
					score_changed.emit(score_keeper.score)
			else:
				resolution["outcome"] = "miss"
	return resolution


func _apply_target_hit(resolution: Dictionary, secondary: bool) -> void:
	var target: TargetInstance = resolution["target"]
	var region: HitRegion = resolution["region"]
	if target == null or region == null:
		return
	var was_first_hit := target.first_hit_time < 0.0
	# The region carries the hitbox model's multiplier (a humanoid head is 3x). The
	# weapon's own head multiplier stacks on top of it and defaults to 1.0, so the
	# hitbox model stays the single source of truth for what a headshot is worth.
	var damage := weapon_definition.damage
	if region.is_headshot and weapon_definition.head_multiplier > 1.0:
		damage *= weapon_definition.head_multiplier
	if definition.rules.region_restricted and not region.is_headshot:
		# A drill can declare that only head hits count (a headshot matrix, for
		# example). Body hits are then misses that happen to land on the target:
		# they are recorded as absorbed shots so the player can see that the aim was
		# on the body rather than off the target entirely.
		stats.register_restricted_hit()
		_register_miss()
		score_keeper.register_miss()
		resolution["outcome"] = "restricted"
		notice.emit("BODY SHOT", "warn")
		return
	var outcome := target.apply_hit(region, damage, clock.time)
	if not outcome["accepted"]:
		# A hit on an inert region (a body hit in a head-only drill) is neither a hit
		# nor a miss: it is absorbed, and it must not award points or count against a
		# miss limit.
		stats.register_miss(false, true)
		resolution["outcome"] = "absorbed"
		return
	resolution["outcome"] = "hit"
	resolution["region_id"] = region.id
	resolution["is_headshot"] = region.is_headshot
	resolution["damage"] = outcome["damage"]
	if secondary:
		# Secondary pellets deal damage but do not enter the statistics; the primary
		# pellet already recorded this trigger pull.
		resolution["secondary"] = true
		if outcome["lethal"] and target.alive:
			_eliminate(target, region.is_headshot)
		return

	_last_hit_headshot = region.is_headshot
	stats.register_hit(target.time_to_first_hit() if was_first_hit else -1.0, region.is_headshot)
	var points := score_keeper.register_hit(region.is_headshot)
	resolution["points"] = points
	if points != 0:
		score_changed.emit(score_keeper.score)

	if outcome["lethal"] or definition.lifetime.die_on_first_hit:
		_eliminate(target, region.is_headshot)
	elif definition.lifetime.grace_after_hit > 0.0:
		# A damaged target survives long enough for the follow-up shot, unless the
		# scenario deliberately trains its disappearance.
		target.grace_until = clock.time + definition.lifetime.grace_after_hit


func _eliminate(target: TargetInstance, is_headshot: bool) -> void:
	var ttk := clock.time - target.spawn_time
	target.retire("eliminated", clock.time)
	stats.register_elimination(ttk)
	var points := score_keeper.register_elimination(ttk, is_headshot)
	if points != 0:
		score_changed.emit(score_keeper.score)
	_engagements_resolved += 1
	notice.emit("HEADSHOT" if is_headshot else "ELIMINATED", "headshot" if is_headshot else "kill")
	target_retired.emit(target, "eliminated")
	_release(target)
	_schedule_respawn(clock.time)
	check_round_completion()


func _shot_allowed(player_state: PlayerState) -> Dictionary:
	var rules := definition.rules
	if rules.min_shot_interval > 0.0 and clock.time - weapon.last_shot_time < rules.min_shot_interval:
		return {"allowed": false, "reason": "MIN SHOT INTERVAL"}
	if rules.require_stationary and player_state.speed > rules.stationary_threshold:
		return {"allowed": false, "reason": "STOP MOVING TO SHOOT"}
	if rules.forbid_airborne_shots and player_state.airborne:
		return {"allowed": false, "reason": "NO SHOTS IN THE AIR"}
	if rules.require_ads and not player_state.aiming:
		return {"allowed": false, "reason": "AIM DOWN SIGHTS FIRST"}
	return {"allowed": true, "reason": ""}


# --- tracking and beams ----------------------------------------------------

func _sample_tracking(step_seconds: float, player_state: PlayerState) -> void:
	if definition.scoring.tracking_points_per_second <= 0 and definition.scoring.tracking_off_target_penalty_per_second <= 0:
		return
	var resolution := hit_registry.resolve(player_state.position, _aim_direction(player_state), targets)
	var on_target := String(resolution["result"]) == HitRegistry.HIT_TARGET
	stats.register_tracking_sample(on_target, step_seconds)
	score_keeper.register_tracking(step_seconds, on_target)


## Beam weapons deal damage over time while the trigger is held. Damage arrives in
## fixed ticks rather than every simulation step: the tick is what the HUD shows, and
## it keeps the elimination time reproducible instead of frame-rate dependent.
func _apply_beam(step_seconds: float, player_state: PlayerState) -> void:
	if weapon_definition == null or not weapon_definition.beam or not player_state.firing:
		return
	var resolution := hit_registry.resolve(player_state.position, _aim_direction(player_state), targets)
	if String(resolution["result"]) != HitRegistry.HIT_TARGET:
		_tracking_accumulator = 0.0
		return
	var target: TargetInstance = resolution["target"]
	var region: HitRegion = resolution["region"]
	if target == null or region == null:
		return
	_tracking_accumulator += step_seconds
	var tick_seconds: float = maxf(weapon_definition.beam_tick_seconds, SimClock.STEP_SECONDS)
	if _tracking_accumulator < tick_seconds:
		return
	var tick := _tracking_accumulator
	_tracking_accumulator = 0.0
	var outcome := target.apply_hit(region, weapon_definition.beam_damage_per_second * tick, clock.time)
	if not outcome["accepted"]:
		return
	if outcome["lethal"]:
		_eliminate(target, region.is_headshot)


# --- lifecycle -------------------------------------------------------------

func _register_miss() -> void:
	_misses += 1
	_consecutive_misses += 1


func reload() -> bool:
	if weapon == null:
		return false
	var started := weapon.start_reload()
	if started:
		notice.emit("RELOADING", "info")
	return started


func check_round_completion() -> void:
	if finished_flag:
		return
	if definition.rounds > 0 and _engagements_resolved >= definition.rounds:
		finish("rounds_complete")


func _check_end_conditions(player_state: PlayerState) -> void:
	if finished_flag:
		return
	var rules := definition.rules
	if rules.max_misses > 0 and _misses >= rules.max_misses:
		finish("max_misses")
		return
	if rules.max_consecutive_misses > 0 and _consecutive_misses >= rules.max_consecutive_misses:
		finish("misses_in_a_row")
		return
	if definition.ammo.empty_ends_round and weapon != null and weapon.is_magazine_empty() and not weapon.reloading:
		finish("out_of_ammo")
		return
	if definition.ammo.auto_reload and weapon != null and weapon.is_magazine_empty() and not weapon.reloading and not definition.ammo.infinite:
		weapon.start_reload()
	if definition.duration_seconds > 0.0 and clock.time >= definition.duration_seconds:
		finish("duration")
		return
	if player_state != null and rules.stay_in_bounds and arena != null:
		var inside := absf(player_state.position.x) < arena.half_width and absf(player_state.position.z) < arena.depth
		if not inside:
			finish("left_arena")


## Ends the attempt. Idempotent: repeated calls after the first do nothing, so a late
## frame cannot emit two summaries.
func finish(reason: String) -> Dictionary:
	if finished_flag:
		return {}
	finished_flag = true
	finish_reason = reason
	stats.duration_seconds = clock.time
	score_keeper.apply_accuracy_bonus(stats.accuracy_percent())
	var summary := build_summary()
	finished.emit(summary)
	return summary


func abort() -> Dictionary:
	if finished_flag or clock == null:
		return {}
	return finish("aborted")


# --- results ---------------------------------------------------------------

func build_summary() -> Dictionary:
	var stats_summary := stats.summary()
	return {
		"scenario_id": definition.id if definition != null else "",
		"scenario_name": definition.name if definition != null else "",
		"mode": definition.mode_id() if definition != null else "",
		"mode_label": definition.mode_label() if definition != null else "",
		"skill": definition.skill if definition != null else "",
		"transfer_stage": definition.transfer_id() if definition != null else "",
		"weapon_id": weapon_definition.id if weapon_definition != null else "",
		"arena_id": arena.id if arena != null else "",
		"seed": seed,
		"score": score_keeper.score,
		"score_breakdown": score_keeper.breakdown,
		"finish_reason": finish_reason,
		"stats": stats_summary,
		"success": evaluate_success(stats_summary),
		"sim": clock.snapshot() if clock != null else {},
	}


## Success is evaluated against `SuccessSpec` only. A scenario with no requirements
## returns `practice_only: true`, which the UI reports as a practice run rather than
## as a failure — a drill with no target to hit has not been failed.
func evaluate_success(stats_summary: Dictionary) -> Dictionary:
	var spec := definition.success
	var failures: Array[String] = []
	if not spec.any_requirement():
		return {"met": false, "practice_only": true, "failures": failures}
	if spec.min_accuracy > 0.0 and float(stats_summary["accuracy_percent"]) < spec.min_accuracy:
		failures.append("accuracy %.1f%% below %.1f%%" % [stats_summary["accuracy_percent"], spec.min_accuracy])
	if spec.min_score > 0 and score_keeper.score < spec.min_score:
		failures.append("score %d below %d" % [score_keeper.score, spec.min_score])
	if spec.max_average_time_to_kill > 0.0 and float(stats_summary["average_time_to_kill"]) > spec.max_average_time_to_kill:
		failures.append("average time to kill %.2fs above %.2fs" % [stats_summary["average_time_to_kill"], spec.max_average_time_to_kill])
	if spec.min_headshot_ratio > 0.0 and float(stats_summary["headshot_ratio_percent"]) < spec.min_headshot_ratio:
		failures.append("headshot ratio %.1f%% below %.1f%%" % [stats_summary["headshot_ratio_percent"], spec.min_headshot_ratio])
	if spec.min_targets > 0 and int(stats_summary["targets_eliminated"]) < spec.min_targets:
		failures.append("%d targets below %d" % [stats_summary["targets_eliminated"], spec.min_targets])
	if spec.max_misses > 0 and _misses > spec.max_misses:
		# `_misses` is the scenario's own failure counter: shots that missed, plus
		# expiries the scenario asked to count (`lifetime.counts_as_miss`). Accuracy
		# uses `stats.misses`, which is shots only, because an expiry is not a shot.
		failures.append("%d misses above the limit of %d" % [_misses, spec.max_misses])
	if spec.min_consistency > 0.0 and float(stats_summary["consistency_percent"]) < spec.min_consistency:
		failures.append("consistency %.0f%% below %.0f%%" % [stats_summary["consistency_percent"], spec.min_consistency])
	return {"met": failures.is_empty(), "practice_only": false, "failures": failures}


# --- interface for the world layer -----------------------------------------

func progress_fraction() -> float:
	if definition == null:
		return 0.0
	if definition.rounds > 0:
		return clampf(float(_engagements_resolved) / float(definition.rounds), 0.0, 1.0)
	if definition.duration_seconds > 0.0:
		return clampf(clock.time / definition.duration_seconds, 0.0, 1.0)
	return 0.0


func remaining_seconds() -> float:
	if definition == null or definition.duration_seconds <= 0.0:
		return 0.0
	return maxf(0.0, definition.duration_seconds - clock.time)


func engagements_resolved() -> int:
	return _engagements_resolved


## Failed engagements under the scenario's own definition: shots that missed plus
## expiries the scenario asked to count. This is the number the fail conditions use;
## `stats.misses` is deliberately narrower (shots only), because accuracy must not be
## changed by a target the player never shot at.
func engagement_failures() -> int:
	return _misses


## The recoil displacement the camera must apply so the reticle and the bullet agree.
func view_recoil_degrees() -> Vector2:
	if weapon == null:
		return Vector2.ZERO
	return weapon.recoil


func current_spread_degrees() -> float:
	if weapon == null:
		return 0.0
	var state := WeaponRuntime.State.new()
	if last_player_state != null:
		state.moving_speed = last_player_state.speed
		state.airborne = last_player_state.airborne
		state.aiming = last_player_state.aiming
	return weapon.current_spread(state)


## Compact snapshot for the HUD and for automated tests. Deliberately small: a HUD
## that reads twenty fields per frame is a HUD that will disagree with the sim.
func snapshot() -> Dictionary:
	var target_rows: Array[Dictionary] = []
	for target in targets:
		if not target.alive:
			continue
		var position := target.world_position()
		target_rows.append({
			"id": target.id,
			"group": target.group.type_id() if target.group != null else "?",
			"position": [position.x, position.y, position.z],
			"hp": target.hp,
			"max_hp": target.max_hp,
			"age": target.age(clock.time),
			"lifetime": target.lifetime,
		})
	return {
		"time": clock.time if clock != null else 0.0,
		"score": score_keeper.score if score_keeper != null else 0,
		"ammo": weapon.ammo if weapon != null else 0,
		"magazine": weapon_definition.magazine if weapon_definition != null else 0,
		"reloading": weapon.reloading if weapon != null else false,
		"spread_deg": current_spread_degrees(),
		"recoil": [view_recoil_degrees().x, view_recoil_degrees().y],
		"active_targets": active_count(),
		"progress": progress_fraction(),
		"remaining": remaining_seconds(),
		"stats": stats.summary() if stats != null else {},
		"targets": target_rows,
	}
