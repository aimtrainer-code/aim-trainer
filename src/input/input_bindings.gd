class_name InputBindings
extends RefCounted

## Data-driven keyboard/mouse bindings.
##
## VANTA registers its own actions at boot instead of relying on `project.godot`
## input entries. Reasons: bindings become data (so they can be validated, rebound,
## exported and unit-tested), and a broken/edited settings file can never leave the
## game without a fire button — `apply_to_input_map()` always restores defaults for
## any action that fails validation.
##
## Serialised form (stored in settings):
##     {"fire": ["mouse:1"], "reload": ["key:82"], "jump": ["key:32"]}
## Supported descriptors: "mouse:<button index>" and "key:<unicode/keycode>".

const MOUSE_PREFIX := "mouse:"
const KEY_PREFIX := "key:"

## action id -> { label, category, defaults: Array[String] }
const DEFAULTS: Dictionary = {
	"fire": {"label": "Fire", "category": "Combat", "defaults": ["mouse:1"]},
	"aim": {"label": "Aim / ADS", "category": "Combat", "defaults": ["mouse:2"]},
	"reload": {"label": "Reload", "category": "Combat", "defaults": ["key:82"]},
	"move_forward": {"label": "Move forward", "category": "Movement", "defaults": ["key:87"]},
	"move_back": {"label": "Move back", "category": "Movement", "defaults": ["key:83"]},
	"move_left": {"label": "Move left", "category": "Movement", "defaults": ["key:65"]},
	"move_right": {"label": "Move right", "category": "Movement", "defaults": ["key:68"]},
	"jump": {"label": "Jump", "category": "Movement", "defaults": ["key:32"]},
	"crouch": {"label": "Crouch", "category": "Movement", "defaults": ["key:4194326"]},
	"walk": {"label": "Walk", "category": "Movement", "defaults": ["key:4194325"]},
	"restart_step": {"label": "Restart scenario", "category": "Session", "defaults": ["key:4194308"]},
	"next_step": {"label": "Next step", "category": "Session", "defaults": ["key:78"]},
	"pause": {"label": "Pause / back", "category": "Session", "defaults": ["key:4194305"]},
	"focus_mode": {"label": "Focus Mode", "category": "Interface", "defaults": ["key:70"]},
	"toggle_hud": {"label": "Cycle HUD", "category": "Interface", "defaults": ["key:72"]},
	"diagnostics": {"label": "Diagnostics overlay", "category": "Interface", "defaults": ["key:4194334"]},
	"toggle_fullscreen": {"label": "Toggle fullscreen", "category": "Interface", "defaults": ["key:4194340"]},
	"screenshot": {"label": "Screenshot", "category": "Interface", "defaults": ["key:4194344"]},
}

## Actions that must never end up unbound: if a user clears them, they are
## restored to their default so the application cannot become unusable.
const REQUIRED_ACTIONS: Array[String] = ["fire", "aim", "pause"]


static func action_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in DEFAULTS.keys():
		ids.append(String(key))
	ids.sort()
	return ids


static func label(action: String) -> String:
	var entry: Dictionary = DEFAULTS.get(action, {})
	return String(entry.get("label", action))


static func category(action: String) -> String:
	var entry: Dictionary = DEFAULTS.get(action, {})
	return String(entry.get("category", "Other"))


static func defaults_for(action: String) -> Array[String]:
	var entry: Dictionary = DEFAULTS.get(action, {})
	var out: Array[String] = []
	for d in entry.get("defaults", []):
		out.append(String(d))
	return out


## The binding table used when the user has never rebound anything.
static func default_bindings() -> Dictionary:
	var table := {}
	for key in DEFAULTS.keys():
		table[String(key)] = defaults_for(String(key))
	return table


