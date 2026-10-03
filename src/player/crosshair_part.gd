class_name CrosshairPart
extends RefCounted

## One primitive of a rendered crosshair, expressed in **device pixels**.
##
## `rect` is either a filled rectangle (legs, centre dot) or the bounding box of an
## arc when `radian_range` is set (CIRCLE style). Keeping the unit explicit — device
## pixels, not canvas units — is what allows tests to prove the crosshair lands on
## whole pixels regardless of resolution or UI scale.

var rect: Rect2 = Rect2()
var color_role: String = ROLE_BODY
var radian_range: Vector2 = Vector2.ZERO  ## ZERO = filled rectangle
var is_arc: bool = false

const ROLE_BODY: String = "body"
const ROLE_OUTLINE: String = "outline"


func _init(p_rect: Rect2 = Rect2(), p_role: String = ROLE_BODY) -> void:
	rect = p_rect
	color_role = p_role


static func make_arc(bounds: Rect2, role: String = ROLE_BODY) -> CrosshairPart:
	var part := CrosshairPart.new(bounds, role)
	part.is_arc = true
	part.radian_range = Vector2(0.0, TAU)
	return part


## Integer-aligned? Used by tests and by the renderer as a safety net.
func is_pixel_aligned() -> bool:
	return is_equal_approx(rect.position.x, round(rect.position.x)) \
		and is_equal_approx(rect.position.y, round(rect.position.y)) \
		and is_equal_approx(rect.size.x, round(rect.size.x)) \
		and is_equal_approx(rect.size.y, round(rect.size.y))


func grown(amount: int) -> CrosshairPart:
	var grown_rect := Rect2(
		rect.position - Vector2(amount, amount),
		rect.size + Vector2(amount * 2.0, amount * 2.0)
	)
	var part := CrosshairPart.new(grown_rect, ROLE_OUTLINE)
	part.is_arc = is_arc
	part.radian_range = radian_range
	return part


func center() -> Vector2:
	return rect.position + rect.size * 0.5
