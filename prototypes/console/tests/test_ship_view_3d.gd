extends TestCase

const VIEW_SIZE := Vector2(800, 400)


## A view of `ship` in the tree, laid out at VIEW_SIZE and drawn once with `selected` selected.
func _view(ship: Ship, selected := "") -> ShipView3D:
	var view := ShipView3D.new(ship)
	own(view)
	view.size = VIEW_SIZE
	view.show_ship(ship, selected if selected != "" else ship.rooms[0].id)
	await tree.process_frame
	return view


func _vent(room: Room) -> void:
	for gas in room.mol:
		room.mol[gas] = 0.0


func _mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	return event


func _drag(view: ShipView3D, from: Vector2, by: Vector2) -> void:
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_LEFT, true, from))
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = from + by
	motion.relative = by
	view.gui_input.emit(motion)
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_LEFT, false, from + by))


func _parallel(a: Vector3, b: Vector3) -> bool:
	return absf(absf(a.normalized().dot(b.normalized())) - 1.0) < 1e-3


func _rgb(color: Color) -> Color:
	return Color(color.r, color.g, color.b)


func test_one_box_and_one_name_per_room_at_its_centre() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	for room in ship.rooms:
		var box := view.room_box(room.id)
		assert_true(box.mesh is BoxMesh and ((box.mesh as BoxMesh).size - room.size).length() < 1e-4,
				"%s is a box its size, got %s" % [room.id, box.mesh])
		assert_true(box.global_position.distance_to(room.position) < 1e-4,
				"%s box sits at the room's centre, got %s" % [room.id, box.global_position])
		var label := view.room_name(room.id)
		assert_true(label.text == room.id.to_upper(), "%s label reads its name, got '%s'" % [room.id, label.text])
		assert_true(label.global_position.distance_to(room.position) < 1e-4,
				"%s label sits at the room's centre, got %s" % [room.id, label.global_position])
		assert_true(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "%s label faces the camera" % room.id)
		assert_true(label.no_depth_test, "%s label shows through boxes" % room.id)
	assert_true(view.find_children("*", "Label3D", true, false).size() == ship.rooms.size(), "one label per room")


func test_rotated_rooms_turn_their_boxes() -> void:
	var ship := RingShip.new()
	var view := await _view(ship)
	for room in ship.rooms:
		var basis := view.room_box(room.id).global_basis
		assert_true((basis.x - room.orientation.x).length() < 1e-4 and (basis.z - room.orientation.z).length() < 1e-4,
				"%s box turns with the room" % room.id)


func test_one_door_panel_per_opening_on_its_face() -> void:
	for ship: Ship in [ShipFixture.make(), RingShip.new(), TugShip.new()]:
		var view := await _view(ship)
		for opening in ship.openings:
			var panel := view.door_panel(opening.id)
			assert_true(panel.global_position.distance_to(opening.position) < 1e-3,
					"%s panel sits at the opening, got %s want %s" % [opening.id, panel.global_position, opening.position])
			var normal := ship.room(opening.room_a).face_normal(opening.face_a)
			assert_true(_parallel(panel.global_basis.z, normal),
					"%s panel lies flat on its face, normal %s want %s" % [opening.id, panel.global_basis.z, normal])
		teardown()


func test_box_tint_follows_the_rooms_status() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	assert_true(_rgb(view.room_tint("cargo")) == _rgb(DashboardView.GREEN), "nominal cargo is green, got %s" % view.room_tint("cargo"))
	_vent(ship.room("cargo"))
	view.show_ship(ship, "cockpit")
	assert_true(_rgb(view.room_tint("cargo")) == _rgb(DashboardView.RED), "vented cargo is red, got %s" % view.room_tint("cargo"))
	assert_true(_rgb(view.room_tint("main")) == _rgb(DashboardView.GREEN), "main stays green")


