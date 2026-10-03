class_name FrameDiagnostics
extends RefCounted

## Frame-time statistics, collected the honest way: by measuring the wall-clock gap
## between rendered frames inside this process.
##
## Reported metrics
##  - fps: instantaneous, averaged over the sampling window.
##  - frame_ms: current frame time.
##  - p50/p95/p99 and the *1% low* of the last N frames: the number that actually
##    describes how a competitive shooter feels. A high average FPS with a terrible
##    1% low is a bad experience, so both are always shown together.
##  - stutters: frames whose time exceeded `STUTTER_FACTOR` × the median of the
##    window. Reported as a count, not as a claim about "input lag".
##
## This class does not measure display latency, mouse latency, or the time between a
## click and a pixel. Those require external instrumentation and are marked
## UNVERIFIED in docs/PERFORMANCE.md.

const WINDOW_SIZE: int = 600  ## ~10 s at 60 fps, ~1.7 s at 360 fps
const STUTTER_FACTOR: float = 2.5

var _frame_times_ms: Array[float] = []
var _write_index: int = 0
var _count: int = 0
var _last_ticks_usec: int = 0
var _accumulator: float = 0.0
var _fps_window: float = 0.0
var _fps_frames: int = 0
var fps: float = 0.0
var frame_ms: float = 0.0
var stutters: int = 0
var _stutters_in_window: int = 0


func begin() -> void:
	_last_ticks_usec = Time.get_ticks_usec()
	_frame_times_ms.clear()
	_frame_times_ms.resize(WINDOW_SIZE)
	_write_index = 0
	_count = 0
	stutters = 0
	_stutters_in_window = 0


## Records one rendered frame. Call once per frame with the engine's `delta`.
func on_frame(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var measured_ms := float(now - _last_ticks_usec) / 1000.0
	_last_ticks_usec = now
	if measured_ms <= 0.0:
		measured_ms = delta * 1000.0
	frame_ms = measured_ms

	_frame_times_ms[_write_index] = measured_ms
	_write_index = (_write_index + 1) % WINDOW_SIZE
	_count = mini(_count + 1, WINDOW_SIZE)

	_fps_window += delta
	_fps_frames += 1
	if _fps_window >= 0.25:
		fps = float(_fps_frames) / _fps_window
		_fps_window = 0.0
		_fps_frames = 0

	# Stutter detection is relative to the running median, so it works at 60 Hz and
	# at 480 Hz without a magic millisecond threshold.
	var stats := _sorted_window()
	if stats.size() >= 30:
		var median: float = stats[stats.size() / 2]
		var threshold := median * STUTTER_FACTOR
		var current := stats[stats.size() - 1]
		if measured_ms > threshold:
			_stutters_in_window += 1
		stutters = _stutters_in_window


func _sorted_window() -> Array[float]:
	var out: Array[float] = []
	for i in _count:
		out.append(_frame_times_ms[i])
	out.sort()
	return out


func percentile(p: float) -> float:
	var stats := _sorted_window()
	if stats.is_empty():
		return 0.0
	var index := clampi(int(floor(p * float(stats.size() - 1) + 0.5)), 0, stats.size() - 1)
	return stats[index]


## "1% low" in FPS, the conventional way to express the worst frames.
func one_percent_low_fps() -> float:
	var worst_ms := percentile(0.99)
	if worst_ms <= 0.0:
		return 0.0
	return 1000.0 / worst_ms


func median_ms() -> float:
	return percentile(0.50)


func snapshot() -> Dictionary:
	return {
		"fps": fps,
		"frame_ms": frame_ms,
		"p50_ms": percentile(0.50),
		"p95_ms": percentile(0.95),
		"p99_ms": percentile(0.99),
		"fps_1pc_low": one_percent_low_fps(),
		"stutters": stutters,
		"samples": _count,
	}


func summary_line() -> String:
	var s := snapshot()
	return "frame: %6.1f fps  |  %.2f ms  |  p99 %.2f ms  |  1%% low %.0f fps  |  stutters %d" % [
		s["fps"], s["frame_ms"], s["p99_ms"], s["fps_1pc_low"], s["stutters"]
	]
