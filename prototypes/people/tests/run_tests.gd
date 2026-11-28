extends SceneTree
## Headless test runner: godot --headless --path . -s res://tests/run_tests.gd [-- <name filter>]

## Work a test starts (a timer, a signal) can log an error after the test has
## returned. The runner keeps watching for this many frames after each test.
const FRAMES_TO_WATCH_AFTER_THE_LAST_TEST := 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		filter = user_args[0]
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var error_log := ErrorLog.new()
	OS.add_logger(error_log)
	var passed := 0
	var failed := 0
	var previous_test_label := ""
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL: %s — could not load" % file)
			continue
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			if filter != "" and not (file + ":" + test_name).contains(filter):
				continue
			var test: TestCase = script.new()
			test.tree = self
			error_log.messages.clear()
			await test.call(test_name)
			test.teardown()
			await process_frame
			test.check_logged_errors(error_log.messages, previous_test_label)
			previous_test_label = file + ":" + test_name
			if test.failures.is_empty():
				passed += 1
				print("ok:   %s:%s" % [file, test_name])
			else:
				failed += 1
				for message in test.failures:
					print("FAIL: %s:%s — %s" % [file, test_name, message])
	for frame in FRAMES_TO_WATCH_AFTER_THE_LAST_TEST:
		await process_frame
	if not error_log.messages.is_empty():
		failed += 1
		for message in error_log.messages:
			print("FAIL: logged after the last test (%s) — %s" % [previous_test_label, message])
	OS.remove_logger(error_log)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(failed)