func test_the_selected_room_is_brighter() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship, "main")
	assert_true(view.room_tint("main").a > view.room_tint("cargo").a, "the selected box is less see-through")
	assert_true(view.room_edge_color("main").a > view.room_edge_color("cargo").a, "the selected box has brighter edges")
	view.show_ship(ship, "cargo")
	assert_true(view.room_tint("cargo").a > view.room_tint("main").a, "the highlight follows the selection")


func test_door_colour_follows_its_state() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	assert_true(view.door_color("d1") == ShipView3D.DOOR_CLOSED, "closed, got %s" % view.door_color("d1"))
	ship.set_opening("d1", true)
	ship.advance(0.5)
	view.show_ship(ship, "cockpit")
	assert_true(view.door_color("d1") == ShipView3D.DOOR_MOVING, "opening, got %s" % view.door_color("d1"))
	ship.advance(5.0)
	view.show_ship(ship, "cockpit")
	assert_true(view.door_color("d1") == ShipView3D.DOOR_OPEN, "open, got %s" % view.door_color("d1"))
	ship.breaker_trip("d1")
	view.show_ship(ship, "cockpit")
	assert_true(view.door_color("d1") == ShipView3D.DOOR_UNPOWERED, "no power, got %s" % view.door_color("d1"))


func test_room_at_finds_the_room_under_a_point() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	for room_id in ["main", "cargo"]:
		var point := view.screen_point(ship.room(room_id).position)
		assert_true(view.room_at(point) == room_id, "%s's centre picks %s, got '%s'" % [room_id, room_id, view.room_at(point)])
	var cockpit := view.screen_point(ship.room("cockpit").position)
	assert_true(view.room_at(cockpit) == "cockpit", "a name drawn on top of main still picks its own room, got '%s'" % view.room_at(cockpit))
	var cargo := ship.room("cargo")
	var box_only := view.screen_point(cargo.position + Vector3(0, -1.0, 1.5))
	assert_true(view.name_at(box_only) == "", "precondition: no name under the box-only point")
	assert_true(view.room_at(box_only) == "cargo", "a point on cargo away from its name picks cargo, got '%s'" % view.room_at(box_only))
	assert_true(view.room_at(Vector2(2, 2)) == "", "a corner of empty space picks nothing")


func test_a_click_on_a_room_emits_it() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	var clicked: Array[String] = []
	view.room_clicked.connect(func(id: String) -> void: clicked.append(id))
	var point := view.screen_point(ship.room("cargo").position)
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_LEFT, true, point))
	assert_true(clicked.is_empty(), "nothing on press")
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_LEFT, false, point))
	assert_true(clicked == ["cargo"], "release without a drag clicks cargo, got %s" % [clicked])


func test_a_drag_orbits_the_camera_and_does_not_click() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	var clicked: Array[String] = []
	view.room_clicked.connect(func(id: String) -> void: clicked.append(id))
	var before := view.camera.global_transform
	var ship_before := view.ship_root.global_transform
	var focus_before := view.camera.global_position.distance_to(view.focus)
	_drag(view, view.screen_point(ship.room("main").position), Vector2(60, 20))
	assert_true(not view.camera.global_transform.is_equal_approx(before), "the camera moves")
	assert_true(view.ship_root.global_transform.is_equal_approx(ship_before), "the ship stays put")
	assert_near(view.camera.global_position.distance_to(view.focus), focus_before, 1e-3, "the camera keeps its distance")
	assert_true(clicked.is_empty(), "a drag is not a click, got %s" % [clicked])


func test_the_wheel_zooms() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	var size_before := view.camera.size
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_WHEEL_UP, true, VIEW_SIZE / 2))
	assert_true(view.camera.size < size_before, "wheel up shrinks the view, %.2f -> %.2f" % [size_before, view.camera.size])
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, VIEW_SIZE / 2))
	view.gui_input.emit(_mouse_button(MOUSE_BUTTON_WHEEL_DOWN, true, VIEW_SIZE / 2))
	assert_true(view.camera.size > size_before, "wheel down widens it")


