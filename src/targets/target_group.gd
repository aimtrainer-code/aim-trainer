class_name TargetGroup
extends RefCounted

## One class of target inside a scenario, with a spawn weight.
##
## Grouping exists so a single scenario can mix target types — a "tactical duel"
## scenario might spawn 70% humanoids and 30% shoulder-width head-only targets —
## without duplicating any rules or scoring.

enum Type { SPHERE, DISC, POINT, HUMANOID, HEAD_ONLY }

const TYPE_IDS: Array[String] = ["sphere", "disc", "point", "humanoid", "head_only"]
const TYPE_LABELS: Array[String] = ["SPHERE", "DISC", "POINT", "HUMANOID", "HEAD ONLY"]

## Relative spawn probability. Weights are normalised by the runtime.
var weight: float = 1.0
var type: int = Type.SPHERE
## Radius in metres for spheres/discs, or full height for humanoids.
var size: float = 0.55
## Health. A target with hp > 1 requires several hits unless
## `ScoreSpec`-independent rules say otherwise.
var hp: float = 1.0
## Which regions can be hit and how much damage they take. Keys are region ids from
## HitRegion; the value is the damage multiplier. Humanoids always have head/torso/
## legs unless the scenario restricts them.
var region_multipliers: Dictionary = {}
## Colour index into VantaStyle.TARGET_COLORS (-1 = use the user setting).
var color_override: int = -1
## Target scale variation applied per spawn, e.g. [0.95, 1.05]. This is what stops a
## player from memorising exact target dimensions.
var size_variance: Vector2 = Vector2(1.0, 1.0)
## When true this group's targets can be the Rival's body inside DUEL scenarios.
var rival_body: bool = false

var errors: Array[String] = []
var warnings: Array[String] = []


static func from_dict(data: Variant) -> Dictionary:
	var group := TargetGroup.new()
	var source := SpecParse.dict(data)
	var label := "targets[]"
	group.weight = SpecParse.float_value(source, "weight", 1.0, 0.0, 100.0, group.errors, label)
	group.size = SpecParse.float_value(source, "size", 0.55, 0.05, 6.0, group.errors, label)
	group.hp = SpecParse.float_value(source, "hp", 1.0, 0.1, 1000.0, group.errors, label)

	var type_id := SpecParse.string_value(source, "type", "sphere", 16).to_lower()
	var type_index := TYPE_IDS.find(type_id)
	if type_index < 0:
		group.errors.append("targets[].type '%s' is not supported" % type_id)
	else:
		group.type = type_index

	group.color_override = SpecParse.int_value(source, "color_index", -1, -1, VantaStyle.TARGET_COLORS.size() - 1, group.errors, label)
	group.size_variance = SpecParse.range_value(source, "size_variance", 1.0, 1.0, 0.5, 1.5, group.errors, label)
	group.rival_body = SpecParse.bool_value(source, "rival_body", false)

	if source.has("regions"):
		var raw: Variant = source["regions"]
		if typeof(raw) == TYPE_DICTIONARY:
			for key in (raw as Dictionary).keys():
				var region_id := String(key)
				var multiplier := SpecParse.float_value(raw, region_id, 1.0, 0.0, 10.0, group.errors, label)
				group.region_multipliers[region_id] = multiplier
		else:
			group.errors.append("targets[].regions must be an object of region ids to damage multipliers")

	var is_humanoid := group.type == Type.HUMANOID or group.type == Type.HEAD_ONLY
	if not is_humanoid and not group.region_multipliers.is_empty():
		group.warnings.append("regions are ignored for %s targets" % TYPE_IDS[group.type])
	if group.type == Type.HEAD_ONLY and group.size < 0.15:
		group.warnings.append("head-only target smaller than 15 cm is below the useful training range")
	if group.weight <= 0.0:
		group.warnings.append("target group with weight 0 will never spawn")
	if group.type == Type.POINT and group.size > 0.2:
		group.warnings.append("a 'point' target should be smaller than 20 cm")
	return {"group": group, "errors": group.errors, "warnings": group.warnings}


func type_id() -> String:
	return TYPE_IDS[clampi(type, 0, TYPE_IDS.size() - 1)]


func type_label() -> String:
	return TYPE_LABELS[clampi(type, 0, TYPE_LABELS.size() - 1)]


func is_humanoid() -> bool:
	return type == Type.HUMANOID or type == Type.HEAD_ONLY


## Effective damage multiplier for a region, defaulting to 1.0.
func region_multiplier(region_id: String) -> float:
	if region_multipliers.is_empty():
		return 1.0
	if region_multipliers.has(region_id):
		return float(region_multipliers[region_id])
	return 1.0


func to_dict() -> Dictionary:
	return {
		"type": type_id(),
		"weight": weight,
		"size": size,
		"hp": hp,
		"size_variance": [size_variance.x, size_variance.y],
		"color_index": color_override,
		"rival_body": rival_body,
		"regions": region_multipliers,
	}
