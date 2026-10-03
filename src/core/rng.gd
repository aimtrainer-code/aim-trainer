class_name VantaRng
extends RefCounted

## Deterministic random number source with named streams.
##
## Scenario replayability matters: a seed must reproduce the same spawn sequence,
## target dimensions and motion parameters. At the same time, changing how many
## random numbers the *motion* system consumes must not shuffle the *spawn*
## sequence, otherwise adding a feature would invalidate every historical run.
##
## Each named stream (spawn / motion / lifetime / rival / ...) is therefore an
## independent RandomNumberGenerator derived from the master seed and the stream
## name, so streams cannot interfere with one another.
##
## The implementation intentionally avoids engine globals (`randi()`, `randf()`),
## which are shared process-wide state and would break determinism as soon as two
## systems run in the same frame.

var _seed: int = 0
var _streams: Dictionary = {}


func _init(master_seed: int = 0) -> void:
	_seed = master_seed


## Master seed. Exposed so a session can be recorded and replayed.
var seed: int:
	get:
		return _seed


func stream(name: String) -> RandomNumberGenerator:
	var existing: RandomNumberGenerator = _streams.get(name)
	if existing != null:
		return existing
	var rng := RandomNumberGenerator.new()
	rng.seed = _derive(name)
	_streams[name] = rng
	return rng


## Derives a stable 64-bit seed from the master seed and a stream name using
## FNV-1a. Deterministic across platforms and engine versions.
func _derive(name: String) -> int:
	var hash_value: int = -3750763034362895579  # FNV-1a 64 offset basis (as signed int64)
	for byte in name.to_utf8_buffer():
		hash_value = hash_value ^ int(byte)
		hash_value = (hash_value * 1099511628211) & 0xFFFFFFFFFFFFFFFF
		# Convert to signed 64-bit range with the same wrap-around semantics the
		# engine uses for int seeds.
		if hash_value >= 0x8000000000000000:
			hash_value -= 0x10000000000000000
	var mixed: int = hash_value ^ (_seed * 0x9E3779B97F4A7C15)
	if mixed >= 0x8000000000000000:
		mixed -= 0x10000000000000000
	return mixed


func reset() -> void:
	_streams.clear()


# --- convenience helpers (always routed through a named stream) -------------

func randf(name: String) -> float:
	return stream(name).randf()


func randf_range(name: String, from: float, to: float) -> float:
	if is_equal_approx(from, to):
		return from
	return stream(name).randf_range(from, to)


func randi_range(name: String, from: int, to: int) -> int:
	if from == to:
		return from
	return stream(name).randi_range(from, to)


func chance(name: String, probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return randf(name) < probability


func pick(name: String, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[randi_range(name, 0, items.size() - 1)]


## Picks an index from a weight array. Weights <= 0 are treated as impossible.
func pick_weighted(name: String, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var roll := randf(name) * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if roll < acc:
			return i
	return weights.size() - 1


## Deterministic Fisher-Yates shuffle (returns a new array).
func shuffled(name: String, items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := randi_range(name, 0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Gaussian sample (Box-Muller) for aim-error modelling.
func gaussian(name: String, mean: float = 0.0, deviation: float = 1.0) -> float:
	var u1 := maxf(randf(name), 1e-7)
	var u2 := randf(name)
	var mag := sqrt(-2.0 * log(u1))
	return mean + deviation * mag * cos(TAU * u2)
