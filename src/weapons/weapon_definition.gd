class_name WeaponDefinition
extends RefCounted

## Data-driven weapon archetype.
##
## VANTA does not simulate any specific title's weapon. These are generic archetypes
## with configurable behaviour, and every value is visible and editable in
## `content/weapons/*.json`. The documentation states plainly that a number here does
## not correspond to a real weapon's ballistics, because no such claim could be
## verified without access to the game's own data.
##
## What the numbers *do* give you is the training-relevant behaviour: how long between
## shots, how large the cone of error is while moving, how the recoil accumulates, and
## how much the weapon punishes a bad first shot. Those are the variables that change
## what a drill trains.

enum Archetype { TACTICAL_RIFLE, PRECISION_RIFLE, SMG, PISTOL, HEAVY_PISTOL, SNIPER, TRACKING_BEAM }

const ARCHETYPE_IDS: Array[String] = [
	"tactical_rifle", "precision_rifle", "smg", "pistol", "heavy_pistol", "sniper", "tracking_beam",
]
const ARCHETYPE_LABELS: Array[String] = [
	"TACTICAL RIFLE", "PRECISION RIFLE", "SMG", "PISTOL", "HEAVY PISTOL", "SNIPER", "TRACKING BEAM",
]

var id: String = "tactical_rifle"
var name: String = "TACTICAL RIFLE"
var description: String = ""
var archetype: int = Archetype.TACTICAL_RIFLE

# --- firing ----------------------------------------------------------------
var automatic: bool = true
var fire_rate_rpm: float = 600.0
var shots_per_burst: int = 0  ## 0 = no burst limit, 1 = single shot per trigger pull
var burst_cooldown: float = 0.0
var damage: float = 30.0
var head_multiplier: float = 1.0
var pellets: int = 1  ## >1 for shotgun-style spread; supported by the resolver

# --- accuracy --------------------------------------------------------------
## Cone half-angle in degrees while standing still and settled.
var spread_base_deg: float = 0.05
## Added per shot fired, before recovery pulls it back.
var spread_per_shot_deg: float = 0.12
var spread_max_deg: float = 2.5
## Degrees of bloom removed per second when not firing.
var spread_recovery_deg_per_second: float = 4.0
## Extra cone while moving at `movement_reference_speed`.
var movement_inaccuracy_deg: float = 1.8
var movement_reference_speed: float = 3.0
var airborne_inaccuracy_deg: float = 4.0
## Multiplier applied to the total spread while aiming down sights.
var ads_spread_multiplier: float = 0.5
## Multiplier applied to the first shot of a burst (first-shot accuracy).
var first_shot_spread_multiplier: float = 0.35

# --- recoil ----------------------------------------------------------------
## Recoil applied to the view per shot, in degrees.
var recoil_vertical_deg: float = 0.35
var recoil_horizontal_deg: float = 0.12
## How much the pattern climbs by the end of a magazine (1.0 = no growth).
var recoil_growth: float = 1.0
## Degrees per second the view returns towards the player's aim when not firing.
var recoil_recovery_deg_per_second: float = 12.0
## Fraction of the recoil that is a fixed, learnable pattern versus random walk. A
## pattern at 1.0 is fully learnable (recoil control drills); at 0.0 it is random.
var recoil_pattern_ratio: float = 0.75

# --- handling --------------------------------------------------------------
var magazine: int = 30
var reload_seconds: float = 2.4
var ads_enabled: bool = false
var ads_fov: float = 55.0
var ads_time: float = 0.18
## Beam weapons apply damage continuously while the crosshair is on target.
var beam: bool = false
var beam_tick_seconds: float = 0.1
var beam_damage_per_second: float = 60.0

# --- presentation ----------------------------------------------------------
var fire_sound: String = "rifle_fire"
var impact_sound: String = "impact"
var beam_sound: String = "beam"

var errors: Array[String] = []
var warnings: Array[String] = []
var source_path: String = ""


