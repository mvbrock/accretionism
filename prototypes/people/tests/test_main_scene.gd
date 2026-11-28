extends TestCase


## The main scene on the shared sim, with its own frame loop stopped so each test steps it by hand.
func _main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.sim = SharedSim.get_sim()
	own(main)
	main.set_process(false)
	return main


func test_main_scene_loads_and_ticks() -> void:
	var main := _main()
	assert_true(main.table.get_root().get_child_count() == 300, "one row per passenger")
	assert_true(main.table.columns == 6, "six columns")
	assert_true(main.detail_panel.shown == null, "the panel starts empty")
	main.clock.paused = false
	main.clock.speed_index = 1
	var before := main.sim.day
	main._process(1.0)
	assert_near(main.sim.day, before + 1.0, 1e-9, "the sim follows the clock")
	assert_true(main.clock_label.text == main.clock.label(), "the label shows the clock")


func test_clock_bar() -> void:
	var main := _main()
	main.play_pause_button.pressed.emit()
	assert_true(main.clock.paused, "the button pauses")
	var before := main.sim.day
	main._process(1.0)
	assert_near(main.sim.day, before, 1e-9, "no time passes while paused")
	main.play_pause_button.pressed.emit()
	var speed: int = main.clock.speed_index
	main.speed_button.pressed.emit()
	assert_true(main.clock.speed_index == (speed + 1) % SimClock.SPEEDS_DAYS_PER_SEC.size(), "the speed button steps the speed")


func test_filter_box_filters_the_table() -> void:
	var main := _main()
	var target: Passenger = main.sim.passengers_by_id.values()[7]
	main.filter.text = target.id
	main.filter.text_changed.emit(target.id)
	main.table.refresh(main.sim)
	var shown := main.table.get_root().get_children().filter(func(item: TreeItem) -> bool: return item.visible)
	assert_true(shown.size() == 1 and shown[0].get_metadata(0) == target, "only the matching row shows")


func test_scaled_window_size_fits_the_screen() -> void:
	assert_true(Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(4000, 3000)) == Vector2i(3200, 1800), "2x scale doubles the window")
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(3024, 1890))
	assert_true(size.x <= 3024 and size.y <= 1890, "fits the usable screen (got %s)" % size)
