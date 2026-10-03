class_name LifetimeSpec
extends RefCounted

## How long a target stays available.
##
## A short lifetime is one of the strongest difficulty levers in aim training: it
## converts "how fast can I click" into "can I acquire and click in time", which is
## closer to a real engagement. The spec distinguishes the lifetime *range* from the
## grace period a target gets after being damaged, so a partially damaged target does
## not vanish mid-correction without warning.

## Seconds the target remains alive. Expiry counts as a miss when
## `counts_as_miss` is true.
var min_seconds: float = 3.0
var max_seconds: float = 3.0
## Extra time granted after the first hit on a target (0 = none).
var grace_after_hit: float = 0.0
## Whether expiry is scored as a miss.
var counts_as_miss: bool = true
## Despawn immediately when hit (clicking modes) instead of waiting for HP to drain.
var die_on_first_hit: bool = true
## Delay before a new target replaces an expired/eliminated one.
var respawn_delay: float = 0.0
## Fade-in time during which the target is visible but not yet interactive. 0 means
## targets are interactive the instant they exist, which is correct for precision
## work where the "spawn pop" is the reaction stimulus.
var spawn_fade: float = 0.0

var errors: Array[String] = []


static func from_dict(data: Variant) -> LifetimeSpec:
	var spec := LifetimeSpec.new()
	var source := SpecParse.dict(data)
	var label := "lifetime"
	var span := SpecParse.range_value(source, "seconds", 3.0, 3.0, 0.25, 600.0, spec.errors, label)
	spec.min_seconds = span.x
	spec.max_seconds = span.y
	spec.grace_after_hit = SpecParse.float_value(source, "grace_after_hit", 0.0, 0.0, 60.0, spec.errors, label)
	spec.counts_as_miss = SpecParse.bool_value(source, "counts_as_miss", true)
	spec.die_on_first_hit = SpecParse.bool_value(source, "die_on_first_hit", true)
	spec.respawn_delay = SpecParse.float_value(source, "respawn_delay", 0.0, 0.0, 10.0, spec.errors, label)
	spec.spawn_fade = SpecParse.float_value(source, "spawn_fade", 0.0, 0.0, 2.0, spec.errors, label)
	if spec.grace_after_hit > 0.0 and spec.die_on_first_hit:
		spec.errors.append("lifetime.grace_after_hit has no effect when lifetime.die_on_first_hit is true")
	return spec


func to_dict() -> Dictionary:
	return {
		"seconds": [min_seconds, max_seconds],
		"grace_after_hit": grace_after_hit,
		"counts_as_miss": counts_as_miss,
		"die_on_first_hit": die_on_first_hit,
		"respawn_delay": respawn_delay,
		"spawn_fade": spawn_fade,
	}