func test_the_view_frames_every_standard_ship() -> void:
	var fleet := Fleet.standard()
	for ship_name in fleet.ships:
		var ship: Ship = fleet.ships[ship_name]
		var view := await _view(ship)
		var rect := Rect2(Vector2.ZERO, VIEW_SIZE)
		for room in ship.rooms:
			for corner in 8:
				var offset := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
				var point := room.position + room.orientation * (room.size * 0.5 * offset)
				assert_true(not view.camera.is_position_behind(point) and rect.has_point(view.screen_point(point)),
						"%s: %s corner %d is on screen, got %s" % [ship_name, room.id, corner, view.screen_point(point)])
		teardown()


func test_picking_skips_a_room_that_contains_the_camera() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	view.camera.global_position = ship.room("cargo").position
	view.camera.look_at(ship.room("main").position)
	assert_true(view.room_at(VIEW_SIZE / 2 + Vector2(0, 100)) != "cargo", "a room the camera is inside is not picked, got '%s'" % view.room_at(VIEW_SIZE / 2 + Vector2(0, 100)))


func test_names_are_about_the_label_size_on_screen() -> void:
	var ship := ShipFixture.make()
	var view := await _view(ship)
	var label := view.room_name("cargo")
	var on_screen := label.pixel_size * label.font_size * VIEW_SIZE.y / view.camera.size
	assert_near(on_screen, ShipView3D.LABEL_EM_PX, 0.5, "label em height in control px")


func test_the_ship_fills_the_view() -> void:
	var fleet := Fleet.standard()
	for ship_name in fleet.ships:
		var ship: Ship = fleet.ships[ship_name]
		var view := await _view(ship)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for room in ship.rooms:
			for corner in 8:
				var offset := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
				var p := view.screen_point(room.position + room.orientation * (room.size * 0.5 * offset))
				low = low.min(p)
				high = high.max(p)
		var span := high - low
		assert_true(span.x >= 0.75 * VIEW_SIZE.x or span.y >= 0.75 * VIEW_SIZE.y,
				"%s fills the view, span %s of %s" % [ship_name, span, VIEW_SIZE])
		teardown()


func test_the_camera_is_orthographic_and_the_ship_fills_90_percent() -> void:
	var fleet := Fleet.standard()
	for ship_name in fleet.ships:
		var ship: Ship = fleet.ships[ship_name]
		var view := await _view(ship)
		assert_true(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "%s: orthographic" % ship_name)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for room in ship.rooms:
			for corner in 8:
				var offset := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
				var p := view.screen_point(room.position + room.orientation * (room.size * 0.5 * offset))
				low = low.min(p)
				high = high.max(p)
		var fill := maxf((high.x - low.x) / VIEW_SIZE.x, (high.y - low.y) / VIEW_SIZE.y)
		assert_near(fill, ShipView3D.FRAME_FILL, 0.02, "%s fills its limiting dimension" % ship_name)
		teardown()


func _visible_name_rects(view: ShipView3D, ship: Ship) -> Dictionary:
	var rects := {}
	for room in ship.rooms:
		if view.room_name(room.id).visible:
			rects[room.id] = view.name_rect(room.id)
	return rects


func test_no_two_visible_names_overlap_on_the_wheel() -> void:
	var ship := WheelShip.new()
	var view := await _view(ship, "")
	var rects := _visible_name_rects(view, ship)
	var ids := rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			assert_true(not rects[ids[i]].intersects(rects[ids[j]]), "%s and %s overlap" % [ids[i], ids[j]])
	assert_true(view.room_name(ship.rooms[0].id).visible, "the selected room's name shows")
	var hidden := ""
	for room in ship.rooms:
		if not view.room_name(room.id).visible:
			hidden = room.id
			break
	assert_true(hidden != "", "some names are hidden on the Wheel")
	assert_true(view.name_at(view.screen_point(ship.room(hidden).position)) != hidden, "a hidden name takes no click")
	view.show_ship(ship, hidden)
	assert_true(view.room_name(hidden).visible, "selecting a hidden room shows its name")
	assert_true(view.name_at(view.screen_point(ship.room(hidden).position)) == hidden, "and it takes the click")
