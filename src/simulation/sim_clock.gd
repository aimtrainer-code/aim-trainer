class_name SimClock
extends RefCounted

## Fixed-step simulation clock with interpolation for rendering.
##
## Why not "position = sin(time)"? Because frame-rate independence, deterministic
## replays and bounded catch-up all matter here:
##
##  - Target motion is integrated at a fixed rate (default 480 Hz), so a target's
##    trajectory is identical whether the display runs at 60, 240 or 500 Hz.
##  - Rendering uses `alpha` to interpolate between the last two simulation states,
##    so at 500 Hz the display shows smooth motion without the simulation having to
##    run 500 times a second.
##  - Hit registration resolves against **the same interpolated state that was
##    rendered**. There is therefore no discrepancy between "what I saw" and "what
##    the game tested" — the classic source of "my shot should have hit" complaints.
##
## Long frames (a window drag, a driver stall, an asset load) are caught up to a
## limit and the excess is *dropped and reported*, never silently absorbed, because a
## hidden time debt would make a scenario behave differently from its definition.

const STEP_SECONDS: float = 1.0 / 480.0
## Maximum simulated time consumed in one frame (seconds). Beyond this the clock
## drops time and increments `dropped_seconds`.
const MAX_CATCH_UP: float = 0.2

var time: float = 0.0
var steps: int = 0
var alpha: float = 0.0
var dropped_seconds: float = 0.0
var last_frame_steps: int = 0
var last_frame_dropped: float = 0.0

var _accumulator: float = 0.0


func reset() -> void:
	time = 0.0
	steps = 0
	alpha = 0.0
	dropped_seconds = 0.0
	last_frame_steps = 0
	last_frame_dropped = 0.0
	_accumulator = 0.0


## Advances the clock. Returns the number of fixed steps the caller must run.
func advance(frame_delta: float) -> int:
	var delta: float = clampf(frame_delta, 0.0, MAX_CATCH_UP)
	if frame_delta > MAX_CATCH_UP:
		last_frame_dropped = frame_delta - MAX_CATCH_UP
		dropped_seconds += last_frame_dropped
	else:
		last_frame_dropped = 0.0

	_accumulator += delta
	var step_count := 0
	while _accumulator >= STEP_SECONDS:
		_accumulator -= STEP_SECONDS
		step_count += 1
	time += float(step_count) * STEP_SECONDS
	steps += step_count
	alpha = _accumulator / STEP_SECONDS
	last_frame_steps = step_count
	return step_count


## True when the accumulator holds a partial step, i.e. the displayed position is an
## interpolation rather than an exact simulation state.
func is_interpolating() -> bool:
	return alpha > 0.0


func snapshot() -> Dictionary:
	return {
		"time": time,
		"steps": steps,
		"alpha": alpha,
		"dropped_seconds": dropped_seconds,
		"steps_per_frame": last_frame_steps,
		"step_hz": int(round(1.0 / STEP_SECONDS)),
	}
