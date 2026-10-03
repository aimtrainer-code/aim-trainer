class_name ScenarioDefinition
extends RefCounted

## Versioned, human-readable scenario definition.
##
## A scenario is pure data (JSON on disk, this class in memory). The runtime
## (`src/simulation/scenario_runtime.gd`) interprets it and knows nothing about any
## specific trainer, which is what allows the community to author scenarios without
## touching engine code (see docs/SCENARIOS.md).
##
## Parsing is defensive by design: a malformed community file must produce a clear
## error list instead of a crash, and it must never be able to reference a file
## outside the content directory (path handling happens in VantaContentLibrary).

const SCHEMA_VERSION: int = 1

## Training modes. `custom` exists for community scenarios that combine behaviours.
enum Mode {
	STATIC_PRECISION,
	MICRO_FLICK,
	WIDE_FLICK,
	DYNAMIC_CLICKING,
	SMOOTH_TRACKING,
	REACTIVE_TRACKING,
	TARGET_SWITCHING,
	HEADSHOT_MATRIX,
	MOVEMENT_AIM,
	PEEK_LAB,
	DUEL,
	CUSTOM,
}

## Where a scenario sits in the transfer ladder
## (ISOLATION → VARIATION → COMBINATION → PRESSURE → COMBAT).
enum TransferStage { ISOLATION, VARIATION, COMBINATION, PRESSURE, COMBAT }

const MODE_IDS: Array[String] = [
	"static_precision", "micro_flick", "wide_flick", "dynamic_clicking",
	"smooth_tracking", "reactive_tracking", "target_switching", "headshot_matrix",
	"movement_aim", "peek_lab", "duel", "custom",
]
const MODE_LABELS: Array[String] = [
	"STATIC PRECISION", "MICRO FLICK", "WIDE FLICK", "DYNAMIC CLICKING",
	"SMOOTH TRACKING", "REACTIVE TRACKING", "TARGET SWITCHING", "HEADSHOT MATRIX",
	"MOVEMENT + AIM", "PEEK LAB", "DUEL", "CUSTOM",
]
const TRANSFER_IDS: Array[String] = ["isolation", "variation", "combination", "pressure", "combat"]

# --- identity --------------------------------------------------------------
var id: String = ""
var version: int = 1
var name: String = "UNTITLED"
var description: String = ""
var author: String = ""
var mode: int = Mode.CUSTOM
var tags: Array[String] = []
var source_path: String = ""

# --- structure -------------------------------------------------------------
var duration_seconds: float = 60.0
## Optional round/elimination goal. 0 = run for the full duration.
var rounds: int = 0
var arena_id: String = "dojo_open"
var weapon_id: String = "tactical_rifle"
var seed: int = 0
## When true the runtime derives a new seed every attempt; when false the scenario
## replays identically, which is what benchmarks and coach-led drills want.
var randomise_seed: bool = true

# --- training metadata -----------------------------------------------------
var skill: String = "aim_control.precision"
var transfer_stage: int = TransferStage.ISOLATION
var lesson_id: String = ""
var difficulty: int = 3  ## 1..10, human-facing label only (see docs/TRAINING_DESIGN.md)

# --- targets ---------------------------------------------------------------
var target_groups: Array[TargetGroup] = []
var simultaneous_targets: int = 1
var spawn: SpawnSpec = SpawnSpec.new()
var lifetime: LifetimeSpec = LifetimeSpec.new()
var motion: MotionSpec = MotionSpec.new()
var reaction: ReactionSpec = ReactionSpec.new()

# --- rules -----------------------------------------------------------------
var ammo: AmmoSpec = AmmoSpec.new()
var rules: RuleSpec = RuleSpec.new()
var scoring: ScoreSpec = ScoreSpec.new()
var success: SuccessSpec = SuccessSpec.new()
var adaptive: AdaptiveSpec = AdaptiveSpec.new()

# --- parse results ---------------------------------------------------------
var errors: Array[String] = []
var warnings: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty()


func mode_id() -> String:
	return MODE_IDS[clampi(mode, 0, MODE_IDS.size() - 1)]


func mode_label() -> String:
	return MODE_LABELS[clampi(mode, 0, MODE_LABELS.size() - 1)]


func transfer_id() -> String:
	return TRANSFER_IDS[clampi(transfer_stage, 0, TRANSFER_IDS.size() - 1)]


