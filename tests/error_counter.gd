class_name ErrorCounter
extends Logger
## Counts engine/script errors and warnings so tests fail on any runtime error.

var errors: int = 0
var warnings: int = 0
var messages: PackedStringArray = PackedStringArray()
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	var text := "%s:%d %s(): %s %s" % [file, line, function, code, rationale]
	if error_type == ERROR_TYPE_WARNING:
		warnings += 1
	else:
		errors += 1
	if messages.size() < 50:
		messages.append(("WARNING " if error_type == ERROR_TYPE_WARNING else "ERROR ") + text)
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