static func from_dict(data: Variant, source_path: String = "") -> Dictionary:
	var weapon := WeaponDefinition.new()
	weapon.source_path = source_path
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		errors.append("weapon file must contain a JSON object")
		return {"weapon": weapon, "errors": errors, "warnings": warnings}
	var d: Dictionary = data

	weapon.id = SpecParse.string_value(d, "id", "", 64)
	if weapon.id.is_empty():
		errors.append("'id' is required")
	elif not ScenarioDefinition.is_safe_id(weapon.id):
		errors.append("'id' must be lowercase letters, digits, dashes or underscores")
	weapon.name = SpecParse.string_value(d, "name", weapon.id.to_upper(), 40)
	weapon.description = SpecParse.string_value(d, "description", "", 240)

	var archetype_id := SpecParse.string_value(d, "archetype", "tactical_rifle", 32).to_lower()
	var archetype_index := ARCHETYPE_IDS.find(archetype_id)
	if archetype_index < 0:
		errors.append("unknown archetype '%s'" % archetype_id)
		archetype_index = Archetype.TACTICAL_RIFLE
	weapon.archetype = archetype_index
	_apply_archetype_defaults(weapon)

	weapon.automatic = SpecParse.bool_value(d, "automatic", weapon.automatic)
	weapon.fire_rate_rpm = SpecParse.float_value(d, "fire_rate_rpm", weapon.fire_rate_rpm, 20.0, 3000.0, errors, "weapon")
	weapon.shots_per_burst = SpecParse.int_value(d, "shots_per_burst", weapon.shots_per_burst, 0, 60, errors, "weapon")
	weapon.burst_cooldown = SpecParse.float_value(d, "burst_cooldown", weapon.burst_cooldown, 0.0, 5.0, errors, "weapon")
	weapon.damage = SpecParse.float_value(d, "damage", weapon.damage, 0.1, 500.0, errors, "weapon")
	weapon.head_multiplier = SpecParse.float_value(d, "head_multiplier", weapon.head_multiplier, 1.0, 20.0, errors, "weapon")
	weapon.pellets = SpecParse.int_value(d, "pellets", weapon.pellets, 1, 64, errors, "weapon")

	weapon.spread_base_deg = SpecParse.float_value(d, "spread_base_deg", weapon.spread_base_deg, 0.0, 30.0, errors, "weapon")
	weapon.spread_per_shot_deg = SpecParse.float_value(d, "spread_per_shot_deg", weapon.spread_per_shot_deg, 0.0, 10.0, errors, "weapon")
	weapon.spread_max_deg = SpecParse.float_value(d, "spread_max_deg", weapon.spread_max_deg, 0.0, 45.0, errors, "weapon")
	weapon.spread_recovery_deg_per_second = SpecParse.float_value(d, "spread_recovery_deg_per_second", weapon.spread_recovery_deg_per_second, 0.0, 200.0, errors, "weapon")
	weapon.movement_inaccuracy_deg = SpecParse.float_value(d, "movement_inaccuracy_deg", weapon.movement_inaccuracy_deg, 0.0, 45.0, errors, "weapon")
	weapon.movement_reference_speed = SpecParse.float_value(d, "movement_reference_speed", weapon.movement_reference_speed, 0.1, 30.0, errors, "weapon")
	weapon.airborne_inaccuracy_deg = SpecParse.float_value(d, "airborne_inaccuracy_deg", weapon.airborne_inaccuracy_deg, 0.0, 45.0, errors, "weapon")
	weapon.ads_spread_multiplier = SpecParse.float_value(d, "ads_spread_multiplier", weapon.ads_spread_multiplier, 0.0, 2.0, errors, "weapon")
	weapon.first_shot_spread_multiplier = SpecParse.float_value(d, "first_shot_spread_multiplier", weapon.first_shot_spread_multiplier, 0.0, 2.0, errors, "weapon")

	weapon.recoil_vertical_deg = SpecParse.float_value(d, "recoil_vertical_deg", weapon.recoil_vertical_deg, 0.0, 30.0, errors, "weapon")
	weapon.recoil_horizontal_deg = SpecParse.float_value(d, "recoil_horizontal_deg", weapon.recoil_horizontal_deg, 0.0, 30.0, errors, "weapon")
	weapon.recoil_growth = SpecParse.float_value(d, "recoil_growth", weapon.recoil_growth, 0.2, 8.0, errors, "weapon")
	weapon.recoil_recovery_deg_per_second = SpecParse.float_value(d, "recoil_recovery_deg_per_second", weapon.recoil_recovery_deg_per_second, 0.0, 500.0, errors, "weapon")
	weapon.recoil_pattern_ratio = SpecParse.float_value(d, "recoil_pattern_ratio", weapon.recoil_pattern_ratio, 0.0, 1.0, errors, "weapon")

	weapon.magazine = SpecParse.int_value(d, "magazine", weapon.magazine, 1, 500, errors, "weapon")
	weapon.reload_seconds = SpecParse.float_value(d, "reload_seconds", weapon.reload_seconds, 0.0, 30.0, errors, "weapon")
	weapon.ads_enabled = SpecParse.bool_value(d, "ads_enabled", weapon.ads_enabled)
	weapon.ads_fov = SpecParse.float_value(d, "ads_fov", weapon.ads_fov, 5.0, 120.0, errors, "weapon")
	weapon.ads_time = SpecParse.float_value(d, "ads_time", weapon.ads_time, 0.0, 2.0, errors, "weapon")
	weapon.beam = SpecParse.bool_value(d, "beam", weapon.beam)
	weapon.beam_tick_seconds = SpecParse.float_value(d, "beam_tick_seconds", weapon.beam_tick_seconds, 0.02, 1.0, errors, "weapon")
	weapon.beam_damage_per_second = SpecParse.float_value(d, "beam_damage_per_second", weapon.beam_damage_per_second, 0.0, 2000.0, errors, "weapon")
	weapon.fire_sound = SpecParse.string_value(d, "fire_sound", weapon.fire_sound, 32)
	weapon.impact_sound = SpecParse.string_value(d, "impact_sound", weapon.impact_sound, 32)
	weapon.beam_sound = SpecParse.string_value(d, "beam_sound", weapon.beam_sound, 32)

	# Cross-field checks: the combinations that would produce a broken drill.
	if weapon.spread_max_deg < weapon.spread_base_deg:
		errors.append("spread_max_deg is below spread_base_deg, so the weapon can never reach its base accuracy")
	if weapon.shots_per_burst == 1 and weapon.automatic:
		warnings.append("automatic fire with a 1-shot burst limit behaves like a semi-automatic weapon")
	if weapon.beam and weapon.spread_base_deg > 0.25:
		warnings.append("a beam weapon with spread above 0.25° will feel unreliable; beams are for tracking drills")
	if weapon.beam and weapon.recoil_vertical_deg > 0.0:
		warnings.append("recoil on a beam weapon biases tracking drills; keep recoil_vertical_deg at 0")
	if weapon.fire_rate_rpm > 1200.0 and weapon.damage > 60.0:
		warnings.append("very high rate of fire with high damage will end duels instantly")
	if weapon.pellets == 1 and not weapon.beam and weapon.spread_base_deg == 0.0 and weapon.spread_per_shot_deg == 0.0:
		warnings.append("a perfectly accurate weapon with no bloom trains nothing about trigger discipline")

	weapon.errors = errors
	weapon.warnings = warnings
	return {"weapon": weapon, "errors": errors, "warnings": warnings}


