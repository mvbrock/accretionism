class_name ErrorLog
extends Logger
## Records every error the engine or a script logs, so the runner can fail a
## test that hit one. Without this, a runtime error in a test body prints and
## the test still counts as passed.

var messages: Array[String] = []


func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	# push_error and script errors carry their text in `rationale` when there is one;
	# otherwise `code` holds it.
	messages.append(rationale if not rationale.is_empty() else code)
