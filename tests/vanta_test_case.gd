class_name VantaTestCase
extends RefCounted

## Minimal test base class for VANTA's self-test suite.
##
## Deliberately dependency-free: the project must be testable with nothing but a
## Godot binary and the repository, in CI and on a contributor's machine, without
## downloading a test framework.
##
## Usage:
##     class_name TestSomething extends VantaTestCase
##     func test_addition() -> void:
##         assert_eq(2 + 2, 4, "arithmetic still works")
##
## Every `test_*` method is executed by tests/run_tests.gd. Failures are collected
## rather than thrown, so one broken assertion does not hide the rest of the file.

var failures: Array[String] = []
var assertions: int = 0
var current_test: String = ""

## Set to true to skip this case entirely (with a printed reason).
var skip: bool = false
var skip_reason: String = ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- assertions ------------------------------------------------------------

func assert_true(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		_fail(message, "expected true, got false")


func assert_false(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		_fail(message, "expected false, got true")


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if typeof(actual) != typeof(expected):
		if not _loose_equal(actual, expected):
			_fail(message, "expected %s (%s), got %s (%s)" % [
				str(expected), type_string(typeof(expected)), str(actual), type_string(typeof(actual))
			])
		return
	if actual != expected:
		_fail(message, "expected %s, got %s" % [str(expected), str(actual)])


func assert_not_eq(actual: Variant, unexpected: Variant, message: String) -> void:
	assertions += 1
	if actual == unexpected:
		_fail(message, "did not expect %s" % str(unexpected))


func assert_almost_eq(actual: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_fail(message, "expected %.6f ± %.6f, got %.6f" % [expected, tolerance, actual])


func assert_less(actual: float, limit: float, message: String) -> void:
	assertions += 1
	if actual >= limit:
		_fail(message, "expected < %.6f, got %.6f" % [limit, actual])


func assert_greater(actual: float, limit: float, message: String) -> void:
	assertions += 1
	if actual <= limit:
		_fail(message, "expected > %.6f, got %.6f" % [limit, actual])


func assert_between(actual: float, low: float, high: float, message: String) -> void:
	assertions += 1
	if actual < low or actual > high:
		_fail(message, "expected within [%.4f, %.4f], got %.4f" % [low, high, actual])


func assert_not_null(value: Variant, message: String) -> void:
	assertions += 1
	if value == null:
		_fail(message, "expected a value, got null")


func assert_null(value: Variant, message: String) -> void:
	assertions += 1
	if value != null:
		_fail(message, "expected null, got %s" % str(value))


func assert_contains(haystack: Array, needle: Variant, message: String) -> void:
	assertions += 1
	if not haystack.has(needle):
		_fail(message, "%s does not contain %s" % [str(haystack), str(needle)])


func assert_string_contains(haystack: String, needle: String, message: String) -> void:
	assertions += 1
	if not haystack.contains(needle):
		_fail(message, "\"%s\" does not contain \"%s\"" % [haystack, needle])


## Unconditional failure — useful inside a loop that found bad data.
func assert_fail(message: String) -> void:
	assertions += 1
	_fail(message, "explicit failure")


func _fail(message: String, detail: String) -> void:
	failures.append("%s :: %s (%s)" % [current_test, message, detail])


func _loose_equal(a: Variant, b: Variant) -> bool:
	# Int/float equivalence is common in JSON-loaded data.
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return is_equal_approx(float(a), float(b))
	if typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING:
		return str(a) == str(b)
	return false