## Archetype presets. Authors only need the fields they want to change.
static func _apply_archetype_defaults(weapon: WeaponDefinition) -> void:
	match weapon.archetype:
		Archetype.TACTICAL_RIFLE:
			weapon.automatic = true
			weapon.fire_rate_rpm = 600.0
			weapon.damage = 30.0
			weapon.head_multiplier = 1.0
			weapon.spread_base_deg = 0.05
			weapon.spread_per_shot_deg = 0.14
			weapon.spread_max_deg = 2.8
			weapon.recoil_vertical_deg = 0.38
			weapon.recoil_horizontal_deg = 0.13
			weapon.magazine = 30
			weapon.ads_enabled = false
		Archetype.PRECISION_RIFLE:
			weapon.automatic = false
			weapon.fire_rate_rpm = 220.0
			weapon.damage = 65.0
			weapon.head_multiplier = 1.6
			weapon.spread_base_deg = 0.02
			weapon.spread_per_shot_deg = 0.5
			weapon.spread_max_deg = 4.0
			weapon.recoil_vertical_deg = 0.9
			weapon.magazine = 20
			weapon.ads_enabled = true
			weapon.ads_fov = 45.0
		Archetype.SMG:
			weapon.automatic = true
			weapon.fire_rate_rpm = 900.0
			weapon.damage = 22.0
			weapon.spread_base_deg = 0.12
			weapon.spread_per_shot_deg = 0.16
			weapon.spread_max_deg = 3.6
			weapon.recoil_vertical_deg = 0.28
			weapon.movement_inaccuracy_deg = 0.9
			weapon.magazine = 30
		Archetype.PISTOL:
			weapon.automatic = false
			weapon.fire_rate_rpm = 400.0
			weapon.damage = 28.0
			weapon.head_multiplier = 1.4
			weapon.spread_base_deg = 0.03
			weapon.recoil_vertical_deg = 0.5
			weapon.magazine = 15
			weapon.ads_enabled = true
			weapon.ads_fov = 60.0
		Archetype.HEAVY_PISTOL:
			weapon.automatic = false
			weapon.fire_rate_rpm = 260.0
			weapon.damage = 60.0
			weapon.head_multiplier = 2.0
			weapon.spread_base_deg = 0.02
			weapon.recoil_vertical_deg = 1.3
			weapon.recoil_horizontal_deg = 0.3
			weapon.magazine = 7
			weapon.ads_enabled = true
			weapon.ads_fov = 55.0
		Archetype.SNIPER:
			weapon.automatic = false
			weapon.fire_rate_rpm = 45.0
			weapon.damage = 150.0
			weapon.head_multiplier = 2.0
			weapon.spread_base_deg = 0.0
			weapon.spread_per_shot_deg = 1.2
			weapon.spread_max_deg = 6.0
			weapon.recoil_vertical_deg = 2.2
			weapon.magazine = 5
			weapon.reload_seconds = 3.0
			weapon.ads_enabled = true
			weapon.ads_fov = 18.0
			weapon.ads_time = 0.35
		Archetype.TRACKING_BEAM:
			weapon.automatic = true
			# A beam's damage rate is `beam_damage_per_second` applied on
			# `beam_tick_seconds`; the fire rate only bounds how often the trigger can
			# re-acquire, so it stays inside the validator's accepted range.
			weapon.fire_rate_rpm = 3000.0
			weapon.damage = 1.0
			weapon.spread_base_deg = 0.0
			weapon.spread_per_shot_deg = 0.0
			weapon.spread_max_deg = 0.0
			weapon.recoil_vertical_deg = 0.0
			weapon.recoil_horizontal_deg = 0.0
			weapon.magazine = 1000000
			weapon.beam = true
			weapon.movement_inaccuracy_deg = 0.0


