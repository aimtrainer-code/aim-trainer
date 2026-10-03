class_name VantaSensitivity
extends RefCounted

## Sensitivity math for VANTA.
##
## This file is pure: no engine calls, no state. It is the single place where
## "mouse counts" become "degrees", which makes it possible to unit-test every
## conversion and to display the same numbers the simulation actually uses.
##
## ---------------------------------------------------------------------------
## The model
## ---------------------------------------------------------------------------
## Every title that exposes an FPS-style sensitivity converts mouse counts into
## yaw degrees with a linear coefficient:
##
##     yaw_degrees_per_count = sensitivity * yaw_coefficient
##
## `yaw_coefficient` is the game's angular increment per count at sensitivity 1.
## For Source-engine titles (CS2, CS:GO, Apex Legends, ...) that coefficient is
## the well-known `m_yaw` default of 0.022 degrees per count. VANTA uses the same
## convention as its default so a player can carry their CS2 number across
## unchanged, which is why `VANTA sensitivity` is described as Source-compatible
## rather than "invented".
##
## Physical distances follow from DPI:
##
##     counts_per_360 = 360 / yaw_degrees_per_count
##     cm_per_360     = counts_per_360 / dpi * 2.54
##
## ---------------------------------------------------------------------------
## Honesty rules
## ---------------------------------------------------------------------------
##  - Only coefficients with a documented origin ship as presets. Each entry in
##    `GAME_PROFILES` carries `source` and `confidence` metadata that the UI
##    displays verbatim.
##  - No entry claims to reproduce a game's *feel*: rotation per count is only one
##    of several factors (FOV handling, zoom scaling, acceleration, engine input
##    path). docs/INPUT.md states this explicitly.

const YAW_COEFFICIENT_SOURCE: float = 0.022
const YAW_COEFFICIENT_VALORANT: float = 0.07

const SENS_MIN: float = 0.01
const SENS_MAX: float = 100.0
const DPI_MIN: int = 100
const DPI_MAX: int = 16000
const CM360_MIN: float = 3.0
const CM360_MAX: float = 300.0

## Conversion profiles. `coefficient` is degrees per count at sensitivity 1.
const GAME_PROFILES: Array[Dictionary] = [
	{
		"id": "vanta",
		"label": "VANTA (Source-compatible)",
		"coefficient": YAW_COEFFICIENT_SOURCE,
		"source": "Source engine default `m_yaw` (0.022), the value CS2/CS:GO use by default.",
		"confidence": "documented",
	},
	{
		"id": "source",
		"label": "Counter-Strike 2 / CS:GO",
		"coefficient": YAW_COEFFICIENT_SOURCE,
		"source": "Source engine default `m_yaw` (0.022).",
		"confidence": "documented",
	},
	{
		"id": "apex",
		"label": "Apex Legends",
		"coefficient": YAW_COEFFICIENT_SOURCE,
		"source": "Source-derived yaw coefficient (0.022). Independent verification against a running client is pending.",
		"confidence": "community",
	},
	{
		"id": "valorant",
		"label": "VALORANT",
		"coefficient": YAW_COEFFICIENT_VALORANT,
		"source": "Widely used community conversion (VALORANT ≈ 3.18 × Source sens). Not published by Riot Games; review required.",
		"confidence": "community",
	},
]


static func profile(profile_id: String) -> Dictionary:
	for p in GAME_PROFILES:
		if p["id"] == profile_id:
			return p
	return GAME_PROFILES[0]


## Degrees of yaw applied per mouse count.
static func yaw_per_count(sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	return maxf(sensitivity, 0.0) * coefficient


## Vertical sensitivity multiplier. 1.0 keeps yaw and pitch identical, which is
## what every supported title does.
static func effective_pitch_per_count(yaw: float, vertical_scale: float) -> float:
	return yaw * vertical_scale


## Counts of mouse movement required for a full 360° turn.
static func counts_per_360(sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	var yaw := yaw_per_count(sensitivity, coefficient)
	if yaw <= 0.0:
		return INF
	return 360.0 / yaw


## Physical distance (centimetres) for a full 360° turn at the given DPI.
static func cm_per_360(dpi: int, sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	if dpi <= 0:
		return INF
	return counts_per_360(sensitivity, coefficient) / float(dpi) * 2.54


## Inverse of `cm_per_360`: the sensitivity that yields the requested distance.
static func sensitivity_for_cm_per_360(dpi: int, cm360: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> float:
	if dpi <= 0 or cm360 <= 0.0:
		return SENS_MIN
	var counts := cm360 / 2.54 * float(dpi)
	return 360.0 / counts / coefficient


## Converts a sensitivity from one profile to another through cm/360, which is the
## only frame of reference that is physically meaningful.
static func convert_sensitivity(value: float, from_id: String, to_id: String) -> float:
	var from := profile(from_id)
	var to := profile(to_id)
	var from_coeff: float = float(from["coefficient"])
	var to_coeff: float = float(to["coefficient"])
	if to_coeff <= 0.0:
		return value
	return value * from_coeff / to_coeff


## Rotation applied for a mouse delta, in degrees, before any FOV/ADS scaling.
static func rotation_for_delta(delta: Vector2, yaw_deg_per_count: float, vertical_scale: float, invert_y: bool) -> Vector2:
	var yaw := -delta.x * yaw_deg_per_count
	var pitch := delta.y * yaw_deg_per_count * vertical_scale
	if invert_y:
		pitch = -pitch
	return Vector2(yaw, pitch)


## Sensitivity multiplier applied while aiming down sights / scoped.
##
## VANTA scales by the ratio of the tangents of the FOVs, which keeps the
## *apparent* target speed under the crosshair constant when zooming. This is a
## deliberate design choice, not a claim to reproduce any specific title.
static func zoom_multiplier(hip_fov: float, zoom_fov: float) -> float:
	if zoom_fov <= 0.0 or hip_fov <= 0.0:
		return 1.0
	return tan(deg_to_rad(hip_fov * 0.5)) / tan(deg_to_rad(zoom_fov * 0.5))


## Human-readable summary used by the settings screen and the release report.
static func summary(dpi: int, sensitivity: float, coefficient: float = YAW_COEFFICIENT_SOURCE) -> Dictionary:
	var yaw := yaw_per_count(sensitivity, coefficient)
	return {
		"dpi": dpi,
		"yaw_per_count": yaw,
		"counts_per_360": counts_per_360(sensitivity, coefficient),
		"cm_per_360": cm_per_360(dpi, sensitivity, coefficient),
		"inches_per_360": cm_per_360(dpi, sensitivity, coefficient) / 2.54,
	}


## Validates and clamps a sensitivity/DPI pair. Returns {ok, reason, settings}.
static func validate(dpi: int, sensitivity: float) -> Dictionary:
	if dpi < DPI_MIN or dpi > DPI_MAX:
		return {"ok": false, "reason": "DPI must be between %d and %d." % [DPI_MIN, DPI_MAX]}
	if sensitivity < SENS_MIN or sensitivity > SENS_MAX:
		return {"ok": false, "reason": "Sensitivity must be between %.2f and %.0f." % [SENS_MIN, SENS_MAX]}
	return {"ok": true, "reason": ""}
