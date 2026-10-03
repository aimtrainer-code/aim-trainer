class_name VantaStyle
extends RefCounted

## Design tokens for VANTA.
##
## The visual language is "industrial precision instrument": flat surfaces, one
## accent, generous negative space, no ornament. Colours are defined once here and
## consumed by src/ui/theme_builder.gd and by in-arena drawing code, so a palette
## change can never leave half the product behind.
##
## Colour literals are written as float triples (not hex strings) so they can be
## used in `const` expressions.
##
## #08090B  #101318  #171B21  #F1F4F7  #929CA8  #FF3545
const BG := Color(0.031373, 0.035294, 0.043137, 1.0)
const SURFACE := Color(0.062745, 0.074510, 0.094118, 1.0)
const SURFACE_2 := Color(0.090196, 0.105882, 0.129412, 1.0)
const SURFACE_3 := Color(0.121569, 0.141176, 0.172549, 1.0)
const LINE := Color(0.164706, 0.188235, 0.223529, 1.0)
const TEXT := Color(0.945098, 0.956863, 0.968627, 1.0)
const TEXT_SECONDARY := Color(0.572549, 0.611765, 0.658824, 1.0)
const TEXT_DIM := Color(0.352941, 0.388235, 0.431373, 1.0)
const ACCENT := Color(1.0, 0.207843, 0.270588, 1.0)
const ACCENT_DARK := Color(0.529412, 0.101961, 0.137255, 1.0)
const ACCENT_SOFT := Color(1.0, 0.207843, 0.270588, 0.16)

## Status colours. Never used as the *only* signal: every place that uses them also
## carries a label, glyph or shape difference (see ACCESSIBILITY.md).
const HIT := Color(0.490196, 0.886275, 0.615686, 1.0)
const MISS := Color(1.0, 0.690196, 0.207843, 1.0)
const HEADSHOT := Color(1.0, 0.831373, 0.400000, 1.0)
const INFO := Color(0.431373, 0.658824, 1.0)
const WARN := Color(1.0, 0.690196, 0.207843, 1.0)
const OK := Color(0.490196, 0.886275, 0.615686, 1.0)
const DANGER := ACCENT

## High-contrast / colour-vision-safe alternatives. The "hit vs miss" pair is
## blue/orange, which survives protanopia, deuteranopia and tritanopia, and is
## additionally differentiated by shape in the HUD.
const CB_HIT := Color(0.301961, 0.639216, 1.0, 1.0)
const CB_MISS := Color(1.0, 0.619608, 0.172549, 1.0)
const HIGH_CONTRAST_TEXT := Color(1.0, 1.0, 1.0, 1.0)
const HIGH_CONTRAST_BG := Color(0.0, 0.0, 0.0, 1.0)

## Target palette. Index 0 is the default; the rest are selectable and the first
## four are colour-vision safe.
const TARGET_COLORS: Array[Color] = [
	Color(0.909804, 0.913725, 0.925490, 1.0),
	Color(1.0, 0.619608, 0.172549, 1.0),
	Color(0.301961, 0.639216, 1.0, 1.0),
	Color(0.490196, 0.886275, 0.615686, 1.0),
	Color(1.0, 0.831373, 0.400000, 1.0),
	Color(0.788235, 0.505882, 1.0, 1.0),
]

## Crosshair presets shipped in content/crosshairs/. Accent-adjacent colours only.
const CROSSHAIR_COLORS: Array[Color] = [
	Color(0.0, 1.0, 0.0, 1.0),
	Color(1.0, 1.0, 1.0, 1.0),
	Color(0.0, 1.0, 1.0, 1.0),
	Color(1.0, 0.207843, 0.270588, 1.0),
	Color(1.0, 0.831373, 0.400000, 1.0),
	Color(1.0, 0.0, 1.0, 1.0),
]

# --- metrics ---------------------------------------------------------------

## 4px grid. Every gap/padding token is a multiple of the base unit.
const UNIT: int = 4
const GAP_XS: int = 4
const GAP_S: int = 8
const GAP_M: int = 16
const GAP_L: int = 24
const GAP_XL: int = 40
const RADIUS: int = 2
const BORDER: int = 1
const FOCUS_RING: int = 2

# --- type scale (design pixels at 1080p, scaled by ui_scale) ---------------

const SIZE_DISPLAY: int = 44
const SIZE_H1: int = 28
const SIZE_H2: int = 20
const SIZE_BODY: int = 15
const SIZE_SMALL: int = 13
const SIZE_MICRO: int = 11

const FONT_UI := "res://assets/fonts/Inter-Regular.woff2"
const FONT_UI_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
const FONT_UI_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_UI_BOLD := "res://assets/fonts/Inter-Bold.woff2"
const FONT_MONO := "res://assets/fonts/JetBrainsMono-Regular.woff2"
const FONT_MONO_MEDIUM := "res://assets/fonts/JetBrainsMono-Medium.woff2"
const FONT_MONO_BOLD := "res://assets/fonts/JetBrainsMono-Bold.woff2"

# --- animation -------------------------------------------------------------

## Animations are short, subtle and never block input. Durations in seconds.
const T_FAST: float = 0.08
const T_BASE: float = 0.14
const T_SLOW: float = 0.22

const OPACITY_DISABLED: float = 0.38
const OPACITY_DIM: float = 0.62


## Standard surface box used by panels and cards.
static func surface_box(fill: Color = SURFACE, border_color: Color = LINE, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_color
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(radius)
	box.content_margin_left = GAP_M
	box.content_margin_right = GAP_M
	box.content_margin_top = GAP_M
	box.content_margin_bottom = GAP_M
	return box


static func flat_box(fill: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	return box


## Applies accessibility overrides (high contrast / colour vision safe) to a
## palette lookup. Kept as a pure function so tests can pin the behaviour.
static func semantic_color(kind: String, high_contrast: bool = false, color_vision_safe: bool = false) -> Color:
	match kind:
		"hit":
			if color_vision_safe:
				return CB_HIT
			return HIT
		"miss":
			if color_vision_safe:
				return CB_MISS
			return MISS
		"headshot":
			return HEADSHOT
		"warn":
			return WARN
		"ok":
			return OK
		"info":
			return INFO
		"accent":
			return ACCENT
		"score":
			if color_vision_safe:
				return CB_HIT
			return HEADSHOT
		_:
			return HIGH_CONTRAST_TEXT if high_contrast else TEXT


static func text_color(high_contrast: bool) -> Color:
	return HIGH_CONTRAST_TEXT if high_contrast else TEXT


static func background_color(high_contrast: bool) -> Color:
	return HIGH_CONTRAST_BG if high_contrast else BG


## Glyph shown next to status colours so meaning never depends on hue alone.
static func status_glyph(kind: String) -> String:
	match kind:
		"hit":
			return "[+]"
		"miss":
			return "[x]"
		"headshot":
			return "[*]"
		"ok":
			return "[ok]"
		"warn":
			return "[!]"
		"info":
			return "[i]"
		_:
			return ""
