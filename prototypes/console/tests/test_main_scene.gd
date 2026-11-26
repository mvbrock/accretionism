extends TestCase


## The main scene connected to `ship_name`, with its own frame loop stopped so each test steps it by hand.
func _main(ship_name := "kestrel") -> Main:
	var main := _disconnected_main()
	main.console.line_submitted.emit("ships connect " + ship_name)
	return main


func _disconnected_main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	main.set_process(false)
	return main


## Writes `data` as the only ship file in a fresh user:// folder and returns the folder.
func _ships_dir_with(file_name: String, data: Dictionary) -> String:
	var dir := "user://test_ships"
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return dir


func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func test_starts_disconnected() -> void:
	var main := _disconnected_main()
	assert_true(main.ship == null, "no ship is connected")
	assert_true(main.dashboard == null, "no dashboard is built")
	assert_true(main.no_ship_label.visible, "NO SHIP CONNECTED shows")
	var text := main.console.scrollback.get_parsed_text()
	assert_true(text.contains(Main.GREETING), "the console says how to connect, got '%s'" % text)


func test_connect_shows_that_ships_dashboard() -> void:
	var main := _disconnected_main()
	main.console.line_submitted.emit("ships connect wren")
	assert_true(main.ship == main.fleet.ships.wren, "wren is connected")
	assert_true(not main.no_ship_label.visible, "the placeholder hides")
	assert_true(main.dashboard != null and main.dashboard.tile("treehouse") != null, "the dashboard shows wren's rooms")
	assert_true(main.console.scrollback.get_parsed_text().contains("connected to wren"), "the response prints")


func test_disconnect_takes_the_dashboard_away() -> void:
	var main := _main()
	main.console.line_submitted.emit("disconnect")
	assert_true(main.ship == null, "no ship is connected")
	assert_true(main.dashboard == null, "the dashboard is gone")
	assert_true(main.no_ship_label.visible, "NO SHIP CONNECTED shows")


func test_disconnect_clears_the_reboot_overlay() -> void:
	var main := _main()
	main.console.line_submitted.emit("computer restart")
	assert_true(main.overlay.visible, "the overlay is up while booting")
	main.console.line_submitted.emit("disconnect")
	assert_true(not main.overlay.visible and not main.stale_label.visible, "no banner covers the placeholder")


