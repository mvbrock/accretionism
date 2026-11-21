extends TestCase

const WINDOW_SIZE := Vector2(1600, 900)


## The main scene at the project's window size (the headless window is 64 x 64),
## with the Diagram tab showing and laid out, its frame loop stopped so each
## test steps it by hand.
func _main() -> Main:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	own(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.size = WINDOW_SIZE
	main.set_process(false)
	main.diagram.set_process(false)
	main.tabs.current_tab = Main.DIAGRAM_TAB
	await tree.process_frame
	main.diagram.rebuild()
	return main


func _ship(main: Main, ship_name: String) -> Variant:
	for ship in main.fleet.cyclers + main.fleet.transports:
		if ship.name == ship_name:
			return ship
	return null


func _cycler_pos(view: DiagramView, cycler: Cycler) -> Vector2:
	for entry in view.layout.cyclers:
		if entry.cycler == cycler:
			return entry.pos
	return Vector2.INF


func _click(view: DiagramView, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	view._gui_input(event)


func test_click_selects_ship() -> void:
	var main: Main = await _main()
	var view := main.diagram
	assert_true(view.size.x > 100.0 and view.size.y > 100.0, "the diagram is laid out, got %s" % view.size)
	var cycler: Cycler = _ship(main, "Aldrin III")
	var square := _cycler_pos(view, cycler)
	assert_true(view.ship_at(square) == cycler, "the square is the cycler")
	assert_true(view.ship_at(square + Vector2(7, 7)) == cycler, "anywhere on the 14.4 px square picks it")
	assert_true(view.ship_at(square + Vector2(13.5, 0)) == cycler, "a click within the 14.4 px pick radius picks it")
	var empty := Vector2(2, view.size.y - 2)
	assert_true(view.ship_at(empty) == null, "empty space picks nothing")

	_click(view, square)
	assert_true(main.selected == cycler, "a left click on the square selects the cycler")
	_click(view, empty)
	assert_true(main.selected == null, "a click on empty space clears the selection")


func test_click_selects_parked_transport() -> void:
	var main: Main = await _main()
	var view := main.diagram
	assert_true(not view.layout.parked.is_empty(), "the starting fleet has parked or docked transports")
	var entry: Dictionary = view.layout.parked[0]
	_click(view, entry.pos)
	assert_true(main.selected == entry.transport, "a click on a parked triangle selects that transport")


func test_redraws_when_clock_runs() -> void:
	var main: Main = await _main()
	var view := main.diagram
	var cycler: Cycler = main.fleet.cyclers[0]
	var before := _cycler_pos(view, cycler)
	main.clock.paused = false
	main.clock.speed_index = SimClock.SPEEDS_DAYS_PER_SEC.size() - 1 # 10 d/s
	main._process(1.0)
	view._process(1.0)
	var after := _cycler_pos(view, cycler)
	assert_true(before.distance_to(after) > 0.5, "the square moves after 10 sim days (%s -> %s)" % [before, after])


func test_hidden_view_does_not_rebuild() -> void:
	var main: Main = await _main()
	var view := main.diagram
	main.tabs.current_tab = Main.TABLE_TAB
	var before: Dictionary = view.layout
	main.clock.paused = false
	main._process(1.0)
	view._process(1.0)
	assert_true(view.layout == before, "no layout work while the Table tab shows")
