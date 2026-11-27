extends TestCase

const DESTINATION_COLUMN := 3


## The main scene, with its own frame loop stopped so each test steps it by hand.
func _main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	main.set_process(false)
	return main


func _ship(main: Main, ship_name: String) -> Variant:
	for ship in main.fleet.cyclers + main.fleet.transports:
		if ship.name == ship_name:
			return ship
	return null


func _row(main: Main, ship: Variant) -> TreeItem:
	for item in main.table.get_root().get_children():
		if item.get_metadata(0) == ship:
			return item
	return null


func _option_texts(main: Main) -> Array:
	var texts := []
	for i in main.dispatch.targets.item_count:
		texts.append(main.dispatch.targets.get_item_text(i))
	return texts


func test_table_has_36_rows() -> void:
	var main := _main()
	assert_true(main.table.get_root().get_child_count() == 36, "6 cyclers + 30 transports")
	assert_true(main.table.columns == 4, "Ship | Origin | Progress | Destination")
	var first := main.table.get_root().get_child(0)
	assert_true(first.get_text(0) == "Aldrin I", "cyclers come first")


func test_select_row_shows_dispatch() -> void:
	var main := _main()
	var kestrel: Transport = _ship(main, "Kestrel")
	_row(main, kestrel).select(0)
	assert_true(main.selected == kestrel, "clicking Kestrel's row selects it")
	var expected := main.fleet.valid_targets(kestrel).map(func(target: Variant) -> String:
		return Fleet.target_name(target))
	assert_true(_option_texts(main) == expected, "targets are Kestrel's valid targets, got %s" % [_option_texts(main)])
	assert_true(main.dispatch.depart_button.visible, "Depart shows for a transport")
	assert_true(main.dispatch.estimate_label.text.begins_with("Est. travel time: "), "an estimate shows")
	assert_true(not main.dispatch.estimate_label.text.ends_with("unreachable"), "the first target is reachable")

	_row(main, _ship(main, "Aldrin I")).select(0)
	assert_true(main.selected == _ship(main, "Aldrin I"), "clicking a cycler's row selects it")
	assert_true(not main.dispatch.depart_button.visible, "Depart hides for a cycler")
	assert_true(not main.dispatch.targets.visible, "no dispatch controls for a cycler")


func test_selection_changed_signal() -> void:
	var main := _main()
	var seen := []
	main.selection_changed.connect(func(ship: Variant) -> void: seen.append(ship))
	var heron: Transport = _ship(main, "Heron")
	main.select(heron)
	main.select(heron)
	main.select(null)
	assert_true(seen == [heron, null], "emits once per change, got %s" % [seen])
	assert_true(not main.dispatch.depart_button.visible, "Depart hides with nothing selected")


func test_depart_updates_row() -> void:
	var main := _main()
	var kestrel: Transport = _ship(main, "Kestrel")
	main.select(kestrel)
	var mars_index := _option_texts(main).find("Mars")
	assert_true(mars_index != -1, "Mars is a valid target for Kestrel")
	main.dispatch.targets.select(mars_index)
	main.dispatch.targets.item_selected.emit(mars_index)
	main.dispatch.depart_button.pressed.emit()
	assert_true(kestrel.state == Transport.State.IN_TRANSIT, "Depart sends Kestrel")

	main.clock.paused = false
	main.clock.speed_index = 1 # 1 d/s
	main._process(1.0)
	assert_near(main.fleet.day, 1.0, 1e-9, "the fleet follows the clock")
	assert_true(_row(main, kestrel).get_text(DESTINATION_COLUMN) == "Mars", "the row shows the destination")
	assert_true(main.table.get_selected() == _row(main, kestrel), "the refresh keeps the row selected")


func test_unreachable_disables_depart() -> void:
	var main := _main()
	main.dispatch.show_estimate(-1.0)
	assert_true(main.dispatch.estimate_label.text == "Est. travel time: unreachable", "says so")
	assert_true(main.dispatch.depart_button.disabled, "Depart is disabled")
	main.dispatch.show_estimate(31.1667)
	assert_true(main.dispatch.estimate_label.text == "Est. travel time: 31.17 d", "got %s" % main.dispatch.estimate_label.text)
	assert_true(not main.dispatch.depart_button.disabled, "Depart is enabled again")


func test_clock_bar() -> void:
	var main := _main()
	main.play_pause_button.pressed.emit()
	assert_true(main.clock.paused, "the button pauses")
	main._process(1.0)
	assert_near(main.clock.day, 0.0, 1e-9, "no time passes while paused")
	main.play_pause_button.pressed.emit()
	var before: int = main.clock.speed_index
	main.speed_button.pressed.emit()
	assert_true(main.clock.speed_index == (before + 1) % SimClock.SPEEDS_DAYS_PER_SEC.size(), "the speed button steps the speed")
	main._process(0.5)
	assert_true(main.clock_label.text == main.clock.label(), "the label shows the clock")