func test_reconnecting_to_another_ship_rebuilds_the_dashboard() -> void:
	var main := _main()
	main.console.line_submitted.emit("disconnect")
	main.console.line_submitted.emit("ships connect wren")
	main.refresh()
	assert_true(main.dashboard.selected_room == "treehouse", "the ROOM panel starts on wren's first room, got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.get_index() == 0, "the dashboard sits under the banners")


func test_every_ship_runs_while_disconnected() -> void:
	var main := _disconnected_main()
	main.set_process(true)
	main.clock.paused = false
	main._process(1.0)
	main.set_process(false)
	for ship_name in main.fleet.ships:
		assert_near(main.fleet.ships[ship_name].time_s, 1.0, 1e-6, "%s advances with no connection" % ship_name)


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


func _click(tile: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	tile.gui_input.emit(event)


func _panel_text(main: Main, key: String) -> String:
	return main.dashboard.room_label(key).text


func _label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for child in node.find_children("*", "Label", true, false):
		texts.append((child as Label).text)
	return texts


func test_tiles_show_only_the_room_name() -> void:
	var main := _main()
	for room in main.ship.rooms:
		var texts := _label_texts(main.dashboard.tile(room.id))
		assert_true(texts == [room.id.to_upper()], "%s tile text is just its name, got %s" % [room.id, texts])


func test_tile_border_is_the_rooms_status_colour() -> void:
	var main := _main()
	var style := main.dashboard.tile(("cargo")).get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(style.border_color == DashboardView.GREEN, "nominal cargo is green, got %s" % style.border_color)
	_vent(main.ship.room("cargo"))
	main.refresh()
	assert_true(style.border_color == DashboardView.RED, "vented cargo is red, got %s" % style.border_color)


func test_room_panel_starts_on_the_first_room() -> void:
	var main := _main()
	assert_true(main.dashboard.room_heading.text == "COCKPIT", "got '%s'" % main.dashboard.room_heading.text)
	assert_true(_panel_text(main, "pressure") == "101.3 kPa", "got '%s'" % _panel_text(main, "pressure"))


func test_room_panel_is_the_left_most_panel() -> void:
	var main := _main()
	var heading_x := main.dashboard.room_heading.get_global_rect().position.x
	assert_true(main.dashboard.room_heading.get_parent().get_index() == 0, "ROOM is the first child of the panels row")
	assert_true(heading_x <= main.dashboard.panels.get_global_rect().position.x + 1.0, "ROOM sits at the row's left edge")


func test_clicking_a_tile_shows_that_room() -> void:
	var main := _main()
	_click(main.dashboard.tile("main"))
	assert_true(main.dashboard.room_heading.text == "MAIN", "got '%s'" % main.dashboard.room_heading.text)
	assert_true(_panel_text(main, "pressure") == "101.3 kPa", "got '%s'" % _panel_text(main, "pressure"))
	_vent(main.ship.room("main"))
	main.refresh()
	assert_true(_panel_text(main, "o2") == "O₂ —", "vacuum reads — in the panel, got '%s'" % _panel_text(main, "o2"))


func test_clicking_the_selected_room_keeps_it_selected() -> void:
	var main := _main()
	_click(main.dashboard.tile("main"))
	_click(main.dashboard.tile("main"))
	assert_true(main.dashboard.selected_room == "main", "got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.room_heading.text == "MAIN", "the panel still shows MAIN")


func test_one_room_is_highlighted() -> void:
	var main := _main()
	_click(main.dashboard.tile("cargo"))
	var widths := {}
	for room in main.ship.rooms:
		widths[room.id] = (main.dashboard.tile(room.id).get_theme_stylebox("panel") as StyleBoxFlat).border_width_left
	assert_true(widths.cargo > widths.cockpit and widths.cockpit == widths.main,
			"only the selected tile has the thicker border, got %s" % widths)


func test_panel_shows_passengers_after_command() -> void:
	var main := _main()
	main.dashboard.select_room("cargo")
	main.refresh()
	assert_true(_panel_text(main, "passengers") == "passengers 0", "got '%s'" % _panel_text(main, "passengers"))
	main.console.line_submitted.emit("passenger add cargo")
	main.refresh()
	assert_true(_panel_text(main, "passengers") == "passengers 1", "got '%s'" % _panel_text(main, "passengers"))


func test_clicking_while_the_computer_is_down_does_nothing() -> void:
	var main := _main()
	main.console.line_submitted.emit("debug fault computer")
	main.refresh()
	_click(main.dashboard.tile("main"))
	assert_true(main.dashboard.selected_room == "cockpit", "FAULT: the selection is unchanged, got '%s'" % main.dashboard.selected_room)
	main.console.line_submitted.emit("computer restart")
	main.refresh()
	_click(main.dashboard.tile("main"))
	assert_true(main.dashboard.selected_room == "cockpit", "BOOTING: the selection is unchanged, got '%s'" % main.dashboard.selected_room)
	main.ship.advance(21.0)
	main.refresh()
	_click(main.dashboard.tile("main"))
	assert_true(main.dashboard.selected_room == "main", "RUN: the click selects, got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.room_heading.text == "MAIN", "the panel shows MAIN")


func test_capture_selects_cargo() -> void:
	var main := _main()
	Main.CaptureScript.new(main, "user://capture_test")
	main.refresh()
	assert_true(main.dashboard.room_heading.text == "CARGO", "got '%s'" % main.dashboard.room_heading.text)


func _fits(main: Main) -> void:
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = Vector2(1600, 900)
	await tree.process_frame
	await tree.process_frame
	var bounds := main.dashboard.get_global_rect()
	for part in [main.dashboard.schematic, main.dashboard.panels]:
		assert_true(bounds.encloses(part.get_global_rect()), "%s stays inside the dashboard %s" % [part.get_global_rect(), bounds])


func test_three_rooms_fit_the_dashboard() -> void:
	await _fits(_main())


func test_four_rooms_fit_the_dashboard() -> void:
	await _fits(_main("wren"))


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


func test_overlay_and_stale_cover_only_the_dashboard() -> void:
	var main := _main()
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900) # the headless window is only 64x64
	await tree.process_frame
	main.console.line_submitted.emit("computer restart")
	main.refresh()
	await tree.process_frame
	assert_true(main.overlay.visible, "the overlay is up")
	assert_true(main.dashboard.get_global_rect().encloses(main.overlay.get_global_rect()),
			"overlay %s stays inside the dashboard %s" % [main.overlay.get_global_rect(), main.dashboard.get_global_rect()])
	assert_true(not main.overlay.get_global_rect().intersects(main.console.get_global_rect()),
			"overlay %s overlaps console %s" % [main.overlay.get_global_rect(), main.console.get_global_rect()])
	main.console.line_submitted.emit("computer restart")
	main.ship.advance(21.0)
	main.console.line_submitted.emit("debug fault computer")
	main.refresh()
	await tree.process_frame
	assert_true(main.stale_label.visible, "STALE is up")
	assert_true(main.dashboard.get_global_rect().encloses(main.stale_label.get_global_rect()),
			"STALE stays inside the dashboard")
	assert_true(not main.stale_label.get_global_rect().intersects(main.console.get_global_rect()),
			"stale label stays off the console")


func test_console_is_a_full_height_column_left_of_the_dashboard() -> void:
	var main := _main()
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900) # the headless window is only 64x64
	await tree.process_frame
	var console_rect := main.console_panel.get_global_rect()
	var dashboard_rect := main.dashboard.get_global_rect()
	assert_true(console_rect.end.x <= dashboard_rect.position.x,
			"console %s is left of the dashboard %s" % [console_rect, dashboard_rect])
	assert_true(console_rect.size.y >= 900 - 2 * Main.WINDOW_MARGIN_PX,
			"console %s spans the window height" % console_rect)
	var share: float = console_rect.size.x / 1600.0
	assert_true(absf(share - 0.40) <= 0.03, "console panel takes about 40%% of the width, got %.3f" % share)
	assert_true(dashboard_rect.end.x <= 1600, "dashboard %s stays inside the window" % dashboard_rect)


func test_stale_freeze() -> void:
	var main := _main()
	main.console.line_submitted.emit("debug fault computer")
	main.refresh()
	assert_true(main.stale_label.visible, "STALE shows in FAULT")
	assert_true(main.stale_label.text == "STALE", "got '%s'" % main.stale_label.text)
	var label := main.dashboard.room_label("pressure")
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
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ShipFixture.KESTREL_PATH))
	data.rooms[0].volume_m3 = 0
	var dir := _ships_dir_with("broken.json", data)
	expect_error("Bad ship data: room 'cockpit' has volume")
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.ships_dir = dir
	own(main)
	_remove_dir(dir)
	return main


func test_bad_data_file_shows_its_problem() -> void:
	var main := _main_with_broken_data()
	assert_true(main.ship == null, "no ship is built")
	assert_true(main.error_label != null, "the message label exists")
	if main.error_label == null:
		return
	assert_true(main.error_label.visible, "the message is up")
	assert_true(main.error_label.text.begins_with("Could not load user://test_ships/broken.json: "),
			"names the file, got '%s'" % main.error_label.text)
	assert_true(main.error_label.text == "Could not load user://test_ships/broken.json: room 'cockpit' has volume 0.0 m3, which must be above 0",
			"names the file and the bare problem, got '%s'" % main.error_label.text)


func test_missing_ships_folder_names_its_path() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.ships_dir = "user://missing_ships"
	own(main)
	assert_true(main.error_label != null, "the message label exists")
	if main.error_label == null:
		return
	assert_true(main.error_label.text == "Could not load user://missing_ships: folder is missing",
			"got '%s'" % main.error_label.text)


func test_bad_data_file_runs_no_sim() -> void:
	var main := _main_with_broken_data()
	assert_true(not main.is_processing(), "the frame loop is off")
	main._input(_key(KEY_SPACE))
