class_name CrosshairGeometry
extends RefCounted

## Pure crosshair geometry.
##
## Given a crosshair configuration, the canvas→device scale of the active viewport
## and the weapon's current spread, this produces a list of `CrosshairPart`s in
## **device pixels**. The renderer only has to map them back into canvas space.
##
## Keeping this pure is what makes "the crosshair stays crisp" testable: tests
## assert that every produced rectangle is integral in device space, that symmetry
## holds exactly, and that the crosshair centre coincides with the optical centre.


## Builds the crosshair parts.
##
## center_device:  optical centre of the viewport, in device pixels. Snapped to a
##                 whole pixel so the crosshair has a real centre pixel.
## device_scale:   canvas-units → device-pixels factor of the active viewport.
## spread_device:  extra half-gap, in device pixels, derived from weapon spread.
static func build(config: VantaCrosshair, center_device: Vector2, device_scale: float = 1.0, spread_device: float = 0.0) -> Array[CrosshairPart]:
	var out: Array[CrosshairPart] = []
	if config == null:
		return out

	var scale: float = device_scale if device_scale > 0.0 else 1.0
	var thickness: int = maxi(1, roundi(float(config.thickness) * scale))
	var length: int = maxi(0, roundi(float(config.length) * scale))
	var gap: int = maxi(0, roundi(float(config.gap) * scale))
	if config.dynamic_gap:
		gap += maxi(0, roundi(spread_device * maxf(0.0, config.spread_scale)))
	var outline_w: int = maxi(0, roundi(float(config.outline_thickness) * scale)) if config.outline else 0
	var wants_dot: bool = config.center_dot or config.style == VantaCrosshair.Style.DOT
	var dot: int = maxi(1, roundi(float(config.dot_size) * scale)) if wants_dot else 0

	var center: Vector2 = Vector2(roundf(center_device.x), roundf(center_device.y))

	var body_parts: Array[CrosshairPart] = []

	# --- legs --------------------------------------------------------------
	var draw_left := true
	var draw_right := true
	var draw_top := true
	var draw_bottom := true
	match config.style:
		VantaCrosshair.Style.DOT:
			draw_left = false
			draw_right = false
			draw_top = false
			draw_bottom = false
		VantaCrosshair.Style.T_SHAPE:
			draw_top = config.t_top
		_:
			pass

	# Half-thickness is kept as an explicit float so the parser never has to infer a
	# type from a Variant-returning cast.
	var half_thickness: float = 0.5 * float(thickness)
	var y_center: float = center.y - floorf(half_thickness)
	var x_center: float = center.x - floorf(half_thickness)

	if length > 0:
		if draw_left:
			body_parts.append(CrosshairPart.new(Rect2(center.x - float(gap + length), y_center, float(length), float(thickness))))
		if draw_right:
			body_parts.append(CrosshairPart.new(Rect2(center.x + float(gap), y_center, float(length), float(thickness))))
		if draw_top:
			body_parts.append(CrosshairPart.new(Rect2(x_center, center.y - float(gap + length), float(thickness), float(length))))
		if draw_bottom:
			body_parts.append(CrosshairPart.new(Rect2(x_center, center.y + float(gap), float(thickness), float(length))))

	if config.style == VantaCrosshair.Style.CIRCLE:
		var radius: float = float(gap) + float(maxi(2, length)) * 0.5
		var outer: float = radius + float(thickness) * 0.5
		body_parts.append(CrosshairPart.make_arc(Rect2(center.x - outer, center.y - outer, outer * 2.0, outer * 2.0)))

	if dot > 0:
		var dot_offset: float = floorf(0.5 * float(dot))
		body_parts.append(CrosshairPart.new(Rect2(center.x - dot_offset, center.y - dot_offset, float(dot), float(dot))))

	# --- outline first so the body draws on top ----------------------------
	if outline_w > 0:
		for part in body_parts:
			out.append(part.grown(outline_w))
	out.append_array(body_parts)
	return out


## Bounding radius of the crosshair in device pixels. Used by the HUD to avoid
## overlapping the crosshair with markers, and by tests.
static func visual_radius(config: VantaCrosshair, device_scale: float = 1.0) -> float:
	var parts := build(config, Vector2.ZERO, device_scale, 0.0)
	var radius := 0.0
	for part in parts:
		var half := part.rect.size * 0.5
		radius = maxf(radius, maxf(half.x, half.y) + maxf(absf(part.rect.position.x), absf(part.rect.position.y)))
	return radius


## Device pixels per canvas unit for a Control, so the crosshair can compensate for
## UI scaling and resolution. Returns 1.0 when the transform is unusable (headless).
static func device_scale_for(control: Control) -> float:
	if control == null or not control.is_inside_tree():
		return 1.0
	var viewport := control.get_viewport()
	if viewport == null:
		return 1.0
	var transform := viewport.get_screen_transform()
	var scale := transform.get_scale()
	if scale.x <= 0.0 or is_nan(scale.x):
		return 1.0
	return scale.x
