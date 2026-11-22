extends TestCase


## The main scene, with its own frame loop stopped so each test steps it by hand.
func _main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	main.set_process(false)
	return main


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _vent(room: Room) -> void:
	for gas in room.mol:
		room.mol[gas] = 0.0


func test_command_runs_from_console() -> void:
	var main := _main()
	main.console.line_submitted.emit("door open hatch")
	var text := main.console.scrollback.get_parsed_text()
	assert_true(text.contains("> door open hatch"), "the line is echoed, got '%s'" % text)
	assert_true(text.contains("hatch: opening (6 s)"), "the response prints, got '%s'" % text)
	assert_true(main.ship.opening("hatch").state == Opening.State.OPENING, "the hatch is opening")


func test_dashboard_log_has_no_command_line() -> void:
	var main := _main()
	main.console.line_submitted.emit("door open hatch")
	main.refresh()
	var text := main.dashboard._log.get_parsed_text()
	assert_true(not text.contains("> "), "the log shows no command, got '%s'" % text)


func test_history_recall() -> void:
	var main := _main()
	main.console.input.text_submitted.emit("light off main")
	main.console.input.text_submitted.emit("light off cargo")
	assert_true(main.console.input.text == "", "submitting clears the input")
	main.console.input.gui_input.emit(_key(KEY_UP))
	assert_true(main.console.input.text == "light off cargo", "one Up recalls the second, got '%s'" % main.console.input.text)
	main.console.input.gui_input.emit(_key(KEY_UP))
	assert_true(main.console.input.text == "light off main", "another Up recalls the first, got '%s'" % main.console.input.text)
	main.console.input.gui_input.emit(_key(KEY_DOWN))
	assert_true(main.console.input.text == "light off cargo", "Down steps forward, got '%s'" % main.console.input.text)


func test_tile_shows_pressure() -> void:
	var main := _main()
	assert_true(main.dashboard.tile_label("cockpit", "pressure").text == "101.3 kPa",
			"got '%s'" % main.dashboard.tile_label("cockpit", "pressure").text)


func test_tile_shows_passengers_after_command() -> void:
	var main := _main()
	assert_true(main.dashboard.tile_label("main", "passengers").text == "passengers 1",
			"got '%s'" % main.dashboard.tile_label("main", "passengers").text)
	main.console.line_submitted.emit("passenger add main")
	main.refresh()
	assert_true(main.dashboard.tile_label("main", "passengers").text == "passengers 2",
			"got '%s'" % main.dashboard.tile_label("main", "passengers").text)


func test_reboot_overlay() -> void:
	var main := _main()
	assert_true(not main.overlay.visible, "no overlay while running")
	main.console.line_submitted.emit("computer restart")
	main.refresh()
	assert_true(main.overlay.visible, "the overlay shows while booting")
	assert_true(main.overlay.text == "COMPUTER REBOOTING", "got '%s'" % main.overlay.text)
	main.ship.advance(21.0)
	main.refresh()
	assert_true(not main.overlay.visible, "the overlay hides once the computer runs")


func test_overlay_leaves_the_console_uncovered() -> void:
	var main := _main()
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900) # the headless window is only 64x64
	await tree.process_frame
	main.console.line_submitted.emit("computer restart")
	main.refresh()
	await tree.process_frame
	assert_true(main.overlay.visible, "the overlay is up")
	assert_true(not main.overlay.get_global_rect().intersects(main.console.get_global_rect()),
			"overlay %s overlaps console %s" % [main.overlay.get_global_rect(), main.console.get_global_rect()])
	main.console.line_submitted.emit("computer restart")
	main.ship.advance(21.0)
	main.console.line_submitted.emit("debug fault computer")
	main.refresh()
	await tree.process_frame
	assert_true(main.stale_label.visible, "STALE is up")
	assert_true(not main.stale_label.get_global_rect().intersects(main.console.get_global_rect()),
			"stale label stays off the console")


func test_console_is_a_full_height_column_left_of_the_dashboard() -> void:
	var main := _main()
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900) # the headless window is only 64x64
	await tree.process_frame
	var console_rect := main.console.get_global_rect()
	var dashboard_rect := main.dashboard.get_global_rect()
	assert_true(console_rect.end.x <= dashboard_rect.position.x,
			"console %s is left of the dashboard %s" % [console_rect, dashboard_rect])
	assert_true(console_rect.size.y >= 900 - 2 * Main.WINDOW_MARGIN_PX,
			"console %s spans the window height" % console_rect)
	assert_true(dashboard_rect.end.x <= 1600, "dashboard %s stays inside the window" % dashboard_rect)


func test_stale_freeze() -> void:
	var main := _main()
	main.console.line_submitted.emit("debug fault computer")
	main.refresh()
	assert_true(main.stale_label.visible, "STALE shows in FAULT")
	assert_true(main.stale_label.text == "STALE", "got '%s'" % main.stale_label.text)
	var label := main.dashboard.tile_label("cockpit", "pressure")
	var before := label.text
	_vent(main.ship.room("cockpit"))
	main.refresh()
	assert_true(label.text == before, "the panels stay as they were, got '%s'" % label.text)
	main.console.line_submitted.emit("computer restart")
	main.ship.advance(21.0)
	_vent(main.ship.room("cockpit"))
	main.refresh()
	assert_true(not main.stale_label.visible, "STALE hides after the restart")
	assert_true(label.text == "0.0 kPa", "the panels redraw, got '%s'" % label.text)


