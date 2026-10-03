class_name VantaLog
extends RefCounted

## Minimal, dependency-free logger.
##
## Design goals:
##  - Never allocate heavily on the hot path: messages are only formatted when the
##    level is enabled.
##  - Keep a bounded ring buffer so the in-app diagnostics overlay can show recent
##    warnings/errors without any file I/O in the middle of a session.
##  - Optional file sink with rotation, used when the user enables "write logs".

enum Level { ERROR = 0, WARN = 1, INFO = 2, DEBUG = 3, TRACE = 4 }

const RING_CAPACITY: int = 256
const MAX_LOG_BYTES: int = 512 * 1024
const LOG_DIR: String = "user://logs"
const LOG_FILE: String = "user://logs/vanta.log"

static var _level: Level = Level.INFO
static var _ring: Array[String] = []
static var _file_enabled: bool = false
static var _file_ready: bool = false

static var _warning_count: int = 0
static var _error_count: int = 0


static func set_level(level: Level) -> void:
	_level = level


static func get_level() -> Level:
	return _level


static func set_file_logging(enabled: bool) -> void:
	_file_enabled = enabled
	if enabled and not _file_ready:
		var dir := DirAccess.open("user://")
		if dir != null and not dir.dir_exists("logs"):
			dir.make_dir("logs")
		_file_ready = true


static func level_name(level: Level) -> String:
	match level:
		Level.ERROR:
			return "ERROR"
		Level.WARN:
			return "WARN"
		Level.INFO:
			return "INFO"
		Level.DEBUG:
			return "DEBUG"
		_:
			return "TRACE"


static func error(tag: String, message: String) -> void:
	_emit(Level.ERROR, tag, message)


static func warn(tag: String, message: String) -> void:
	_emit(Level.WARN, tag, message)


static func info(tag: String, message: String) -> void:
	_emit(Level.INFO, tag, message)


static func debug(tag: String, message: String) -> void:
	_emit(Level.DEBUG, tag, message)


static func trace(tag: String, message: String) -> void:
	_emit(Level.TRACE, tag, message)


static func recent(limit: int = 32) -> Array[String]:
	var out: Array[String] = []
	var start: int = maxi(0, _ring.size() - limit)
	for i in range(start, _ring.size()):
		out.append(_ring[i])
	return out


static func counters() -> Dictionary:
	return {"warnings": _warning_count, "errors": _error_count}


static func clear_ring() -> void:
	_ring.clear()
	_warning_count = 0
	_error_count = 0


static func _emit(level: Level, tag: String, message: String) -> void:
	if int(level) > int(_level):
		return
	var line := "[%s] %-14s %s" % [Time.get_time_string_from_system(), tag, message]
	if level == Level.ERROR:
		_error_count += 1
		push_error(line)
	elif level == Level.WARN:
		_warning_count += 1
		push_warning(line)
	else:
		print(line)
	_ring.append(line)
	if _ring.size() > RING_CAPACITY:
		_ring.remove_at(0)
	if _file_enabled:
		_write_file(line)


static func _write_file(line: String) -> void:
	if not _file_ready:
		return
	var f := FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
	if f == null:
		# File may not exist yet; fall back to creating it.
		f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if f == null:
			return
		f.store_line("VANTA %s log" % VantaVersion.string())
	f.seek_end()
	if f.get_length() > MAX_LOG_BYTES:
		# Cheap rotation: keep the newest half.
		var keep_from: int = int(f.get_length() / 2)
		f.seek(keep_from)
		var tail := f.get_buffer(f.get_length() - keep_from)
		f.close()
		var w := FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if w != null:
			w.store_buffer(tail)
			w.close()
		f = FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
		if f == null:
			return
		f.seek_end()
	var stamp := Time.get_datetime_string_from_system(false, true)
	f.store_line("%s %s" % [stamp, line])
	f.close()
