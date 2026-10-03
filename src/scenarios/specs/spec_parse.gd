class_name SpecParse
extends RefCounted

## Shared coercion helpers for scenario specs.
##
## Community content is untrusted input: every value coming out of a JSON file is
## coerced, clamped and range-checked here so the specs themselves stay readable.

static func dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func int_value(source: Dictionary, key: String, fallback: int, min_value: int, max_value: int, errors: Array[String], label: String) -> int:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	var parsed := fallback
	match typeof(raw):
		TYPE_INT:
			parsed = raw
		TYPE_FLOAT:
			parsed = int(raw)
		TYPE_STRING:
			if raw.is_valid_int():
				parsed = int(raw)
			else:
				errors.append("%s.%s must be a whole number (got \"%s\")" % [label, key, raw])
				return fallback
		_:
			errors.append("%s.%s must be a whole number" % [label, key])
			return fallback
	var clamped := clampi(parsed, min_value, max_value)
	if clamped != parsed:
		errors.append("%s.%s must be between %d and %d (got %d)" % [label, key, min_value, max_value, parsed])
	return clamped


static func float_value(source: Dictionary, key: String, fallback: float, min_value: float, max_value: float, errors: Array[String], label: String) -> float:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	var parsed := fallback
	match typeof(raw):
		TYPE_FLOAT:
			parsed = raw
		TYPE_INT:
			parsed = float(raw)
		TYPE_STRING:
			if raw.is_valid_float():
				parsed = float(raw)
			else:
				errors.append("%s.%s must be a number (got \"%s\")" % [label, key, raw])
				return fallback
		_:
			errors.append("%s.%s must be a number" % [label, key])
			return fallback
	if is_nan(parsed) or is_inf(parsed):
		errors.append("%s.%s must be a finite number" % [label, key])
		return fallback
	if parsed < min_value or parsed > max_value:
		errors.append("%s.%s must be between %s and %s (got %s)" % [label, key, str(min_value), str(max_value), str(parsed)])
		return clampf(parsed, min_value, max_value)
	return parsed


static func bool_value(source: Dictionary, key: String, fallback: bool) -> bool:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	match typeof(raw):
		TYPE_BOOL:
			return raw
		TYPE_INT:
			return raw != 0
		TYPE_STRING:
			return raw.to_lower() in ["true", "1", "yes"]
		_:
			return fallback


static func string_value(source: Dictionary, key: String, fallback: String, max_length: int = 80) -> String:
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	if typeof(raw) != TYPE_STRING:
		return fallback
	return String(raw).substr(0, max_length)


## Reads a min/max pair, ensuring min <= max.
static func range_value(source: Dictionary, key: String, fallback_min: float, fallback_max: float, min_value: float, max_value: float, errors: Array[String], label: String) -> Vector2:
	var fallback := Vector2(fallback_min, fallback_max)
	if not source.has(key):
		return fallback
	var raw: Variant = source[key]
	if typeof(raw) == TYPE_ARRAY:
		var arr: Array = raw
		if arr.size() < 2:
			errors.append("%s.%s must be [min, max]" % [label, key])
			return fallback
		var probe := {key + "_min": arr[0], key + "_max": arr[1]}
		var lo := float_value(probe, key + "_min", fallback_min, min_value, max_value, errors, label)
		var hi := float_value(probe, key + "_max", fallback_max, min_value, max_value, errors, label)
		if lo > hi:
			errors.append("%s.%s min (%s) is greater than max (%s)" % [label, key, str(lo), str(hi)])
			return Vector2(hi, hi)
		return Vector2(lo, hi)
	if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
		# A single number means a fixed value, which is the common case.
		var value := float_value(source, key, fallback_min, min_value, max_value, errors, label)
		return Vector2(value, value)
	errors.append("%s.%s must be a number or [min, max]" % [label, key])
	return fallback
