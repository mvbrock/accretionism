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


func _move_mouse(view: DiagramView, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	view._gui_input(event)


func test_hover_follows_a_ship_that_moves_from_under_a_still_mouse() -> void:
	var main: Main = await _main()
	var view := main.diagram
	var cycler: Cycler = _ship(main, "Aldrin III")
	_move_mouse(view, _cycler_pos(view, cycler))
	assert_true(view._hovered == cycler, "the mouse over the square hovers the cycler")
	var mouse_point := _cycler_pos(view, cycler)

	main.clock.paused = false
	main.clock.speed_index = SimClock.SPEEDS_DAYS_PER_SEC.size() - 1 # 10 d/s
	main._process(5.0)
	view._process(5.0)
	assert_true(_cycler_pos(view, cycler).distance_to(mouse_point) > DiagramView.PICK_RADIUS, "the square moved out from under the mouse")
	assert_true(view._hovered != cycler, "the cycler is no longer hovered once it has moved away")
	assert_true(view._hovered == view.ship_at(mouse_point), "whatever is under the mouse now is hovered")


func test_mouse_leaving_clears_hover_until_it_returns() -> void:
	var main: Main = await _main()
	var view := main.diagram
	var cycler: Cycler = _ship(main, "Aldrin III")
	_move_mouse(view, _cycler_pos(view, cycler))
	view._notification(Control.NOTIFICATION_MOUSE_EXIT)
	view.rebuild()
	assert_true(view._hovered == null, "rebuilding with the mouse outside hovers nothing")


func test_a_turned_back_cycler_square_is_still_pickable() -> void:
	var main: Main = await _main()
	var view := main.diagram
	var host: Cycler = main.fleet.cyclers[0]
	var docked: Array = main.fleet.transports.filter(
		func(t: Transport) -> bool: return t.state == Transport.State.DOCKED and t.host == host)
	assert_true(not docked.is_empty(), "%s has a docked transport" % host.name)
	var t: Transport = docked[0]
	assert_true(main.fleet.depart(t, Orbits.Body.MOON), "%s leaves for the Moon" % t.name)
	main.fleet.advance_to(main.fleet.day + 0.05)
	assert_true(main.fleet.depart(t, host), "%s turns back to %s" % [t.name, host.name])
	view.rebuild()
	assert_true(view.ship_at(_cycler_pos(view, host)) == host, "the square still picks the cycler, not the looping transport")


func _length(polyline: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, polyline.size()):
		total += polyline[i - 1].distance_to(polyline[i])
	return total


## A 200 px line, along x, sampled at `count` points.
func _line(count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		points.append(Vector2(200.0 * i / (count - 1), 0.0))
	return points


func test_dashes_are_the_same_length_however_finely_the_line_is_sampled() -> void:
	for count in [2, 3, 33, 400]:
		var dashes := DiagramView.dashes(_line(count))
		assert_true(dashes.size() == 15, "%d points: 200 px holds 15 dashes (got %d)" % [count, dashes.size()])
		# Only the dash nearest the start may be cut short; the pattern runs from the end.
		for i in range(1, dashes.size()):
			assert_near(_length(dashes[i]), DiagramView.DASH_LENGTH, 0.01, "%d points: dash %d is full length" % [count, i])
		assert_near(dashes[dashes.size() - 1][-1].x, 200.0, 0.01, "%d points: the last dash ends on the line's end" % count)


func test_dashes_follow_a_bend() -> void:
	var corner := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
	var dashes := DiagramView.dashes(corner)
	for i in range(1, dashes.size()):
		assert_near(_length(dashes[i]), DiagramView.DASH_LENGTH, 0.01, "dash %d keeps its length, the one across the corner too" % i)
	for dash in dashes:
		for p in dash:
			assert_true(is_equal_approx(p.y, 0.0) or is_equal_approx(p.x, 100.0), "dashes stay on the path (got %s)" % p)


func test_a_line_shorter_than_a_dash_is_one_dash() -> void:
	var dashes := DiagramView.dashes(PackedVector2Array([Vector2.ZERO, Vector2(3, 0)]))
	assert_true(dashes.size() == 1 and is_equal_approx(_length(dashes[0]), 3.0), "one 3 px dash")