func test_selection_survives_tab_switch() -> void:
	var main := _main()
	var kestrel: Transport = _ship(main, "Kestrel")
	main.select(kestrel)
	main.tabs.current_tab = 1
	await tree.process_frame
	main.tabs.current_tab = 0
	await tree.process_frame
	assert_true(main.selected == kestrel, "still selected")
	assert_true(main.table.get_selected() == _row(main, kestrel), "the row is still highlighted")
	assert_true(main.dispatch.ship_label.text == "Kestrel", "the panel still shows Kestrel")


func test_scaled_window_size_doubles_on_retina() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(4000, 3000))
	assert_true(size == Vector2i(3200, 1800), "2x scale doubles the window (got %s)" % size)


func test_scaled_window_size_fits_the_screen() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(3024, 1890))
	assert_true(size.x <= 3024 and size.y <= 1890, "fits the usable screen (got %s)" % size)
	assert_near(float(size.x) / size.y, 16.0 / 9.0, 0.01, "keeps the 16:9 shape")


func test_a_ship_in_flight_shows_its_destination_until_it_arrives() -> void:
	var main := _main()
	var kestrel: Transport = _ship(main, "Kestrel")
	main.select(kestrel)
	var mars_index := _option_texts(main).find("Mars")
	assert_true(mars_index != -1, "Mars is a valid target for Kestrel")
	main.dispatch.targets.select(mars_index)
	main.dispatch.depart_button.pressed.emit()
	assert_true(kestrel.state == Transport.State.IN_TRANSIT, "Kestrel is on its way")
	assert_true(main.dispatch.note_label.visible and main.dispatch.note_label.text == "In flight to Mars.",
		"the panel says where it is headed, got '%s'" % main.dispatch.note_label.text)
	for control in [main.dispatch.targets, main.dispatch.estimate_label, main.dispatch.depart_button]:
		assert_true(not control.visible, "%s hides while it flies" % control.name)

	main.fleet.advance_to(main.fleet.day + 1000.0)
	main.dispatch.refresh()
	assert_true(not main.dispatch.note_label.visible, "the note goes once Kestrel has arrived")
	assert_true(main.dispatch.targets.visible and main.dispatch.depart_button.visible, "the controls come back")
	assert_true(not _option_texts(main).has("Mars"), "Mars is no longer a target")
	assert_true(main.dispatch.selected_target() == null, "nothing is chosen for it")
	assert_true(main.dispatch.estimate_label.text == "Pick a destination", "got '%s'" % main.dispatch.estimate_label.text)
	assert_true(main.dispatch.depart_button.disabled, "Depart is disabled until a destination is picked")

	main.dispatch.targets.select(0)
	main.dispatch.refresh()
	assert_true(main.dispatch.estimate_label.text.begins_with("Est. travel time: "), "picking a target brings the estimate back")
	assert_true(not main.dispatch.depart_button.disabled, "and Depart")

func test_dispatch_keeps_the_list_when_its_targets_have_not_changed() -> void:
	var main := _main()
	main.select(_ship(main, "Kestrel"))
	main.dispatch.targets.set_item_metadata(0, "still the same item")
	main.dispatch.refresh()
	assert_true(main.dispatch.targets.get_item_metadata(0) == "still the same item", "refresh leaves an unchanged list alone")


func test_panel_title_shows_the_selected_ship_icon() -> void:
	var main := _main()
	assert_true(not main.dispatch.ship_icon.visible, "no icon with nothing selected")
	for ship_name in ["Kestrel", "Aldrin III"]:
		var ship: Variant = _ship(main, ship_name)
		main.select(ship)
		var image: Image = main.dispatch.ship_icon.texture.get_image()
		var middle := image.get_pixelv(Vector2i(image.get_width() / 2, image.get_height() * 6 / 10))
		assert_true(main.dispatch.ship_icon.visible, "%s's icon shows" % ship_name)
		assert_color_near(middle, main.icons.color_of(ship), "%s's icon is in its color" % ship_name)
	main.select(null)
	assert_true(not main.dispatch.ship_icon.visible, "the icon hides again")


func test_cycler_targets_show_their_icons() -> void:
	var main := _main()
	var kestrel: Transport = _ship(main, "Kestrel")
	main.select(kestrel)
	var valid := main.fleet.valid_targets(kestrel)
	assert_true(main.dispatch.targets.item_count == valid.size(), "the list shows every valid target")
	for i in valid.size():
		var has_icon := main.dispatch.targets.get_item_icon(i) != null
		assert_true(has_icon == valid[i] is Cycler, "%s %s an icon" % [Fleet.target_name(valid[i]), "has" if has_icon else "lacks"])
	assert_true(main.dispatch.targets.get_theme_constant("icon_max_width") == DispatchPanel.TARGET_ICON_WIDTH, "the button shows icons at logical size")
	assert_true(main.dispatch.targets.get_popup().get_theme_constant("icon_max_width") == DispatchPanel.TARGET_ICON_WIDTH, "so does its list")
