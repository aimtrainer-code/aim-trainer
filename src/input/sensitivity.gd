class_name VantaSensitivity
extends RefCounted

## Mouse-to-rotation mathematics.
##
## This file is pure arithmetic on purpose: no `Input`, no `Node`, no engine state.
## Everything a player can configure about aim is defined by formulas that can be
## checked on paper and by test, which is the only way to make claims like "this
## sensitivity matches that game" honestly.
##
## The model
## ---------
## Rotation is linear in mouse counts:
##
##     yaw_degrees = counts * sensitivity * YAW_COEFFICIENT
##
## `YAW_COEFFICIENT` is degrees per count at sensitivity 1.0. It is the same shape the
## tactical shooters use, which is what allows a converted sensitivity to mean
## something: at equal cm/360 the same physical mouse movement produces the same
## in-game turn.
##
## What VANTA does not do: no smoothing, no acceleration, no curve, no rounding of
## accumulated counts. The only transformations are the user's own settings
## (sensitivity, vertical scale, invert Y) and the optional zoom scaling.

## Degrees of yaw per mouse count at sensitivity 1.0, for each calibration profile.
const YAW_COEFFICIENT_SOURCE: float = 0.022
const YAW_COEFFICIENT_TACTICAL_VAL: float = 0.07

const PROFILE_IDS: Array[String] = ["source", "tactical_val", "vanta"]
const PROFILE_LABELS: Array[String] = [
	"SOURCE-STYLE (0.022°/count at 1.0)",
	"TACTICAL // VAL-STYLE (0.07°/count at 1.0)",
	"VANTA NATIVE (0.022°/count at 1.0)",
]

## Pitch stops just short of vertical, like every shooter that has ever shipped.
const PITCH_LIMIT_DEGREES: float = 89.0


static func profile(profile_id: String) -> Dictionary:
	match profile_id:
		"source":
			return {"id": "source", "label": PROFILE_LABELS[0], "yaw_coefficient": YAW_COEFFICIENT_SOURCE}
		"tactical_val":
			return {"id": "tactical_val", "label": PROFILE_LABELS[1], "yaw_coefficient": YAW_COEFFICIENT_TACTICAL_VAL}
		"vanta":
			return {"id": "vanta", "label": PROFILE_LABELS[2], "yaw_coefficient": YAW_COEFFICIENT_SOURCE}
		_:
			# An unrecognised id (a file from a build with a different profile list)
			# falls back to VANTA's own profile, which is the Source coefficient under
			# a name VANTA owns. A coefficient is never invented.
			return {"id": "vanta", "label": PROFILE_LABELS[2], "yaw_coefficient": YAW_COEFFICIENT_SOURCE}


