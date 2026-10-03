class_name ReactionSpec
extends RefCounted

## Latency budget applied to targets and to the Rival.
##
## VANTA is explicit about the difference between *human* reaction time and
## *software* delay:
##   - `human_delay` models the time a person needs to notice and start moving.
##     It is applied to spawned targets only when a scenario asks for it (for
##     example "delayed peek" in Peek Lab), never as a fake handicap.
##   - Nothing here adds artificial delay to the *player's* input. VANTA does not
##     and will not add input latency to "balance" a drill.
##
## Reaction values are drawn per spawn from the range, so a target never reacts with
## the mechanically perfect timing that makes training feel synthetic.

## Seconds between the stimulus and the target's first movement.
var human_delay: Vector2 = Vector2(0.0, 0.0)
## How often the target fails to react at all within its lifetime (0-1). Gives
## targets a believable lull instead of constant action.
var hesitation_chance: float = 0.0
## Extra delay applied when the target re-peeks (Peek Lab).
var reengage_delay: Vector2 = Vector2(0.2, 0.9)
## Probability that an eliminated/expired target re-peeks rather than disappearing.
var reengage_chance: float = 0.0

var errors: Array[String] = []


static func from_dict(data: Variant) -> ReactionSpec:
	var spec := ReactionSpec.new()
	var source := SpecParse.dict(data)
	var label := "reaction"
	spec.human_delay = SpecParse.range_value(source, "human_delay", 0.0, 0.0, 0.0, 10.0, spec.errors, label)
	spec.hesitation_chance = SpecParse.float_value(source, "hesitation_chance", 0.0, 0.0, 1.0, spec.errors, label)
	spec.reengage_delay = SpecParse.range_value(source, "reengage_delay", 0.2, 0.9, 0.0, 30.0, spec.errors, label)
	spec.reengage_chance = SpecParse.float_value(source, "reengage_chance", 0.0, 0.0, 1.0, spec.errors, label)
	if spec.reengage_chance > 0.0 and spec.reengage_delay.y <= 0.0:
		spec.errors.append("reaction.reengage_delay must be greater than zero when re-peeks are enabled")
	return spec


func to_dict() -> Dictionary:
	return {
		"human_delay": [human_delay.x, human_delay.y],
		"hesitation_chance": hesitation_chance,
		"reengage_delay": [reengage_delay.x, reengage_delay.y],
		"reengage_chance": reengage_chance,
	}
