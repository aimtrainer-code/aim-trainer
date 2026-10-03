class_name CoverBox
extends RefCounted

## One solid piece of arena geometry.
##
## Cover is an oriented box rather than an axis-aligned one because ramps and angled
## walls are exactly the geometry that makes crosshair placement interesting. The
## same instance is used for three things, which is the point:
##
##   1. the visual mesh (the builder creates a BoxMesh with this transform),
##   2. the hit test (HitRegistry resolves the nearest box),
##   3. the Rival's line-of-sight test.
##
## Because there is one source of truth, a wall that renders cannot be shot through,
## and a wall the Rival cannot see through is the same wall the player cannot.

var center: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var half_size: Vector3 = Vector3(0.5, 0.5, 0.5)
## Free-form tag used for scoring and diagnostics: "cover", "wall", "floor", "ramp".
var tag: String = "cover"
var colour: Color = Color(0.09, 0.105, 0.13)
## Purely visual: how the surface should be shaded ("matte", "grid", "emissive").
var material: String = "matte"

var _inverse: Basis = Basis.IDENTITY
var _inverse_valid: bool = false


static func make(center_position: Vector3, size: Vector3, yaw_degrees: float = 0.0, pitch_degrees: float = 0.0, tag_name: String = "cover", colour_value: Color = Color(0.09, 0.105, 0.13)) -> CoverBox:
	var box := CoverBox.new()
	box.center = center_position
	box.half_size = size * 0.5
	var rotation := Basis.IDENTITY
	if not is_zero_approx(pitch_degrees):
		rotation = rotation.rotated(Vector3.RIGHT, deg_to_rad(pitch_degrees))
	if not is_zero_approx(yaw_degrees):
		rotation = rotation.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	box.basis = rotation
	box.tag = tag_name
	box.colour = colour_value
	return box


## Ray/box test, exact for arbitrarily oriented boxes.
##
## This runs inside the hit resolver, which is called for every shot *and* for the
## tracking sample on every fixed step, so it must not do per-call work it can cache.
## The inverse of the basis is computed once per box (bases are orthonormal, so it is
## also just the transpose) instead of once per ray.
func intersect(origin: Vector3, direction: Vector3) -> float:
	var inverse := inverse_basis()
	var local_origin := inverse * (origin - center)
	var local_dir := inverse * direction
	return MathX.ray_aabb(local_origin, local_dir, Vector3.ZERO, half_size * 2.0)


## Sets the basis and invalidates the cached inverse. Use this rather than assigning
## `basis` directly when the box is already in use.
func set_basis(new_basis: Basis) -> void:
	basis = new_basis
	_inverse_valid = false


func inverse_basis() -> Basis:
	if not _inverse_valid:
		_inverse = basis.inverse()
		_inverse_valid = true
	return _inverse


func top_y() -> float:
	return center.y + half_size.y


func world_aabb() -> AABB:
	var extent := basis.x * half_size.x
	extent += basis.y * half_size.y
	extent += basis.z * half_size.z
	var abs_extent := Vector3(absf(extent.x), absf(extent.y), absf(extent.z))
	return AABB(center - abs_extent, abs_extent * 2.0)
