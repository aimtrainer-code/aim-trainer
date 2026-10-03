class_name AmmoSpec
extends RefCounted

## Ammunition rules.
##
## Ammo exists to put a cost on spam. A precision drill with a magazine of 10 and a
## miss penalty teaches trigger discipline; an infinite-ammo tracking drill with a
## beam weapon teaches smoothness. Both are legitimate, which is why this is data.

var infinite: bool = true
var magazine: int = 30
var reload_seconds: float = 2.0
## When true a reload happens automatically when the magazine is empty; when false
## the player must press reload, which is what competitive titles do.
var auto_reload: bool = true
## When true an empty magazine ends the round/scenario immediately.
var empty_ends_round: bool = false
## Fraction of the magazine required to be left at the end of the round for the
## round to count as disciplined (used by trigger-discipline scenarios).
var discipline_threshold: float = 0.0
## Clears the magazine counter at the start of every round.
var reset_each_round: bool = true

var errors: Array[String] = []


static func from_dict(data: Variant) -> AmmoSpec:
	var spec := AmmoSpec.new()
	var source := SpecParse.dict(data)
	var label := "ammo"
	spec.infinite = SpecParse.bool_value(source, "infinite", true)
	spec.magazine = SpecParse.int_value(source, "magazine", 30, 1, 500, spec.errors, label)
	spec.reload_seconds = SpecParse.float_value(source, "reload_seconds", 2.0, 0.0, 30.0, spec.errors, label)
	spec.auto_reload = SpecParse.bool_value(source, "auto_reload", true)
	spec.empty_ends_round = SpecParse.bool_value(source, "empty_ends_round", false)
	spec.discipline_threshold = SpecParse.float_value(source, "discipline_threshold", 0.0, 0.0, 1.0, spec.errors, label)
	spec.reset_each_round = SpecParse.bool_value(source, "reset_each_round", true)
	if spec.infinite and spec.empty_ends_round:
		spec.errors.append("ammo.empty_ends_round cannot be used with infinite ammo")
	return spec


func to_dict() -> Dictionary:
	return {
		"infinite": infinite,
		"magazine": magazine,
		"reload_seconds": reload_seconds,
		"auto_reload": auto_reload,
		"empty_ends_round": empty_ends_round,
		"discipline_threshold": discipline_threshold,
		"reset_each_round": reset_each_round,
	}
