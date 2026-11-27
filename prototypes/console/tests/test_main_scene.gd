extends TestCase


## The main scene connected to `ship_name`, with its own frame loop stopped so each test steps it by hand.
func _main(ship_name := "kestrel") -> Main:
	var main := _disconnected_main()
	main.console.line_submitted.emit("ships connect " + ship_name)
	return main


func _disconnected_main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.fleet = ShipFixture.make_fleet()
	own(main)
	main.set_process(false)
	for ship in main.fleet.ships.values():
		(ship as Ship).transmission_s = 0.0
	return main


## Submits `line` and steps the main scene by no time, which is enough to land a command and its reply when transmission takes none.
func _send(main: Main, line: String) -> void:
	main.console.line_submitted.emit(line)
	main._process(0.0)


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
	assert_true(main.dashboard != null and main.dashboard.ship_view.room_box("treehouse") != null, "the dashboard shows wren's rooms")
	assert_true(main.console.scrollback.get_parsed_text().contains("connected to wren"), "the response prints")


func test_disconnect_takes_the_dashboard_away() -> void:
	var main := _main()
	main.console.line_submitted.emit("disconnect")
	assert_true(main.ship == null, "no ship is connected")
	assert_true(main.dashboard == null, "the dashboard is gone")
	assert_true(main.no_ship_label.visible, "NO SHIP CONNECTED shows")


func test_disconnect_clears_the_reboot_overlay() -> void:
	var main := _main()
	_send(main, "computer restart")
	assert_true(main.overlay.visible, "the overlay is up while booting")
	main.console.line_submitted.emit("disconnect")
	assert_true(not main.overlay.visible and not main.stale_label.visible, "no banner covers the placeholder")