## Degrees of yaw produced by one mouse count.
static func yaw_per_count(sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	return maxf(sensitivity, 0.0) * maxf(coefficient, 0.0)


## Pitch is the same equation with the vertical scale applied, so a non-1.0 vertical
## scale is a genuine, stated deviation from a 1:1 mapping rather than a hidden tweak.
static func effective_pitch_per_count(yaw: float, vertical_scale: float) -> float:
	return yaw * clampf(vertical_scale, 0.0, 10.0)


## Mouse counts needed for a full 360° turn.
static func counts_per_360(sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	var per_count := yaw_per_count(sensitivity, coefficient)
	if per_count <= 0.0:
		return INF
	return 360.0 / per_count


## Centimetres of mouse movement for a full 360° turn at the given DPI.
static func cm_per_360(dpi: int, sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	var counts := counts_per_360(sensitivity, coefficient)
	if is_inf(counts):
		return INF
	if dpi <= 0:
		# A mouse cannot report zero DPI. Returning INF says "undefined" out loud
		# instead of producing a plausible-looking distance the player might trust.
		return INF
	return counts / float(dpi) * 2.54


## Inverse of `cm_per_360`. Used by the "convert from a known cm/360" workflow, which
## is how a player moves a sensitivity between games without guesswork.
static func sensitivity_for_cm_per_360(dpi: int, cm360: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	if cm360 <= 0.0:
		return 0.0
	if dpi <= 0:
		return INF
	var counts := cm360 / 2.54 * float(dpi)
	return counts_per_360_to_sensitivity(counts, coefficient)


static func counts_per_360_to_sensitivity(counts: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	if counts <= 0.0 or coefficient <= 0.0:
		return 0.0
	return 360.0 / (counts * coefficient)


## Converts a sensitivity from one calibration profile to another *at the same
## physical mouse movement*, i.e. preserving cm/360.
static func convert_sensitivity(value: float, from_id: String, to_id: String) -> float:
	var from_profile := profile(from_id)
	var to_profile := profile(to_id)
	var from_coefficient: float = from_profile["yaw_coefficient"]
	var to_coefficient: float = to_profile["yaw_coefficient"]
	if to_coefficient <= 0.0:
		return value
	return value * from_coefficient / to_coefficient


## The zoom multiplier for aim-down-sights.
##
## `tan(zoom/2) / tan(hip/2)` is the ratio that keeps the *on-screen* distance covered
## by a mouse movement constant, which is the textbook definition of matched-zoom
## sensitivity. It is applied to yaw only when the player enables it, because some
## players deliberately train unmatched zoom behaviour.
static func zoom_multiplier(hip_fov: float, zoom_fov: float) -> float:
	var hip := clampf(hip_fov, 1.0, 179.0)
	var zoom := clampf(zoom_fov, 1.0, 179.0)
	var hip_tan := tan(deg_to_rad(hip * 0.5))
	var zoom_tan := tan(deg_to_rad(zoom * 0.5))
	if hip_tan <= 0.0001:
		return 1.0
	return clampf(zoom_tan / hip_tan, 0.05, 20.0)


## Converts accumulated mouse counts into an angular delta in degrees.
## Returns (yaw_delta, pitch_delta) with a positive pitch meaning "look up".
static func rotation_for_delta(delta_counts: Vector2, yaw_deg_per_count: float, vertical_scale: float, invert_y: bool) -> Vector2:
	var yaw := delta_counts.x * yaw_deg_per_count
	var pitch := delta_counts.y * effective_pitch_per_count(yaw_deg_per_count, vertical_scale)
	if invert_y:
		pitch = -pitch
	# Two sign conventions, both deliberate:
	#   - Screen-space +Y is down, so a downward mouse movement decreases pitch (looks
	#     down) unless the player asked for inverted aim.
	#   - A positive yaw in Godot turns left, so moving the mouse right — which must
	#     turn the view right — is a *negative* yaw delta.
	return Vector2(-yaw, -pitch)


## Everything the sensitivity screen displays, in one dictionary.
static func summary(dpi: int, sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> Dictionary:
	var counts := counts_per_360(sensitivity, coefficient)
	var cm := cm_per_360(dpi, sensitivity, coefficient)
	return {
		"dpi": dpi,
		"sensitivity": sensitivity,
		"yaw_per_count": yaw_per_count(sensitivity, coefficient),
		"counts_per_360": counts,
		"cm_per_360": cm,
		"in_per_360": cm / 2.54,
		"degrees_per_cm": (360.0 / cm) if cm > 0.0 and not is_inf(cm) else 0.0,
	}


## Sanity checks for the values a player typed. Returns warnings rather than errors:
## an unusual configuration is the player's business, but a physically impossible one
## is worth saying out loud.
static func validate(dpi: int, sensitivity: float) -> Dictionary:
	var issues: Array[String] = []
	if dpi < 100 or dpi > 32000:
		issues.append("DPI %d is outside the range a mouse typically reports (100–32000)" % dpi)
	if sensitivity <= 0.0:
		issues.append("sensitivity must be greater than zero")
	elif sensitivity > 40.0:
		issues.append("sensitivity %.2f is very high; a whole turn takes less than 1 cm of mouse movement" % sensitivity)
	var cm := cm_per_360(dpi, sensitivity)
	if cm < 2.0 and sensitivity > 0.0:
		issues.append("%.1f cm per 360° is faster than most competitive settings (typically 15–60 cm)" % cm)
	return {"ok": issues.is_empty(), "issues": issues, "cm_per_360": cm}