func to_dict() -> Dictionary:
	var groups: Array = []
	for group in target_groups:
		groups.append(group.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"version": version,
		"name": name,
		"description": description,
		"author": author,
		"mode": mode_id(),
		"tags": tags,
		"duration_seconds": duration_seconds,
		"rounds": rounds,
		"arena": arena_id,
		"weapon": weapon_id,
		"seed": seed,
		"randomise_seed": randomise_seed,
		"training": {
			"skill": skill,
			"transfer_stage": transfer_id(),
			"lesson_id": lesson_id,
			"difficulty": difficulty,
		},
		"targets": groups,
		"simultaneous_targets": simultaneous_targets,
		"spawn": spawn.to_dict(),
		"lifetime": lifetime.to_dict(),
		"motion": motion.to_dict(),
		"reaction": reaction.to_dict(),
		"ammo": ammo.to_dict(),
		"rules": rules.to_dict(),
		"scoring": scoring.to_dict(),
		"success": success.to_dict(),
		"adaptive": adaptive.to_dict(),
	}


## Parses arbitrary data into a scenario definition.
## Returns {definition, errors, warnings}; `definition` is always usable when
## `errors` is empty, and the caller decides what to do with a broken file.
static func from_dict(data: Variant, source_path: String = "") -> Dictionary:
	var def := ScenarioDefinition.new()
	def.source_path = source_path
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if typeof(data) != TYPE_DICTIONARY:
		errors.append("scenario file must contain a JSON object")
		def.errors = errors
		return {"definition": def, "errors": errors, "warnings": warnings}
	var d: Dictionary = data

	var schema := _int(d.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION)
	if schema > SCHEMA_VERSION:
		errors.append("scenario schema_version %d is newer than this build understands (%d)" % [schema, SCHEMA_VERSION])

	def.id = _string(d.get("id", ""), "").strip_edges()
	if def.id.is_empty():
		errors.append("'id' is required")
	elif not _is_safe_id(def.id):
		errors.append("'id' must be lowercase letters, digits, dashes or underscores (got '%s')" % def.id)

	def.version = maxi(1, _int(d.get("version", 1), 1))
	def.name = _string(d.get("name", def.id.to_upper()), def.id.to_upper()).substr(0, 64)
	if def.name.strip_edges().is_empty():
		errors.append("'name' must not be empty")
	def.description = _string(d.get("description", ""), "").substr(0, 512)
	def.author = _string(d.get("author", ""), "").substr(0, 64)

	var mode_id := _string(d.get("mode", "custom"), "custom").to_lower()
	var mode_index := MODE_IDS.find(mode_id)
	if mode_index < 0:
		warnings.append("unknown mode '%s'; treated as CUSTOM" % mode_id)
		mode_index = Mode.CUSTOM
	def.mode = mode_index

	def.tags = _string_array(d.get("tags", []))
	def.duration_seconds = clampf(_float(d.get("duration_seconds", 60.0), 60.0), 5.0, 3600.0)
	def.rounds = clampi(_int(d.get("rounds", 0), 0), 0, 100000)
	def.seed = _int(d.get("seed", 0), 0)
	def.randomise_seed = _bool(d.get("randomise_seed", true), true)

	# Arena and weapon ids are validated against the content library by the loader;
	# here we only enforce that they cannot be paths.
	def.arena_id = _string(d.get("arena", "dojo_open"), "dojo_open")
	if not _is_safe_id(def.arena_id):
		errors.append("'arena' must be a plain id (got '%s')" % def.arena_id)
		def.arena_id = "dojo_open"
	def.weapon_id = _string(d.get("weapon", "tactical_rifle"), "tactical_rifle")
	if not _is_safe_id(def.weapon_id):
		errors.append("'weapon' must be a plain id (got '%s')" % def.weapon_id)
		def.weapon_id = "tactical_rifle"

	var training: Dictionary = _dict(d.get("training", {}))
	def.skill = _string(training.get("skill", "aim_control.precision"), "aim_control.precision")
	def.lesson_id = _string(training.get("lesson_id", ""), "")
	if def.lesson_id != "" and not _is_safe_id(def.lesson_id):
		errors.append("'lesson_id' must be a plain id")
		def.lesson_id = ""
	var stage_id := _string(training.get("transfer_stage", "isolation"), "isolation").to_lower()
	var stage_index := TRANSFER_IDS.find(stage_id)
	if stage_index < 0:
		warnings.append("unknown transfer_stage '%s'; treated as ISOLATION" % stage_id)
		stage_index = TransferStage.ISOLATION
	def.transfer_stage = stage_index
	def.difficulty = clampi(_int(training.get("difficulty", 3), 3), 1, 10)

	# Target groups
	var groups_data: Variant = d.get("targets", [])
	if typeof(groups_data) != TYPE_ARRAY or (groups_data as Array).is_empty():
		errors.append("'targets' must be a non-empty array")
	else:
		var total_weight := 0.0
		for entry in groups_data:
			var parsed := TargetGroup.from_dict(entry)
			for error in parsed["errors"]:
				errors.append("targets: %s" % error)
			for warning in parsed["warnings"]:
				warnings.append("targets: %s" % warning)
			var group: TargetGroup = parsed["group"]
			total_weight += group.weight
			def.target_groups.append(group)
		if total_weight <= 0.0:
			errors.append("target weights must sum to more than zero")

	def.simultaneous_targets = clampi(_int(d.get("simultaneous_targets", 1), 1), 1, 64)

	def.spawn = SpawnSpec.from_dict(d.get("spawn", {}))
	for error in def.spawn.errors:
		errors.append("spawn: %s" % error)
	def.lifetime = LifetimeSpec.from_dict(d.get("lifetime", {}))
	for error in def.lifetime.errors:
		errors.append("lifetime: %s" % error)
	def.motion = MotionSpec.from_dict(d.get("motion", {}))
	for error in def.motion.errors:
		errors.append("motion: %s" % error)
	def.reaction = ReactionSpec.from_dict(d.get("reaction", {}))
	for error in def.reaction.errors:
		errors.append("reaction: %s" % error)
	def.ammo = AmmoSpec.from_dict(d.get("ammo", {}))
	for error in def.ammo.errors:
		errors.append("ammo: %s" % error)
	def.rules = RuleSpec.from_dict(d.get("rules", {}))
	for error in def.rules.errors:
		errors.append("rules: %s" % error)
	def.scoring = ScoreSpec.from_dict(d.get("scoring", {}))
	for error in def.scoring.errors:
		errors.append("scoring: %s" % error)
	def.success = SuccessSpec.from_dict(d.get("success", {}))
	for error in def.success.errors:
		errors.append("success: %s" % error)
	def.adaptive = AdaptiveSpec.from_dict(d.get("adaptive", {}))
	for error in def.adaptive.errors:
		errors.append("adaptive: %s" % error)

	# Cross-field sanity checks. These are the scenarios a naive author gets wrong,
	# so they are worth explicit errors rather than silent oddness.
	if def.motion.model_id == "stationary" and def.mode in [Mode.SMOOTH_TRACKING, Mode.REACTIVE_TRACKING]:
		warnings.append("a tracking mode with stationary targets trains nothing; check 'motion.model'")
	if def.simultaneous_targets > 1 and def.mode == Mode.STATIC_PRECISION:
		warnings.append("static precision with multiple simultaneous targets behaves like target switching")
	if def.ammo.infinite and def.scoring.miss_penalty > 0.0:
		warnings.append("infinite ammo with a miss penalty rewards spamming unless the miss penalty is meaningful")
	if def.lifetime.min_seconds > def.duration_seconds and def.rounds == 0:
		warnings.append("target lifetime exceeds the scenario duration, so nothing will ever expire")

	def.errors = errors
	def.warnings = warnings
	return {"definition": def, "errors": errors, "warnings": warnings}


static func _is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for i in value.length():
		var c := value[i]
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" or c == "_"
		if not ok:
			return false
	return true


static func is_safe_id(value: String) -> bool:
	return _is_safe_id(value)


# --- coercion helpers ------------------------------------------------------

static func _dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _int(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return int(value) if value.is_valid_int() else fallback
		_:
			return fallback


static func _float(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_FLOAT:
			return value
		TYPE_INT:
			return float(value)
		TYPE_STRING:
			return float(value) if value.is_valid_float() else fallback
		_:
			return fallback


static func _bool(value: Variant, fallback: bool) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_STRING:
			return value.to_lower() in ["true", "1", "yes"]
		_:
			return fallback


static func _string(value: Variant, fallback: String) -> String:
	return value if typeof(value) == TYPE_STRING else fallback


static func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) == TYPE_STRING:
				out.append(String(item).substr(0, 32))
	return out
