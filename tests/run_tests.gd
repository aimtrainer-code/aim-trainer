extends SceneTree

## VANTA self-test entry point.
##
##     godot --headless --path . --script res://tests/run_tests.gd [--filter substring]
##
## Runs in two phases:
##   1. Parse check — every .gd file in src/, tests/, tools/ and benchmarks/ is
##      loaded. A script that fails to parse is reported as a hard failure, which
##      means CI catches syntax and typing errors even in code no test imports.
##   2. Test execution — every `test_*.gd` file in tests/ is instantiated and each
##      `test_*` method is executed.
##
## Exit code is 0 only when everything passed.

const SCAN_DIRS: Array[String] = ["res://src", "res://tests", "res://tools", "res://benchmarks", "res://content"]
const TEST_DIR: String = "res://tests"
const RUNNING_SCRIPT: String = "res://tests/run_tests.gd"

var _filter: String = ""
var _total_assertions: int = 0
var _failures: Array[String] = []
var _cases_run: int = 0
var _cases_skipped: int = 0
var _start_usec: int = 0


func _initialize() -> void:
	_start_usec = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--filter" and i + 1 < args.size():
			_filter = args[i + 1]
		elif String(args[i]).begins_with("--filter="):
			_filter = String(args[i]).split("=")[1]

	print("")
	print("VANTA %s — self test" % VantaVersion.string())
	print("engine: %s (%s)" % [Engine.get_version_info()["string"], Engine.get_version_info()["hash"]])
	print("")

	_phase_parse_check()
	_phase_run_tests()

	var elapsed_ms := float(Time.get_ticks_usec() - _start_usec) / 1000.0
	print("")
	print("─".repeat(72))
	print("cases: %d run, %d skipped | assertions: %d | time: %.1f ms" % [
		_cases_run, _cases_skipped, _total_assertions, elapsed_ms
	])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  ✗ %s" % failure)
		quit(1)


# --- phase 1 ---------------------------------------------------------------

func _phase_parse_check() -> void:
	var scripts: Array[String] = []
	for dir in SCAN_DIRS:
		_collect_scripts(dir, scripts)
	scripts.sort()
	var autoload_paths := _autoload_scripts()
	var broken: Array[String] = []
	for path in scripts:
		var script := load(path)
		if script == null:
			broken.append("%s (load failed)" % path)
			continue
		# `load()` succeeds for a script that parses but fails to *compile* (for
		# example a numeric literal out of range). `reload()` reports that state,
		# which is how this phase catches errors in code no test happens to call.
		var gds := script as GDScript
		if gds != null and path != RUNNING_SCRIPT and not autoload_paths.has(path) and gds.reload() != OK:
			broken.append("%s (compile failed)" % path)
	if broken.is_empty():
		print("parse check: %d scripts OK" % scripts.size())
	else:
		for path in broken:
			_failures.append("parse check failed: %s" % path)


## Autoloads are instantiated before this script runs, and a script with live
## instances cannot be reloaded. Their syntax is still checked by the load() above.
func _autoload_scripts() -> Array[String]:
	var out: Array[String] = []
	for property in ProjectSettings.get_property_list():
		var name := String(property["name"])
		if name.begins_with("autoload/"):
			var value := String(ProjectSettings.get_setting(name, ""))
			out.append(value.trim_prefix("*"))
	return out


func _collect_scripts(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_scripts(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


# --- phase 2 ---------------------------------------------------------------

func _phase_run_tests() -> void:
	var files: Array[String] = []
	_collect_scripts(TEST_DIR, files)
	files.sort()
	print("")
	for file in files:
		var base := file.get_file()
		if not base.begins_with("test_") or not base.ends_with(".gd"):
			continue
		_run_case_file(file)


func _run_case_file(path: String) -> void:
	var script := load(path)
	if script == null:
		_failures.append("could not load %s" % path)
		return
	var instance: Variant = script.new()
	if not (instance is VantaTestCase):
		_failures.append("%s does not extend VantaTestCase" % path)
		return
	var test_case: VantaTestCase = instance
	var case_name := path.get_file().get_basename()
	if _filter != "" and not case_name.contains(_filter):
		return
	test_case.before_all()
	var methods: Array[String] = []
	for method in test_case.get_method_list():
		var method_name := String(method["name"])
		if method_name.begins_with("test_") and method["args"].is_empty():
			methods.append(method_name)
	methods.sort()
	var case_failures := 0
	for method_name in methods:
		test_case.current_test = "%s.%s" % [case_name, method_name]
		var before := test_case.failures.size()
		test_case.before_each()
		test_case.call(method_name)
		test_case.after_each()
		if test_case.failures.size() > before:
			case_failures += test_case.failures.size() - before
	test_case.after_all()
	_cases_run += 1
	_total_assertions += test_case.assertions
	_failures.append_array(test_case.failures)
	var status := "PASS" if case_failures == 0 else "FAIL"
	print("  [%s] %-38s %3d assertions" % [status, case_name, test_case.assertions])
