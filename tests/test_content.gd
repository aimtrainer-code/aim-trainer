extends VantaTestCase

## Content library tests.
##
## The shipped content is not decoration: it is the tutorial, the benchmark set and
## the reference an author copies from. These tests therefore check that it loads, that
## the geometry described by the peek arena actually occludes what it claims to
## occlude, and that untrusted user content cannot take its place.

const USER_SCENARIO_DIR: String = "user://content/scenarios"

var library: VantaContentLibrary = null


func before_all() -> void:
	library = VantaContentLibrary.new()
	library.load_all()


func after_all() -> void:
	_remove_user_content()


func test_library_loads_without_errors() -> void:
	assert_eq(library.errors.size(), 0, "shipped content must load without errors: %s" % str(library.errors))
	assert_true(library.weapons.size() >= 5, "at least five weapons ship with the game (got %d)" % library.weapons.size())
	assert_true(library.arenas.size() >= 3, "at least three arenas ship with the game (got %d)" % library.arenas.size())
	assert_true(library.scenarios.size() >= 10, "at least ten scenarios ship with the game (got %d)" % library.scenarios.size())


func test_every_scenario_resolves_its_references() -> void:
	assert_false(library.scenarios.is_empty(), "scenarios were loaded")
	for id in library.scenario_ids():
		var definition := library.scenario(id)
		assert_not_null(definition, "scenario '%s' resolves" % id)
		assert_not_null(library.arena(definition.arena_id), "scenario '%s' names a real arena" % id)
		assert_not_null(library.weapon(definition.weapon_id), "scenario '%s' names a real weapon" % id)
		assert_true(definition.is_valid(), "scenario '%s' is valid" % id)


func test_every_id_is_a_safe_id() -> void:
	for id in library.weapons.keys():
		assert_true(VantaContentLibrary.is_safe_id(String(id)), "weapon id '%s' is safe" % id)
	for id in library.arenas.keys():
		assert_true(VantaContentLibrary.is_safe_id(String(id)), "arena id '%s' is safe" % id)
	for id in library.scenarios.keys():
		assert_true(VantaContentLibrary.is_safe_id(String(id)), "scenario id '%s' is safe" % id)


func test_safe_id_rejects_hostile_input() -> void:
	assert_true(VantaContentLibrary.is_safe_id("micro_flick_60"), "a normal id is accepted")
	assert_false(VantaContentLibrary.is_safe_id(""), "an empty id is rejected")
	assert_false(VantaContentLibrary.is_safe_id("Upper_Case"), "uppercase is rejected")
	assert_false(VantaContentLibrary.is_safe_id("has space"), "whitespace is rejected")
	assert_false(VantaContentLibrary.is_safe_id("../../etc/passwd"), "path traversal is rejected")
	assert_false(VantaContentLibrary.is_safe_id("id.json"), "a file extension is rejected")
	assert_false(VantaContentLibrary.is_safe_id("semi;colon"), "punctuation is rejected")
	assert_false(VantaContentLibrary.is_safe_id("a".repeat(65)), "an over-long id is rejected")
	assert_false(VantaContentLibrary.is_safe_id("new\nline"), "a newline is rejected")


func test_weapon_validation_rejects_nonsense() -> void:
	var unknown := WeaponDefinition.from_dict({"id": "x", "archetype": "railgun"})
	assert_true((unknown["errors"] as Array).size() > 0, "an unknown archetype is an error")

	var bad_spread := WeaponDefinition.from_dict({"id": "x", "archetype": "smg", "spread_base_deg": 5.0, "spread_max_deg": 1.0})
	assert_true((bad_spread["errors"] as Array).size() > 0, "a maximum spread below the base spread is an error")

	var nameless := WeaponDefinition.from_dict({"archetype": "smg"})
	assert_true((nameless["errors"] as Array).size() > 0, "a weapon without an id is an error")

	var valid := WeaponDefinition.from_dict({"id": "custom_smg", "archetype": "smg", "damage": 25.0})
	assert_eq((valid["errors"] as Array).size(), 0, "a valid minimal weapon is accepted")
	assert_eq((valid["weapon"] as WeaponDefinition).damage, 25.0, "explicit values override the archetype")


func test_scenario_validation_rejects_nonsense() -> void:
	var no_targets := ScenarioDefinition.from_dict({"id": "x", "arena": "dojo_open", "weapon": "smg"})
	assert_true((no_targets["errors"] as Array).size() > 0, "a scenario without targets is an error")

	var bad_id := ScenarioDefinition.from_dict({"id": "Bad ID", "targets": [{"type": "sphere"}]})
	assert_true((bad_id["errors"] as Array).size() > 0, "an unsafe scenario id is an error")

	var future := ScenarioDefinition.from_dict({"id": "x", "schema_version": 99, "targets": [{"type": "sphere"}]})
	assert_true((future["errors"] as Array).size() > 0, "a newer schema version is refused")