func archetype_id() -> String:
	return ARCHETYPE_IDS[clampi(archetype, 0, ARCHETYPE_IDS.size() - 1)]


func archetype_label() -> String:
	return ARCHETYPE_LABELS[clampi(archetype, 0, ARCHETYPE_LABELS.size() - 1)]


func shot_interval() -> float:
	if fire_rate_rpm <= 0.0:
		return 0.0
	return 60.0 / fire_rate_rpm


func to_dict() -> Dictionary:
	return {
		"schema_version": 1,
		"id": id,
		"name": name,
		"description": description,
		"archetype": archetype_id(),
		"automatic": automatic,
		"fire_rate_rpm": fire_rate_rpm,
		"shots_per_burst": shots_per_burst,
		"burst_cooldown": burst_cooldown,
		"damage": damage,
		"head_multiplier": head_multiplier,
		"pellets": pellets,
		"spread_base_deg": spread_base_deg,
		"spread_per_shot_deg": spread_per_shot_deg,
		"spread_max_deg": spread_max_deg,
		"spread_recovery_deg_per_second": spread_recovery_deg_per_second,
		"movement_inaccuracy_deg": movement_inaccuracy_deg,
		"movement_reference_speed": movement_reference_speed,
		"airborne_inaccuracy_deg": airborne_inaccuracy_deg,
		"ads_spread_multiplier": ads_spread_multiplier,
		"first_shot_spread_multiplier": first_shot_spread_multiplier,
		"recoil_vertical_deg": recoil_vertical_deg,
		"recoil_horizontal_deg": recoil_horizontal_deg,
		"recoil_growth": recoil_growth,
		"recoil_recovery_deg_per_second": recoil_recovery_deg_per_second,
		"recoil_pattern_ratio": recoil_pattern_ratio,
		"magazine": magazine,
		"reload_seconds": reload_seconds,
		"ads_enabled": ads_enabled,
		"ads_fov": ads_fov,
		"ads_time": ads_time,
		"beam": beam,
		"beam_tick_seconds": beam_tick_seconds,
		"beam_damage_per_second": beam_damage_per_second,
		"fire_sound": fire_sound,
		"impact_sound": impact_sound,
		"beam_sound": beam_sound,
	}