func test_space_pauses_only_without_console_focus() -> void:
	var main := _main()
	main.console.input.grab_focus()
	main._input(_key(KEY_SPACE))
	assert_true(not main.clock.paused, "Space with the console focused leaves the clock running")
	main.console.input.release_focus()
	main._input(_key(KEY_SPACE))
	assert_true(main.clock.paused, "Space without focus pauses")


func test_clock_bar_buttons() -> void:
	var main := _main()
	main.dashboard.pause_pressed.emit()
	assert_true(main.clock.paused, "Pause pauses")
	main.dashboard.speed_pressed.emit()
	assert_true(main.clock.speed_index == 1, "Speed steps to 10x")
	main.set_process(true)
	main.clock.paused = false
	main.clock.speed_index = 1
	main._process(1.0)
	main.set_process(false)
	assert_near(main.ship.time_s, 10.0, 1e-6, "_process advances the ship by sim time")


func _type(main: Main, text: String) -> void:
	for character in text:
		var event := InputEventKey.new()
		event.keycode = character.unicode_at(0) as Key
		event.unicode = character.unicode_at(0)
		event.pressed = true
		main.get_viewport().push_input(event)


func test_typing_continues_after_enter() -> void:
	var main := _main()
	main.console.input.grab_focus()
	_type(main, "help")
	main.get_viewport().push_input(_key(KEY_ENTER))
	_type(main, "xy")
	assert_true(main.console.input.text == "xy", "typing after Enter reaches the input, got '%s'" % main.console.input.text)


func test_banners_are_inside_the_stage() -> void:
	var main := _main()
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900) # the headless window is only 64x64
	await tree.process_frame
	var stage := main.stale_label.get_parent() as Control
	main.stale_label.visible = true
	await tree.process_frame
	assert_true(stage.get_global_rect().encloses(main.stale_label.get_global_rect()),
			"STALE %s sits inside the stage %s" % [main.stale_label.get_global_rect(), stage.get_global_rect()])
	assert_true(main.overlay.get_global_rect().position.y >= main.dashboard.clock_bar.get_global_rect().end.y,
			"the overlay %s leaves the clock bar %s uncovered" % [main.overlay.get_global_rect(), main.dashboard.clock_bar.get_global_rect()])


func test_scaled_window_size_doubles_on_retina() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(4000, 3000))
	assert_true(size == Vector2i(3200, 1800), "2x scale doubles the window (got %s)" % size)


func test_scaled_window_size_fits_the_screen() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(3024, 1890))
	assert_true(size.x <= 3024 and size.y <= 1890, "fits the usable screen (got %s)" % size)


func test_clock_bar_button_text() -> void:
	var main := _main()
	main.clock.speed_index = 2
	main.clock.paused = false
	main.refresh()
	assert_true(main.dashboard.pause_button.text == "Pause", "playing offers Pause, got '%s'" % main.dashboard.pause_button.text)
	assert_true(main.dashboard.speed_button.text == "Speed: 100×", "speed shows 100×, got '%s'" % main.dashboard.speed_button.text)
	main.clock.paused = true
	main.refresh()
	assert_true(main.dashboard.pause_button.text == "Play", "paused offers Play, got '%s'" % main.dashboard.pause_button.text)


func _main_with_broken_data() -> Main:
	var path := "user://broken_ship.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Main.SHIP_PATH))
	data.rooms[0].volume_m3 = 0
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	expect_error("Bad ship data: room 'cockpit' has volume")
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.data_path = path
	own(main)
	DirAccess.remove_absolute(path)
	return main


func test_bad_data_file_shows_its_problem() -> void:
	var main := _main_with_broken_data()
	assert_true(main.ship == null, "no ship is built")
	assert_true(main.error_label != null, "the message label exists")
	if main.error_label == null:
		return
	assert_true(main.error_label.visible, "the message is up")
	assert_true(main.error_label.text.begins_with("Could not load user://broken_ship.json: "),
			"names the file, got '%s'" % main.error_label.text)
	assert_true(main.error_label.text == "Could not load user://broken_ship.json: room 'cockpit' has volume 0.0 m3, which must be above 0",
			"names the file and the bare problem, got '%s'" % main.error_label.text)


func test_missing_data_file_names_its_path_once() -> void:
	expect_error("Ship file 'user://missing_ship.json' is missing or empty")
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.data_path = "user://missing_ship.json"
	own(main)
	assert_true(main.error_label != null, "the message label exists")
	if main.error_label == null:
		return
	assert_true(main.error_label.text == "Could not load user://missing_ship.json: file is missing or empty",
			"got '%s'" % main.error_label.text)


func test_bad_data_file_runs_no_sim() -> void:
	var main := _main_with_broken_data()
	assert_true(not main.is_processing(), "the frame loop is off")
	main._input(_key(KEY_SPACE))