## Validates a (possibly hand-edited) binding table.
## Returns { bindings, repairs } where `bindings` is always safe to apply.
static func sanitise(data: Variant) -> Dictionary:
	var table := default_bindings()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		return {"bindings": table, "repairs": ["bindings were not an object; defaults restored"]}

	var incoming: Dictionary = data
	for action in incoming.keys():
		var action_id := String(action)
		if not DEFAULTS.has(action_id):
			repairs.append("unknown action '%s' ignored" % action_id)
			continue
		var value: Variant = incoming[action]
		var list: Array[String] = []
		if typeof(value) == TYPE_ARRAY:
			for item in value:
				var descriptor := String(item)
				if is_valid_descriptor(descriptor):
					list.append(descriptor)
				else:
					repairs.append("invalid binding '%s' for '%s' ignored" % [descriptor, action_id])
		else:
			repairs.append("binding for '%s' was not a list; default kept" % action_id)
		if list.is_empty():
			if REQUIRED_ACTIONS.has(action_id):
				repairs.append("'%s' cannot be unbound; default restored" % action_id)
				table[action_id] = defaults_for(action_id)
			else:
				# Optional actions may legitimately be unbound.
				table[action_id] = []
			continue
		table[action_id] = list

	# Duplicate detection: the same physical input on two actions is a genuine
	# configuration error, not a security problem, so report it and keep both but
	# surface it to the user.
	for conflict in conflicts(table):
		repairs.append("'%s' is bound to both %s and %s" % [conflict["descriptor"], conflict["a"], conflict["b"]])
	return {"bindings": table, "repairs": repairs}


static func is_valid_descriptor(descriptor: String) -> bool:
	if descriptor.begins_with(MOUSE_PREFIX):
		var raw := descriptor.substr(MOUSE_PREFIX.length())
		return raw.is_valid_int() and int(raw) >= 1 and int(raw) <= 9
	if descriptor.begins_with(KEY_PREFIX):
		var raw := descriptor.substr(KEY_PREFIX.length())
		return raw.is_valid_int() and int(raw) > 0
	return false


## Returns [{descriptor, a, b}] for every input bound to more than one action.
static func conflicts(table: Dictionary) -> Array[Dictionary]:
	var seen: Dictionary = {}
	var out: Array[Dictionary] = []
	for action in table.keys():
		for descriptor in table[action]:
			var key := String(descriptor)
			if seen.has(key):
				out.append({"descriptor": key, "a": seen[key], "b": String(action)})
			else:
				seen[key] = String(action)
	return out


## Installs the table into the engine's InputMap, clearing anything previously set
## by VANTA. Unknown actions are ignored, required actions fall back to defaults.
static func apply_to_input_map(table: Dictionary) -> void:
	var sanitised: Dictionary = sanitise(table)
	var bindings: Dictionary = sanitised["bindings"]
	for action in DEFAULTS.keys():
		var action_id := String(action)
		if InputMap.has_action(action_id):
			InputMap.action_erase_events(action_id)
		else:
			InputMap.add_action(action_id)
		var list: Array = bindings.get(action_id, [])
		if list.is_empty():
			list = defaults_for(action_id)
		for descriptor in list:
			var event := event_from_descriptor(String(descriptor))
			if event != null:
				InputMap.action_add_event(action_id, event)


static func event_from_descriptor(descriptor: String) -> InputEvent:
	if descriptor.begins_with(MOUSE_PREFIX):
		var button := int(descriptor.substr(MOUSE_PREFIX.length()))
		if button < 1 or button > 9:
			return null
		var mb := InputEventMouseButton.new()
		mb.button_index = button as MouseButton
		mb.pressed = true
		return mb
	if descriptor.begins_with(KEY_PREFIX):
		var code := int(descriptor.substr(KEY_PREFIX.length()))
		if code <= 0:
			return null
		var ke := InputEventKey.new()
		ke.physical_keycode = code as Key
		ke.pressed = true
		return ke
	return null


## Human-readable form of a descriptor, e.g. "mouse:1" -> "MOUSE 1".
static func describe(descriptor: String) -> String:
	if descriptor.begins_with(MOUSE_PREFIX):
		var button := int(descriptor.substr(MOUSE_PREFIX.length()))
		match button:
			1:
				return "MOUSE LEFT"
			2:
				return "MOUSE RIGHT"
			3:
				return "MOUSE MIDDLE"
			_:
				return "MOUSE %d" % button
	if descriptor.begins_with(KEY_PREFIX):
		var code := int(descriptor.substr(KEY_PREFIX.length()))
		var text := OS.get_keycode_string(code)
		return text if text != "" else "KEY %d" % code
	return descriptor


## Builds a descriptor from a captured engine event, for the rebinding UI.
static func descriptor_from_event(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index >= 1 and mb.button_index <= 9:
			return "%s%d" % [MOUSE_PREFIX, int(mb.button_index)]
		return ""
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			var code := ke.physical_keycode if ke.physical_keycode != 0 else ke.keycode
			if code == 0:
				return ""
			return "%s%d" % [KEY_PREFIX, int(code)]
		return ""
	return ""


static func to_dict(table: Dictionary) -> Dictionary:
	return sanitise(table)["bindings"]
