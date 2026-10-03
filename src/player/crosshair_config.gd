class_name VantaCrosshair
extends RefCounted

## Crosshair definition and validation (CROSSHAIR FORGE data model).
##
## All geometry values are in *device pixels* at 100% UI scale, so a crosshair looks
## the same on a 1080p and a 1440p display instead of growing with the UI. The
## renderer (src/player/crosshair_view.gd) is responsible for landing those pixels
## on physical pixel boundaries.

enum Style { CROSS = 0, DOT = 1, T_SHAPE = 2, CIRCLE = 3, CROSS_DOT = 4 }

const STYLE_IDS: Array[String] = ["cross", "dot", "t_shape", "circle", "cross_dot"]
const STYLE_LABELS: Array[String] = ["CROSS", "DOT", "T", "CIRCLE", "CROSS + DOT"]

const LENGTH_MIN: int = 0
const LENGTH_MAX: int = 40
const THICKNESS_MIN: int = 1
const THICKNESS_MAX: int = 8
const GAP_MIN: int = 0
const GAP_MAX: int = 40
const OUTLINE_MIN: int = 0
const OUTLINE_MAX: int = 4
const DOT_SIZE_MIN: int = 1
const DOT_SIZE_MAX: int = 8
const SPREAD_SCALE_MIN: float = 0.0
const SPREAD_SCALE_MAX: float = 3.0

var id: String = "custom"
var name: String = "CUSTOM"

var style: int = Style.CROSS
var color: Color = Color(0.0, 1.0, 0.0)
var opacity: float = 1.0
var length: int = 6
var thickness: int = 2
var gap: int = 3
var center_dot: bool = false
var dot_size: int = 2
var outline: bool = false
var outline_opacity: float = 0.55
var outline_thickness: int = 1

## Expands the gap from the weapon's current spread so the player can read
## "settled vs moving" from the crosshair instead of guessing.
var dynamic_gap: bool = true
var spread_scale: float = 1.0

## T-shape only: draw the top leg.
var t_top: bool = false


static func from_dict(data: Variant) -> Dictionary:
	var c := VantaCrosshair.new()
	var repairs: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY:
		return {"crosshair": c, "repairs": repairs}
	var d: Dictionary = data
	c.id = _str(d.get("id", "custom"), "custom")
	c.name = _str(d.get("name", "CUSTOM"), "CUSTOM").substr(0, 24)
	var style_id := _str(d.get("style", "cross"), "cross")
	var style_index := STYLE_IDS.find(style_id)
	if style_index < 0:
		repairs.append("unknown style '%s'; using CROSS" % style_id)
		style_index = Style.CROSS
	c.style = style_index
	if d.has("color"):
		c.color = _color(d["color"], c.color)
		var raw: Array = d["color"] if typeof(d["color"]) == TYPE_ARRAY else []
		if raw.size() >= 3 and _is_int_like(raw[0]) and float(raw[0]) > 1.0:
			# Values outside 0..1 are interpreted as 0..255, which is what a user
			# editing JSON by hand would expect.
			var scaled := raw.slice(0, min(4, raw.size()))
			for i in scaled.size():
				scaled[i] = clampf(float(scaled[i]) / 255.0, 0.0, 1.0)
			c.color = _color(scaled, c.color)
	c.opacity = clampf(_flt(d.get("opacity", 1.0), 1.0), 0.0, 1.0)
	c.length = clampi(_int(d.get("length", 6), 6), LENGTH_MIN, LENGTH_MAX)
	c.thickness = clampi(_int(d.get("thickness", 2), 2), THICKNESS_MIN, THICKNESS_MAX)
	c.gap = clampi(_int(d.get("gap", 3), 3), GAP_MIN, GAP_MAX)
	c.center_dot = _bool(d.get("center_dot", false), false)
	c.dot_size = clampi(_int(d.get("dot_size", 2), 2), DOT_SIZE_MIN, DOT_SIZE_MAX)
	c.outline = _bool(d.get("outline", false), false)
	c.outline_opacity = clampf(_flt(d.get("outline_opacity", 0.55), 0.55), 0.0, 1.0)
	c.outline_thickness = clampi(_int(d.get("outline_thickness", 1), 1), OUTLINE_MIN, OUTLINE_MAX)
	c.dynamic_gap = _bool(d.get("dynamic_gap", true), true)
	c.spread_scale = clampf(_flt(d.get("spread_scale", 1.0), 1.0), SPREAD_SCALE_MIN, SPREAD_SCALE_MAX)
	c.t_top = _bool(d.get("t_top", false), false)
	return {"crosshair": c, "repairs": repairs}


