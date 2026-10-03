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

## 48-bit mask. Chosen so that every multiplication in `_derive` stays inside the
## signed 64-bit range and cannot depend on integer-overflow behaviour, which keeps
## stream derivation identical on every platform the engine supports.
const HASH_MASK: int = 0xFFFFFFFFFFFF

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


## Derives a stable seed from the master seed and a stream name.
##
## `_hash_name` is a djb2 variant written to stay inside 48 bits so no step can
## overflow; `_derive` then mixes the master seed in with two multiplier steps.
## The result is identical on every platform and does not depend on engine
## internals such as hash randomisation.
static func _hash_name(name: String) -> int:
	var h: int = 5381
	for byte in name.to_utf8_buffer():
		h = ((h * 33) ^ int(byte)) & HASH_MASK
	return h


func _derive(name: String) -> int:
	var name_hash := _hash_name(name)
	var mixed := ((_seed & HASH_MASK) * 6364136223846793005 + name_hash) & HASH_MASK
	mixed = (mixed * 2862933555777941757 + 3037000493) & 0x7FFFFFFFFFFFFFFF
	return mixed if mixed != 0 else 0x1234567


func reset() -> void:
	_streams.clear()


# --- convenience helpers (always routed through a named stream) -------------

func roll(name: String) -> float:
	return stream(name).randf()


func roll_range(name: String, from: float, to: float) -> float:
	if is_equal_approx(from, to):
		return from
	return stream(name).randf_range(from, to)


func roll_int(name: String, from: int, to: int) -> int:
	if from == to:
		return from
	return stream(name).randi_range(from, to)


func chance(name: String, probability: float) -> bool:
	if probability <= 0.0:
		return false
	if probability >= 1.0:
		return true
	return roll(name) < probability


func pick(name: String, items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[roll_int(name, 0, items.size() - 1)]


## Picks an index from a weight array. Weights <= 0 are treated as impossible.
func pick_weighted(name: String, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var needle := roll(name) * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(0.0, float(weights[i]))
		if needle < acc:
			return i
	return weights.size() - 1


## Deterministic Fisher-Yates shuffle (returns a new array).
func shuffled(name: String, items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := roll_int(name, 0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Gaussian sample (Box-Muller) for aim-error modelling.
func gaussian(name: String, mean: float = 0.0, deviation: float = 1.0) -> float:
	var u1 := maxf(roll(name), 1e-7)
	var u2 := roll(name)
	var mag := sqrt(-2.0 * log(u1))
	return mean + deviation * mag * cos(TAU * u2)