func test_reconnecting_to_another_ship_rebuilds_the_dashboard() -> void:
	var main := _main()
	main.console.line_submitted.emit("disconnect")
	main.console.line_submitted.emit("ships connect wren")
	assert_true(main.dashboard.selected_room == "treehouse", "the ROOM panel starts on wren's first room, got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.get_index() == 0, "the dashboard sits under the banners")
	var boxes := main.dashboard.ship_view.find_children("*", "MeshInstance3D", true, false).filter(
			func(node: Node) -> bool: return (node as MeshInstance3D).mesh is BoxMesh and node.name.begins_with("room "))
	assert_true(boxes.size() == 4, "the 3D view shows wren's four rooms, got %d" % boxes.size())


func test_connecting_to_a_faulted_ship_shows_its_last_readings() -> void:
	var main := _main()
	_send(main, "debug fault computer")
	main.console.line_submitted.emit("disconnect")
	main.console.line_submitted.emit("ships connect kestrel")
	assert_true(main.stale_label.visible, "STALE shows")
	assert_true(main.dashboard.ship_view.room_box("cargo") != null, "the rooms are drawn")
	assert_true(main.dashboard.room_heading.text == "COCKPIT", "the ROOM panel has a room, got '%s'" % main.dashboard.room_heading.text)
	assert_true(main.dashboard._clock_label.text != "", "the clock shows")


func test_clicks_reach_the_new_dashboard_after_a_reconnect() -> void:
	var main := _main()
	var old := main.dashboard
	main.console.line_submitted.emit("disconnect")
	main.console.line_submitted.emit("ships connect wren")
	await tree.process_frame
	assert_true(not is_instance_valid(old), "the old dashboard is freed")
	await _click_room(main, "cargo")
	assert_true(main.dashboard.room_heading.text == "CARGO", "got '%s'" % main.dashboard.room_heading.text)


func test_every_ship_runs_while_disconnected() -> void:
	var main := _disconnected_main()
	main.clock.paused = false
	main._process(1.0)
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
	_send(main, "door open hatch")
	var text := main.console.scrollback.get_parsed_text()
	assert_true(text.contains("> door open hatch"), "the line is echoed, got '%s'" % text)
	assert_true(text.contains("hatch: opening (6 s)"), "the response prints, got '%s'" % text)
	assert_true(main.ship.opening("hatch").state == Opening.State.OPENING, "the hatch is opening")


func test_reply_prints_after_the_transmission_time() -> void:
	var main := _main()
	main.ship.transmission_s = 10.0
	main.console.line_submitted.emit("door open hatch")
	var text := main.console.scrollback.get_parsed_text()
	assert_true(text.contains("sent to kestrel; reply in 0:20"), "the console says when to expect the reply, got '%s'" % text)
	main.clock.paused = false
	main._process(19.0)
	assert_true(not main.console.scrollback.get_parsed_text().contains("hatch: opening"), "no reply yet")
	assert_true(main.ship.opening("hatch").state != Opening.State.CLOSED, "the hatch has moved by then")
	main._process(1.0)
	assert_true(main.console.scrollback.get_parsed_text().contains("reply to 'door open hatch': hatch: opening (6 s)"), "the reply names its command when it lands")


func test_main_advances_with_the_clock_step() -> void:
	var main := _disconnected_main()
	main.clock.paused = false
	main.clock.speed_index = 2
	main._process(0.5 / 3600.0)
	assert_near(main.fleet.ships.kestrel.time_s, 0.0, 1e-9,
			"half a sim second is less than the step at 1 hour/s")


func test_dashboard_log_has_no_command_line() -> void:
	var main := _main()
	_send(main, "door open hatch")
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


## Lays the main scene out at window size, so the 3D view has a size to pick in. The headless window is only 64x64.
func _lay_out(main: Main) -> void:
	main.set_anchors_preset(Control.PRESET_TOP_LEFT) # so the size below isn't overridden by full-rect anchors
	main.size = Vector2(1600, 900)
	await tree.process_frame


func _click_room(main: Main, room_id: String) -> void:
	await _lay_out(main)
	var view := main.dashboard.ship_view
	var point := view.screen_point(main.ship.room(room_id).position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		view.gui_input.emit(event)


func _panel_text(main: Main, key: String) -> String:
	return main.dashboard.room_label(key).text


func test_the_3d_view_names_every_room() -> void:
	var main := _main()
	for room in main.ship.rooms:
		var label := main.dashboard.ship_view.room_name(room.id)
		assert_true(label.text == room.id.to_upper(), "%s is labelled with its name, got '%s'" % [room.id, label.text])


func test_a_rooms_box_is_its_status_colour() -> void:
	var main := _main()
	var view := main.dashboard.ship_view
	assert_true(Color(view.room_tint("cargo"), 1.0) == DashboardView.GREEN, "nominal cargo is green, got %s" % view.room_tint("cargo"))
	_vent(main.ship.room("cargo"))
	main.refresh()
	assert_true(Color(view.room_tint("cargo"), 1.0) == DashboardView.RED, "vented cargo is red, got %s" % view.room_tint("cargo"))


func test_room_panel_starts_on_the_first_room() -> void:
	var main := _main()
	assert_true(main.dashboard.room_heading.text == "COCKPIT", "got '%s'" % main.dashboard.room_heading.text)
	assert_true(_panel_text(main, "pressure") == "101.3 kPa", "got '%s'" % _panel_text(main, "pressure"))


func test_room_panel_is_the_left_most_panel() -> void:
	var main := _main()
	var heading_x := main.dashboard.room_heading.get_global_rect().position.x
	assert_true(main.dashboard.room_heading.get_parent().get_index() == 0, "ROOM is the first child of the panels row")
	assert_true(heading_x <= main.dashboard.panels.get_global_rect().position.x + 1.0, "ROOM sits at the row's left edge")


func test_clicking_a_room_shows_it() -> void:
	var main := _main()
	await _click_room(main, "main")
	assert_true(main.dashboard.room_heading.text == "MAIN", "got '%s'" % main.dashboard.room_heading.text)
	assert_true(_panel_text(main, "pressure") == "101.3 kPa", "got '%s'" % _panel_text(main, "pressure"))
	_vent(main.ship.room("main"))
	main.refresh()
	assert_true(_panel_text(main, "o2") == "O₂ —", "vacuum reads — in the panel, got '%s'" % _panel_text(main, "o2"))


func test_clicking_the_selected_room_keeps_it_selected() -> void:
	var main := _main()
	await _click_room(main, "main")
	await _click_room(main, "main")
	assert_true(main.dashboard.selected_room == "main", "got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.room_heading.text == "MAIN", "the panel still shows MAIN")


func test_clicking_a_room_leaves_the_command_line_focused() -> void:
	var main := _main()
	main.console.input.grab_focus()
	await _lay_out(main)
	var view := main.dashboard.ship_view
	var point := view.global_position + view.screen_point(main.ship.room("main").position)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		main.get_viewport().push_input(event)
	assert_true(main.dashboard.selected_room == "main", "the click reaches the view, got '%s'" % main.dashboard.selected_room)
	assert_true(main.console.input.has_focus(), "the command line keeps the focus")


func test_one_room_is_highlighted() -> void:
	var main := _main()
	await _click_room(main, "cargo")
	var alphas := {}
	for room in main.ship.rooms:
		alphas[room.id] = main.dashboard.ship_view.room_tint(room.id).a
	assert_true(alphas.cargo > alphas.cockpit and alphas.cockpit == alphas.main,
			"only the selected box is brighter, got %s" % alphas)


func test_panel_shows_passengers_after_command() -> void:
	var main := _main()
	main.dashboard.select_room("cargo")
	main.refresh()
	assert_true(_panel_text(main, "passengers") == "passengers 0", "got '%s'" % _panel_text(main, "passengers"))
	_send(main, "passenger add cargo")
	main.refresh()
	assert_true(_panel_text(main, "passengers") == "passengers 1", "got '%s'" % _panel_text(main, "passengers"))


func test_clicking_while_the_computer_is_down_does_nothing() -> void:
	var main := _main()
	_send(main, "debug fault computer")
	main.refresh()
	await _click_room(main, "main")
	assert_true(main.dashboard.selected_room == "cockpit", "FAULT: the selection is unchanged, got '%s'" % main.dashboard.selected_room)
	_send(main, "computer restart")
	main.refresh()
	await _click_room(main, "main")
	assert_true(main.dashboard.selected_room == "cockpit", "BOOTING: the selection is unchanged, got '%s'" % main.dashboard.selected_room)
	main.ship.advance(21.0)
	main.refresh()
	await _click_room(main, "main")
	assert_true(main.dashboard.selected_room == "main", "RUN: the click selects, got '%s'" % main.dashboard.selected_room)
	assert_true(main.dashboard.room_heading.text == "MAIN", "the panel shows MAIN")


func test_the_main_scene_starts_with_the_standard_fleet() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	assert_true(main.fleet.names() == Fleet.standard().names(), "got %s" % main.fleet.names())


func test_capture_opens_the_skiffs_hold() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	main.set_process(false)
	Main.CaptureScript.new(main, "user://capture_test")
	main.refresh()
	assert_true(main.link.ship_name == "skiff", "got '%s'" % main.link.ship_name)
	assert_true(main.ship.opening("hatch").state != Opening.State.CLOSED, "the hatch is opening")
	assert_true(main.dashboard.room_heading.text == "HOLD", "got '%s'" % main.dashboard.room_heading.text)


func _fits(main: Main) -> void:
	await _lay_out(main)
	await tree.process_frame
	var bounds := main.dashboard.get_global_rect()
	for part in [main.dashboard.ship_view, main.dashboard.panels]:
		assert_true(bounds.encloses(part.get_global_rect()), "%s stays inside the dashboard %s" % [part.get_global_rect(), bounds])


func test_three_rooms_fit_the_dashboard() -> void:
	await _fits(_main())


func test_four_rooms_fit_the_dashboard() -> void:
	await _fits(_main("wren"))


func test_reboot_overlay() -> void:
	var main := _main()
	assert_true(not main.overlay.visible, "no overlay while running")
	_send(main, "computer restart")
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
	_send(main, "computer restart")
	main.refresh()
	await tree.process_frame
	assert_true(main.overlay.visible, "the overlay is up")
	assert_true(main.dashboard.get_global_rect().encloses(main.overlay.get_global_rect()),
			"overlay %s stays inside the dashboard %s" % [main.overlay.get_global_rect(), main.dashboard.get_global_rect()])
	assert_true(not main.overlay.get_global_rect().intersects(main.console.get_global_rect()),
			"overlay %s overlaps console %s" % [main.overlay.get_global_rect(), main.console.get_global_rect()])
	_send(main, "computer restart")
	main.ship.advance(21.0)
	_send(main, "debug fault computer")
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
	_send(main, "debug fault computer")
	main.refresh()
	assert_true(main.stale_label.visible, "STALE shows in FAULT")
	assert_true(main.stale_label.text == "STALE", "got '%s'" % main.stale_label.text)
	var label := main.dashboard.room_label("pressure")
	var before := label.text
	_vent(main.ship.room("cockpit"))
	main.refresh()
	assert_true(label.text == before, "the panels stay as they were, got '%s'" % label.text)
	_send(main, "computer restart")
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
	assert_true(main.clock.speed_index == 1, "Speed steps to 1 min/s")
	main.set_process(true)
	main.clock.paused = false
	main.clock.speed_index = 1
	main._process(1.0)
	main.set_process(false)
	assert_near(main.ship.time_s, 60.0, 1e-6, "_process advances the ship by sim time")


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
	assert_true(main.dashboard.speed_button.text == "Speed: 1 hour/s", "speed shows 1 hour/s, got '%s'" % main.dashboard.speed_button.text)
	main.clock.paused = true
	main.refresh()
	assert_true(main.dashboard.pause_button.text == "Play", "paused offers Play, got '%s'" % main.dashboard.pause_button.text)


func _status(main: Main) -> LinkStatus:
	return main.console.link_status


func test_link_bars_are_idle_when_disconnected_and_when_nothing_is_in_flight() -> void:
	var main := _disconnected_main()
	assert_true(_status(main).uplink_label.text == "uplink: idle", "got '%s'" % _status(main).uplink_label.text)
	assert_true(_status(main).downlink_label.text == "downlink: idle", "got '%s'" % _status(main).downlink_label.text)
	assert_true(_status(main).uplink_bar.value == 0.0 and _status(main).downlink_bar.value == 0.0, "both empty")
	assert_true(_status(main).visible, "shown while disconnected")
	_send(main, "ships connect kestrel")
	assert_true(_status(main).uplink_label.text == "uplink: idle", "idle when connected too")


func test_link_bars_follow_the_uplink_then_the_downlink() -> void:
	var main := _main()
	main.ship.transmission_s = 100.0
	main.clock.paused = false
	main.console.line_submitted.emit("door open hatch")
	main._process(0.0)
	assert_true(_status(main).uplink_label.text == "uplink: door open hatch — 1:40 left", "got '%s'" % _status(main).uplink_label.text)
	assert_true(_status(main).downlink_label.text == "downlink: waiting", "got '%s'" % _status(main).downlink_label.text)
	main._process(25.0)
	assert_near(_status(main).uplink_bar.value, 0.25, 0.001, "uplink a quarter done")
	assert_true(_status(main).uplink_label.text == "uplink: door open hatch — 1:15 left", "got '%s'" % _status(main).uplink_label.text)
	assert_true(_status(main).downlink_bar.value == 0.0, "downlink not started")
	main._process(75.0)
	assert_true(_status(main).uplink_bar.value == 1.0, "uplink stays full")
	assert_true(_status(main).uplink_label.text == "uplink: door open hatch — sent", "got '%s'" % _status(main).uplink_label.text)
	assert_true(_status(main).downlink_label.text == "downlink: door open hatch — 1:40 left", "got '%s'" % _status(main).downlink_label.text)
	main._process(50.0)
	assert_near(_status(main).downlink_bar.value, 0.5, 0.001, "downlink half done")
	main._process(50.0)
	assert_true(_status(main).uplink_label.text == "uplink: idle", "idle after the reply")
	assert_true(_status(main).downlink_label.text == "downlink: idle", "idle after the reply")
	assert_true(_status(main).uplink_bar.value == 0.0, "bars empty again")


func test_a_long_line_does_not_widen_the_console() -> void:
	var main := _main()
	main.ship.transmission_s = 100.0
	main.console.line_submitted.emit("door open " + "x".repeat(300))
	main._process(0.0)
	await tree.process_frame
	var width := main.console.get_combined_minimum_size().x
	assert_true(width < 300.0, "the console's minimum width stays small, got %s" % width)


func test_the_view_keeps_half_the_dashboard_on_the_wheel() -> void:
	var dashboard := DashboardView.new()
	own(dashboard)
	dashboard.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dashboard.size = Vector2(900, 900)
	dashboard.show_ship(WheelShip.new())
	await tree.process_frame
	await tree.process_frame
	assert_true(dashboard.ship_view.size.y >= 0.45 * dashboard.size.y, "the view is %.0f of %.0f" % [dashboard.ship_view.size.y, dashboard.size.y])


func _listed_breakers(dashboard: DashboardView) -> Array[String]:
	var listed: Array[String] = []
	for label in dashboard._breaker_grid.get_children():
		if label.visible:
			listed.append(label.text.split("  ")[0])
	return listed


func test_the_breakers_panel_lists_the_selected_rooms_breakers_then_the_systems() -> void:
	var dashboard := DashboardView.new()
	own(dashboard)
	var wheel := WheelShip.new()
	dashboard.show_ship(wheel)
	dashboard.select_room("a0")
	dashboard.show_ship(wheel)
	var want: Array[String] = ["light-a0"]
	for door in wheel.doors_of("a0"):
		want.append(door.id)
	want.append_array(Ship.SYSTEM_BREAKER_IDS)
	assert_true(_listed_breakers(dashboard) == want, "got %s, want %s" % [_listed_breakers(dashboard), want])
	assert_true(DashboardModel.total_draw_text(wheel) == dashboard._total_label.text, "the total stays the whole ship's")


func test_the_breakers_panel_lists_a_breaker_tripped_in_another_room() -> void:
	var dashboard := DashboardView.new()
	own(dashboard)
	var wheel := WheelShip.new()
	dashboard.show_ship(wheel)
	dashboard.select_room("a0")
	wheel.breaker_trip("light-c5")
	dashboard.show_ship(wheel)
	var listed := _listed_breakers(dashboard)
	assert_true(listed.has("light-c5") and listed.back() == "light-c5", "the tripped breaker is listed last, got %s" % [listed])
	assert_true(not listed.has("light-c6"), "a closed breaker elsewhere is not listed")


func test_selecting_another_room_changes_the_breakers_listed() -> void:
	var dashboard := DashboardView.new()
	own(dashboard)
	var wheel := WheelShip.new()
	dashboard.show_ship(wheel)
	dashboard.select_room("b3")
	dashboard.show_ship(wheel)
	var listed := _listed_breakers(dashboard)
	assert_true(listed.has("light-b3") and listed.has("hatch") and not listed.has("light-a0"), "got %s" % [listed])
	dashboard.select_room("hub")
	dashboard.show_ship(wheel)
	listed = _listed_breakers(dashboard)
	assert_true(listed.has("light-hub") and not listed.has("light-b3") and not listed.has("hatch"), "got %s" % [listed])
