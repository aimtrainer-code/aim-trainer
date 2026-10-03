class_name InputDiagnostics
extends RefCounted

## Measures what the *engine* delivers to VANTA — nothing more.
##
## Naming matters here. These numbers describe how many mouse motion events the
## engine handed over and how large their deltas were. They are **not** a
## measurement of physical latency, of the mouse's polling rate, or of click-to-
## photon delay: none of those can be observed from inside a game process without
## additional instrumentation (an LED/photodiode rig or a hardware analyser).
##
## The overlay therefore labels this panel "INPUT EVENTS (engine-side)" and
## docs/INPUT.md repeats the caveat.

const WINDOW_SECONDS: float = 1.0
const MAX_HISTORY: int = 240  ## samples of the 1-second rate

var _window_start_usec: int = 0
var _events_in_window: int = 0
var _total_events: int = 0
var events_per_second: float = 0.0
var peak_events_per_second: float = 0.0

var _absolute_motion_window: float = 0.0
var absolute_counts_per_second: float = 0.0
var peak_counts_per_second: float = 0.0

var _max_delta_in_window: float = 0.0
var max_delta_counts: float = 0.0

var _min_gap_usec: int = 0
var _max_gap_usec: int = 0
var _last_event_usec: int = 0

var _frames_without_motion: int = 0
var _frames_sampled: int = 0

var _history: Array[float] = []


func reset() -> void:
	_window_start_usec = Time.get_ticks_usec()
	_events_in_window = 0
	_total_events = 0
	events_per_second = 0.0
	peak_events_per_second = 0.0
	_absolute_motion_window = 0.0
	absolute_counts_per_second = 0.0
	peak_counts_per_second = 0.0
	_max_delta_in_window = 0.0
	max_delta_counts = 0.0
	_min_gap_usec = 0
	_max_gap_usec = 0
	_last_event_usec = 0
	_history.clear()


## Called once per delivered `InputEventMouseMotion`.
func on_motion(delta: Vector2) -> void:
	var now := Time.get_ticks_usec()
	_events_in_window += 1
	_total_events += 1
	var magnitude := delta.length()
	_absolute_motion_window += magnitude
	_max_delta_in_window = maxf(_max_delta_in_window, magnitude)
	if _last_event_usec > 0:
		var gap := now - _last_event_usec
		if _min_gap_usec == 0 or gap < _min_gap_usec:
			_min_gap_usec = gap
		_max_gap_usec = maxi(_max_gap_usec, gap)
	_last_event_usec = now
	if now - _window_start_usec >= int(WINDOW_SECONDS * 1_000_000.0):
		_close_window(now)


## Called once per rendered frame so "frames with no mouse motion" is measurable.
func on_frame(motion_delta: Vector2) -> void:
	_frames_sampled += 1
	if motion_delta.is_zero_approx():
		_frames_without_motion += 1


func _close_window(now_usec: int) -> void:
	var elapsed := maxf(float(now_usec - _window_start_usec) / 1_000_000.0, 0.0001)
	events_per_second = float(_events_in_window) / elapsed
	absolute_counts_per_second = _absolute_motion_window / elapsed
	peak_events_per_second = maxf(peak_events_per_second, events_per_second)
	peak_counts_per_second = maxf(peak_counts_per_second, absolute_counts_per_second)
	max_delta_counts = maxf(max_delta_counts, _max_delta_in_window)
	_history.append(events_per_second)
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)
	_events_in_window = 0
	_absolute_motion_window = 0.0
	_max_delta_in_window = 0.0
	_window_start_usec = now_usec


func history() -> Array[float]:
	return _history


## Snapshot for the diagnostics overlay and the benchmark tool.
func snapshot() -> Dictionary:
	return {
		"events_per_second": events_per_second,
		"peak_events_per_second": peak_events_per_second,
		"counts_per_second": absolute_counts_per_second,
		"peak_counts_per_second": peak_counts_per_second,
		"max_delta_counts": max_delta_counts,
		"total_events": _total_events,
		"min_gap_usec": _min_gap_usec,
		"max_gap_usec": _max_gap_usec,
		"frames_without_motion": _frames_without_motion,
		"frames_sampled": _frames_sampled,
	}


## One-line summary used by the F3 overlay.
func summary_line() -> String:
	return "input: %5.0f ev/s (peak %5.0f)  |  %6.0f counts/s  |  max |d| %.0f counts" % [
		events_per_second, peak_events_per_second, absolute_counts_per_second, max_delta_counts
	]