func to_dict() -> Dictionary:
	return {
		"schema_version": 1,
		"id": id,
		"name": name,
		"style": STYLE_IDS[clampi(style, 0, STYLE_IDS.size() - 1)],
		"color": [color.r, color.g, color.b],
		"opacity": opacity,
		"length": length,
		"thickness": thickness,
		"gap": gap,
		"center_dot": center_dot,
		"dot_size": dot_size,
		"outline": outline,
		"outline_opacity": outline_opacity,
		"outline_thickness": outline_thickness,
		"dynamic_gap": dynamic_gap,
		"spread_scale": spread_scale,
		"t_top": t_top,
	}


func duplicate_config() -> VantaCrosshair:
	return from_dict(to_dict())["crosshair"]


func style_id() -> String:
	return STYLE_IDS[clampi(style, 0, STYLE_IDS.size() - 1)]


func style_label() -> String:
	return STYLE_LABELS[clampi(style, 0, STYLE_LABELS.size() - 1)]


## Effective colour including opacity as alpha.
func draw_color() -> Color:
	var c := color
	c.a = opacity
	return c


func outline_color() -> Color:
	var c := color
	c.a = opacity * outline_opacity
	# Outline is always darker than the body so it works on light and dark arenas.
	c = c.darkened(0.85)
	c.a = opacity * outline_opacity
	return c


# --- shipped presets -------------------------------------------------------

static func presets() -> Array[VantaCrosshair]:
	var out: Array[VantaCrosshair] = []

	var classic := VantaCrosshair.new()
	classic.id = "static_classic"
	classic.name = "STATIC CLASSIC"
	classic.style = Style.CROSS
	classic.length = 5
	classic.thickness = 2
	classic.gap = 3
	classic.color = Color(0.0, 1.0, 0.0)
	out.append(classic)

	var dot := VantaCrosshair.new()
	dot.id = "micro_dot"
	dot.name = "MICRO DOT"
	dot.style = Style.DOT
	dot.center_dot = true
	dot.dot_size = 3
	dot.thickness = 1
	dot.color = Color(0.0, 1.0, 1.0)
	out.append(dot)

	var precision := VantaCrosshair.new()
	precision.id = "precision_cross"
	precision.name = "PRECISION CROSS"
	precision.style = Style.CROSS_DOT
	precision.length = 3
	precision.thickness = 1
	precision.gap = 4
	precision.center_dot = true
	precision.dot_size = 1
	precision.outline = true
	precision.color = Color(0.0, 1.0, 0.0)
	out.append(precision)

	var tactical := VantaCrosshair.new()
	tactical.id = "tactical_t"
	tactical.name = "TACTICAL T"
	tactical.style = Style.T_SHAPE
	tactical.t_top = false
	tactical.length = 6
	tactical.thickness = 2
	tactical.gap = 2
	tactical.color = Color(0.0, 1.0, 0.0)
	out.append(tactical)

	var ring := VantaCrosshair.new()
	ring.id = "tracking_ring"
	ring.name = "TRACKING RING"
	ring.style = Style.CIRCLE
	ring.thickness = 1
	ring.gap = 8
	ring.center_dot = true
	ring.dot_size = 1
	ring.color = Color(1.0, 1.0, 1.0)
	ring.dynamic_gap = true
	ring.spread_scale = 1.0
	out.append(ring)

	var white_cross := VantaCrosshair.new()
	white_cross.id = "high_contrast_white"
	white_cross.name = "HIGH CONTRAST"
	white_cross.style = Style.CROSS
	white_cross.length = 7
	white_cross.thickness = 2
	white_cross.gap = 4
	white_cross.outline = true
	white_cross.outline_opacity = 0.9
	white_cross.color = Color(1.0, 1.0, 1.0)
	out.append(white_cross)

	return out


static func preset_by_id(preset_id: String) -> VantaCrosshair:
	for p in presets():
		if p.id == preset_id:
			return p
	return presets()[0]


# --- coercion (same contract as VantaSettings: never throw) ----------------

static func _color(value: Variant, fallback: Color) -> Color:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.size() >= 3:
			var r := clampf(_flt(arr[0], fallback.r), 0.0, 1.0)
			var g := clampf(_flt(arr[1], fallback.g), 0.0, 1.0)
			var b := clampf(_flt(arr[2], fallback.b), 0.0, 1.0)
			var a := clampf(_flt(arr[3], 1.0), 0.0, 1.0) if arr.size() >= 4 else 1.0
			return Color(r, g, b, a)
	elif typeof(value) == TYPE_STRING:
		var s: String = value
		var parsed := Color.from_string(s, fallback)
		return parsed
	return fallback


static func _is_int_like(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _str(value: Variant, fallback: String) -> String:
	return value if typeof(value) == TYPE_STRING else fallback


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


static func _flt(value: Variant, fallback: float) -> float:
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