func test_user_content_cannot_shadow_shipped_content() -> void:
	_write_user_scenario("static_precision_60", {
		"id": "static_precision_60",
		"name": "REPLACEMENT",
		"arena": "dojo_open",
		"weapon": "smg",
		"targets": [{"type": "sphere"}],
	})
	var reloaded := VantaContentLibrary.new()
	reloaded.load_all()
	var definition := reloaded.scenario("static_precision_60")
	assert_not_null(definition, "the shipped scenario is still present")
	assert_eq(definition.name, "STATIC PRECISION", "the shipped scenario was not replaced")
	assert_true(reloaded.errors.size() > 0, "the shadowing attempt was reported")
	_remove_user_content()


func test_user_content_with_a_mismatched_id_is_rejected() -> void:
	_write_user_scenario("mismatch", {
		"id": "something_else",
		"arena": "dojo_open",
		"weapon": "smg",
		"targets": [{"type": "sphere"}],
	})
	var reloaded := VantaContentLibrary.new()
	reloaded.load_all()
	assert_null(reloaded.scenario("mismatch"), "a file whose id does not match its name is not loaded")
	assert_true(reloaded.errors.size() > 0, "the mismatch was reported")
	_remove_user_content()


func test_peek_anchors_are_actually_occluded() -> void:
	# This is the test that keeps the Peek Lab honest: an anchor whose hiding position
	# is visible from the player start is not a peek, it is a target standing in the
	# open, and an anchor whose exposed position is blocked can never be shot.
	var arena := library.arena("peek_boxes")
	var scenario := library.scenario("peek_lab_45")
	assert_not_null(arena, "the peek arena exists")
	assert_not_null(scenario, "the peek scenario exists")
	var registry := HitRegistry.new()
	registry.configure(ArenaBuilder.cover_boxes(arena))
	var eye := arena.player_start
	var azimuth_half := maxf(absf(scenario.spawn.azimuth_degrees.x), absf(scenario.spawn.azimuth_degrees.y))
	var checked := 0
	for anchor in arena.anchors:
		if not scenario.spawn.anchor_ids.has(anchor.id):
			continue
		checked += 1
		var distance := anchor.position.distance_to(eye)
		var corridor := distance * tan(deg_to_rad(azimuth_half))
		var expose := clampf(corridor * PeekController.EXPOSE_OFFSET_FACTOR, PeekController.EXPOSE_OFFSET_MIN, PeekController.EXPOSE_OFFSET_MAX)
		var hidden := clampf(corridor * PeekController.HIDDEN_OFFSET_FACTOR, PeekController.HIDDEN_OFFSET_MIN, PeekController.HIDDEN_OFFSET_MAX) * PeekController.HIDDEN_HOLD_FACTOR
		var axis := anchor.peek_axis.normalized()
		var hidden_point := anchor.position - axis * hidden
		var exposed_point := anchor.position + axis * expose
		assert_true(registry.line_blocked(eye, hidden_point), "anchor '%s' hides its target (%.2f m behind cover)" % [anchor.id, hidden])
		assert_false(registry.line_blocked(eye, exposed_point), "anchor '%s' exposes its target when it steps out (%.2f m)" % [anchor.id, expose])
	assert_true(checked >= 3, "the peek scenario uses at least three anchors (checked %d)" % checked)


func test_peek_anchors_are_not_inside_their_cover() -> void:
	var arena := library.arena("peek_boxes")
	for anchor in arena.anchors:
		if not anchor.has_cover:
			continue
		var cover := anchor.cover_box()
		var offset := (anchor.position - cover.center).abs()
		var inside := offset.x <= cover.half_size.x and offset.y <= cover.half_size.y and offset.z <= cover.half_size.z
		assert_false(inside, "anchor '%s' is not buried inside its own cover box" % anchor.id)


func test_arena_cover_is_closed() -> void:
	var arena := library.arena("dojo_open")
	var boxes := ArenaBuilder.cover_boxes(arena)
	assert_true(boxes.size() >= 7, "the shell adds floor, four walls and the authored cover (got %d)" % boxes.size())
	var registry := HitRegistry.new()
	registry.configure(boxes)
	# A shot straight at the back wall must hit it rather than leaving the arena.
	var hit := registry.resolve(arena.player_start, Vector3(0, 0, -1), [])
	assert_eq(String(hit["result"]), HitRegistry.HIT_COVER, "the back wall stops a shot")
	assert_eq(String(hit["cover_tag"]), "wall", "the wall is tagged as a wall")


func _write_user_scenario(file_stem: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(USER_SCENARIO_DIR)
	var path := "%s/%s.json" % [USER_SCENARIO_DIR, file_stem]
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		assert_fail("could not write test content to %s" % path)
		return
	handle.store_string(JSON.stringify(data))
	handle.close()


func _remove_user_content() -> void:
	var directory := DirAccess.open(USER_SCENARIO_DIR)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not directory.current_is_dir():
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	var root := DirAccess.open("user://content")
	if root != null:
		root.remove("scenarios")
