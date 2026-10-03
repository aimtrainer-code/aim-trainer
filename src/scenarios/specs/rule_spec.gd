class_name RuleSpec
extends RefCounted

## Session rules that are about behaviour rather than scoring.
##
## Every one of these exists to close an exploit. `end_on_miss` makes spray
## transferring pointless in a precision drill; `max_shots_per_target` stops a player
## from machine-gunning a single dummy; `require_settled` refuses to score shots
## taken while the character is moving in a counter-movement drill.

## End the round after this many misses (0 = never).
var max_misses: int = 0
## End the round after this many consecutive misses (0 = never).
var max_consecutive_misses: int = 0
## Maximum shots allowed per target before it counts as failed (0 = unlimited).
var max_shots_per_target: int = 0
## Shots fired while moving are rejected (movement + aim, counter-movement).
var require_stationary: bool = false
## Speed under which the player counts as stationary, in metres per second.
var stationary_threshold: float = 0.55
## Shots fired while airborne are rejected.
var forbid_airborne_shots: bool = false
## Shots must be fired while aiming down sights / scoped.
var require_ads: bool = false
## Minimum time between accepted shots, in seconds (0 = weapon fire rate only).
var min_shot_interval: float = 0.0
## When true, hits outside the specified region score nothing (used by Headshot
## Matrix so body hits do not count as progress).
var region_restricted: bool = false
## Ends the round when the player's crosshair leaves the arena bounds.
var stay_in_bounds: bool = false
## Freeze the player's position (no movement input) — the default for aim training.
var lock_player_position: bool = true

var errors: Array[String] = []


static func from_dict(data: Variant) -> RuleSpec:
	var spec := RuleSpec.new()
	var source := SpecParse.dict(data)
	var label := "rules"
	spec.max_misses = SpecParse.int_value(source, "max_misses", 0, 0, 10000, spec.errors, label)
	spec.max_consecutive_misses = SpecParse.int_value(source, "max_consecutive_misses", 0, 0, 1000, spec.errors, label)
	spec.max_shots_per_target = SpecParse.int_value(source, "max_shots_per_target", 0, 0, 1000, spec.errors, label)
	spec.require_stationary = SpecParse.bool_value(source, "require_stationary", false)
	spec.stationary_threshold = SpecParse.float_value(source, "stationary_threshold", 0.55, 0.0, 20.0, spec.errors, label)
	spec.forbid_airborne_shots = SpecParse.bool_value(source, "forbid_airborne_shots", false)
	spec.require_ads = SpecParse.bool_value(source, "require_ads", false)
	spec.min_shot_interval = SpecParse.float_value(source, "min_shot_interval", 0.0, 0.0, 5.0, spec.errors, label)
	spec.region_restricted = SpecParse.bool_value(source, "region_restricted", false)
	spec.stay_in_bounds = SpecParse.bool_value(source, "stay_in_bounds", false)
	spec.lock_player_position = SpecParse.bool_value(source, "lock_player_position", true)
	return spec


func to_dict() -> Dictionary:
	return {
		"max_misses": max_misses,
		"max_consecutive_misses": max_consecutive_misses,
		"max_shots_per_target": max_shots_per_target,
		"require_stationary": require_stationary,
		"stationary_threshold": stationary_threshold,
		"forbid_airborne_shots": forbid_airborne_shots,
		"require_ads": require_ads,
		"min_shot_interval": min_shot_interval,
		"region_restricted": region_restricted,
		"stay_in_bounds": stay_in_bounds,
		"lock_player_position": lock_player_position,
	}
