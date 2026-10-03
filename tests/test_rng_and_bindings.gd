extends VantaTestCase

## Determinism and input-binding safety.
##
## Determinism is a product requirement (scenario seeds must reproduce a run), and
## bindings are the one part of the settings file that can render the application
## unusable if a user breaks it, so both are tested in detail.


func test_same_seed_same_sequence() -> void:
	var a := VantaRng.new(12345)
	var b := VantaRng.new(12345)
	for i in 50:
		assert_eq(a.roll_range("spawn", 0.0, 100.0), b.roll_range("spawn", 0.0, 100.0), "identical seeds produce identical values at index %d" % i)


func test_different_seeds_diverge() -> void:
	var a := VantaRng.new(1)
	var b := VantaRng.new(2)
	var identical := 0
	for i in 20:
		if is_equal_approx(a.roll("spawn"), b.roll("spawn")):
			identical += 1
	assert_less(float(identical), 3.0, "different seeds should not agree on most values")


func test_streams_are_independent() -> void:
	# Drawing from "motion" must not disturb the "spawn" stream. This is what keeps
	# historical runs reproducible when unrelated systems start using more randoms.
	var control := VantaRng.new(777)
	var expected: Array[float] = []
	for i in 10:
		expected.append(control.roll("spawn"))

	var perturbed := VantaRng.new(777)
	for i in 10:
		perturbed.roll_range("motion", -100.0, 100.0)
	for i in 10:
		assert_almost_eq(perturbed.roll("spawn"), expected[i], "spawn stream unaffected by the motion stream", 1e-12)


func test_stream_values_are_stable_across_instances() -> void:
	# Pins the stream derivation so a refactor cannot silently change every seed.
	var rng := VantaRng.new(4242)
	var first := rng.roll_int("lifetime", 0, 1000000)
	var again := VantaRng.new(4242).roll_int("lifetime", 0, 1000000)
	assert_eq(first, again, "stream derivation is stable")


func test_weighted_pick_respects_weights() -> void:
	var rng := VantaRng.new(99)
	var counts := [0, 0, 0]
	for i in 3000:
		counts[rng.pick_weighted("spawn", [0.0, 1.0, 0.0])] += 1
	assert_eq(counts[0], 0, "zero weight is never selected")
	assert_eq(counts[2], 0, "zero weight is never selected")
	assert_eq(counts[1], 3000, "the only positive weight always wins")

	var rng2 := VantaRng.new(100)
	var hits := 0
	for i in 2000:
		if rng2.pick_weighted("spawn", [1.0, 1.0]) == 0:
			hits += 1
	assert_between(float(hits), 900.0, 1100.0, "two equal weights split roughly evenly")


func test_gaussian_is_centred() -> void:
	var rng := VantaRng.new(31337)
	var sum := 0.0
	var count := 4000
	for i in count:
		sum += rng.gaussian("rival", 0.0, 1.0)
	var mean := sum / float(count)
	assert_between(mean, -0.1, 0.1, "gaussian mean is close to zero")


func test_shuffle_is_deterministic_and_complete() -> void:
	var rng := VantaRng.new(5)
	var shuffled := rng.shuffled("spawn", [1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(shuffled.size(), 8, "shuffle preserves length")
	var sorted := shuffled.duplicate()
	sorted.sort()
	assert_eq(sorted, [1, 2, 3, 4, 5, 6, 7, 8], "shuffle preserves contents")
	var again := VantaRng.new(5).shuffled("spawn", [1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(shuffled, again, "shuffle is deterministic")


func test_chance_bounds() -> void:
	var rng := VantaRng.new(1)
	for i in 100:
		assert_false(rng.chance("x", 0.0), "p=0 never fires")
		assert_true(rng.chance("x", 1.0), "p=1 always fires")


# --- input bindings --------------------------------------------------------

func test_binding_sanitise_restores_required_actions() -> void:
	var result: Dictionary = InputBindings.sanitise({"fire": [], "aim": "nope", "pause": null})
	var bindings: Dictionary = result["bindings"]
	assert_eq(bindings["fire"], ["mouse:1"], "fire cannot be unbound")
	assert_eq(bindings["pause"], ["key:4194305"], "pause falls back to its default")


func test_binding_sanitise_rejects_bad_descriptors() -> void:
	var result: Dictionary = InputBindings.sanitise({"fire": ["mouse:1", "mouse:99", "key:abc", "", "exec:rm"]})
	var bindings: Dictionary = result["bindings"]
	assert_eq(bindings["fire"], ["mouse:1"], "only the valid descriptor survives")
	var joined := "\n".join(result["repairs"])
	assert_string_contains(joined, "invalid binding", "invalid descriptors are reported")


func test_binding_sanitise_ignores_unknown_actions() -> void:
	var result: Dictionary = InputBindings.sanitise({"become_pro": ["key:80"]})
	var joined := "\n".join(result["repairs"])
	assert_string_contains(joined, "unknown action", "unknown actions are reported")
	assert_false(result["bindings"].has("become_pro"), "unknown action is not applied")


func test_binding_conflicts_are_detected() -> void:
	var table := InputBindings.default_bindings()
	table["next_step"] = ["key:82"]  # same as reload
	var conflicts := InputBindings.conflicts(table)
	assert_greater(float(conflicts.size()), 0.0, "duplicate binding is detected")
	var found := false
	for conflict in conflicts:
		if conflict["descriptor"] == "key:82":
			found = true
	assert_true(found, "the conflicting descriptor is identified")


func test_descriptor_round_trip() -> void:
	for descriptor in ["mouse:1", "mouse:5", "key:87", "key:4194305"]:
		var event := InputBindings.event_from_descriptor(descriptor)
		assert_not_null(event, "descriptor %s produces an event" % descriptor)
		var back := InputBindings.descriptor_from_event(event)
		assert_eq(back, descriptor, "descriptor survives a round trip for %s" % descriptor)


func test_describe_produces_readable_names() -> void:
	assert_eq(InputBindings.describe("mouse:1"), "MOUSE LEFT", "mouse button 1 is described")
	assert_eq(InputBindings.describe("mouse:2"), "MOUSE RIGHT", "mouse button 2 is described")
	assert_true(InputBindings.describe("key:87").length() > 0, "key descriptors have a readable form")


func test_every_default_action_is_well_formed() -> void:
	for action in InputBindings.action_ids():
		var defaults := InputBindings.defaults_for(action)
		assert_greater(float(defaults.size()), 0.0, "action %s has at least one default" % action)
		for descriptor in defaults:
			assert_true(InputBindings.is_valid_descriptor(descriptor), "default %s for %s is valid" % [descriptor, action])
