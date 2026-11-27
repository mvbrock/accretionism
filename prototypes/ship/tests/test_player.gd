extends TestCase


func _spawn(offset_along: float = 0.0, x: float = 0.0) -> Player:
	var ship: Ship = own(RingShip.new())
	var player := own_player(ship)
	# Spawn just above the flat floor of section 0 (its surface is at y = -apothem).
	player.global_position = Vector3(x, -(RingGeometry.floor_apothem() - 0.05), 0) \
			+ RingGeometry.section_tangent(0) * offset_along
	await physics_frames(2)
	return player


func test_idle_on_floor_does_not_drift() -> void:
	var player := await _spawn()
	await physics_frames(30)
	var start := player.global_position
	await physics_frames(60)
	assert_true(player.is_on_floor(), "on floor")
	assert_near(player.global_position.distance_to(start), 0.0, 0.05, "idle drift")


func test_idle_on_slope_does_not_drift() -> void:
	var player := await _spawn(10.0)
	await physics_frames(30)
	var start := player.global_position
	await physics_frames(120)
	assert_true(player.is_on_floor(), "on floor on slope")
	assert_near(player.global_position.distance_to(start), 0.0, 0.05, "idle drift on slope")


func test_walks_full_lap_staying_grounded() -> void:
	var player := await _spawn()
	for crate in tree.root.find_children("Crate*", "StaticBody3D", true, false):
		crate.free()  # this test is about the floor; crates are obstacles
	player.walk_speed = 30.0
	player.move_input = Vector2(0, 1)
	var travelled := 0.0
	var last := RingGeometry.angle_of(player.global_position)
	var frames := 0
	var airborne := 0
	var min_r := INF
	var max_r := 0.0
	while travelled < TAU + 0.2 and frames < 2000:
		await tree.physics_frame
		frames += 1
		var angle := RingGeometry.angle_of(player.global_position)
		travelled += wrapf(angle - last, -PI, PI)
		last = angle
		if frames > 10:
			if not player.is_on_floor():
				airborne += 1
			var r := Vector2(player.global_position.y, player.global_position.z).length()
			min_r = minf(min_r, r)
			max_r = maxf(max_r, r)
	assert_true(travelled >= TAU, "completed a lap (travelled %.2f rad in %d frames)" % [travelled, frames])
	assert_true(airborne == 0, "never airborne (airborne %d frames)" % airborne)
	assert_true(min_r > RingGeometry.floor_apothem() - 0.1, "never above the floor (min r %.3f)" % min_r)
	assert_true(max_r < RingGeometry.FLOOR_CORNER_RADIUS + 0.1, "never below the floor (max r %.3f)" % max_r)


func test_w_moves_toward_increasing_angle() -> void:
	var player := await _spawn()
	player.move_input = Vector2(0, 1)
	await physics_frames(30)
	assert_true(RingGeometry.angle_of(player.global_position) > 0.01, "W increases angle")


func test_wall_stops_player() -> void:
	var player := await _spawn()
	player.move_input = Vector2(1, 0)
	await physics_frames(120)
	assert_true(player.global_position.x < 5.0 - 0.4 + 0.02, "stopped by wall (x %.3f)" % player.global_position.x)
	assert_true(player.global_position.x > 4.0, "reached wall (x %.3f)" % player.global_position.x)


func test_wall_stops_player_at_seam() -> void:
	var player := await _spawn(12.9)
	player.move_input = Vector2(1, 0)
	await physics_frames(120)
	assert_true(player.global_position.x < 5.0 - 0.4 + 0.02, "stopped by wall at seam (x %.3f)" % player.global_position.x)
	player.move_input = Vector2(-1, 0)
	await physics_frames(180)
	assert_true(player.global_position.x > -5.0 + 0.4 - 0.02, "stopped by left wall at seam (x %.3f)" % player.global_position.x)


func test_ensure_input_actions() -> void:
	Player.ensure_input_actions()
	for action in ["move_forward", "move_back", "move_left", "move_right", "toggle_gravity", "next_ship"]:
		assert_true(InputMap.has_action(action), "%s registered" % action)


func test_turns_to_face_aim() -> void:
	var player := await _spawn()
	player.aim_heading = Vector2(0, -1)
	await physics_frames(60)
	var around := RingGeometry.up_at(player.global_position).cross(Vector3.RIGHT)
	var nose := -player.global_basis.z
	assert_true(nose.dot(around) < -0.9, "nose turns to face backward (dot %.3f)" % nose.dot(around))


func test_aim_at_faces_point() -> void:
	var player := await _spawn()
	player.aim_at(player.global_position + Vector3(3, 0, 0))
	assert_true(player.aim_heading.distance_to(Vector2(1, 0)) < 0.01, "aims across the ring (%s)" % player.aim_heading)


func test_aim_through_faces_the_spot_under_the_cursor() -> void:
	var player := await _spawn()
	var rig := own_rig(player, player.ship)
	var camera: Camera3D = rig.get_node("Camera")
	await physics_frames(1)
	rig.snap()
	var cursor := camera.unproject_position(player.global_position + Vector3(3, 0, 0))
	player.aim_through(camera, cursor)
	assert_true(player.aim_heading.distance_to(Vector2(1, 0)) < 0.01, "aims at the cursor (%s)" % player.aim_heading)


func test_w_walks_the_way_it_faces() -> void:
	var player := await _spawn()
	player.aim_heading = Vector2(1, 0)
	await physics_frames(40)
	var start := player.global_position
	player.move_input = Vector2(0, 1)
	await physics_frames(20)
	var moved := player.global_position - start
	assert_true(moved.x > 0.5, "W walks across the ring when facing across (x moved %.2f)" % moved.x)
	assert_true(absf(RingGeometry.angle_of(player.global_position)) < 0.01, "no movement around the ring")


func test_d_strafes_right_of_facing() -> void:
	var player := await _spawn()
	player.aim_heading = Vector2(1, 0)
	await physics_frames(40)
	player.move_input = Vector2(1, 0)
	await physics_frames(20)
	assert_true(RingGeometry.angle_of(player.global_position) < -0.01, "D strafes to the right of facing")


func _height_above_floor(player: Player) -> float:
	var k := RingGeometry.section_of(player.global_position)
	return RingGeometry.floor_apothem() - player.global_position.dot(RingGeometry.section_down(k))


func test_zero_g_floats_horizontal() -> void:
	var player := await _spawn()
	player.set_gravity_enabled(false)
	await physics_frames(180)
	assert_true(not player.is_on_floor(), "off the floor")
	assert_near(_height_above_floor(player), Player.FLOAT_HEIGHT, 0.1, "hovers at float height")
	var pivot: Node3D = player.get_node("Pivot")
	var head := pivot.global_basis.y
	var up := RingGeometry.up_at(player.global_position)
	assert_true(absf(head.dot(up)) < 0.05, "body lies horizontal (head·up %.3f)" % head.dot(up))
	assert_true(head.dot(-player.global_basis.z) > 0.95, "head points the way it faces")


func test_zero_g_moves_without_sinking() -> void:
	var player := await _spawn()
	player.set_gravity_enabled(false)
	await physics_frames(180)
	player.move_input = Vector2(0, 1)
	await physics_frames(60)
	assert_true(RingGeometry.angle_of(player.global_position) > 0.01, "W still moves in zero-g")
	assert_near(_height_above_floor(player), Player.FLOAT_HEIGHT, 0.2, "stays afloat while moving")


func test_gravity_returns_player_upright_to_floor() -> void:
	var player := await _spawn()
	player.set_gravity_enabled(false)
	await physics_frames(180)
	player.set_gravity_enabled(true)
	await physics_frames(120)
	assert_true(player.is_on_floor(), "back on the floor")
	var pivot: Node3D = player.get_node("Pivot")
	var up := RingGeometry.up_at(player.global_position)
	assert_true(pivot.global_basis.y.dot(up) > 0.99, "upright again")


func _float(player: Player) -> void:
	player.set_gravity_enabled(false)
	await physics_frames(180)


func test_zero_g_keeps_drifting_after_release() -> void:
	var player := await _spawn()
	await _float(player)
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	var start := RingGeometry.angle_of(player.global_position)
	await physics_frames(60)
	var moved := (RingGeometry.angle_of(player.global_position) - start) * RingGeometry.floor_apothem()
	assert_near(moved, player.walk_speed, 0.3, "drifts on at walking speed for a second after release")


func test_zero_g_drift_stops_at_wall() -> void:
	var player := await _spawn()
	await _float(player)
	player.aim_heading = Vector2(1, 0)
	await physics_frames(40)
	player.move_input = Vector2(0, 1)
	await physics_frames(5)
	player.move_input = Vector2.ZERO
	await physics_frames(240)
	assert_true(player.global_position.x > 3.5, "drifted to the wall (x %.2f)" % player.global_position.x)
	assert_true(player.velocity.x < 0.01, "stopped at the wall (vx %.3f)" % player.velocity.x)


func test_zero_g_new_direction_replaces_drift() -> void:
	var player := await _spawn()
	await _float(player)
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2(0, -1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	var start := RingGeometry.angle_of(player.global_position)
	await physics_frames(30)
	assert_true(RingGeometry.angle_of(player.global_position) < start - 0.01, "now drifting backward")


func test_zero_g_float_height_ignores_crates() -> void:
	var player := await _spawn()
	await _float(player)
	var crate := StaticBody3D.new()
	crate.collision_layer = Ship.WORLD_LAYER
	crate.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	crate.add_child(shape)
	own(crate)
	var floor_y := -RingGeometry.floor_apothem()
	crate.global_position = Vector3(player.global_position.x, floor_y + 0.5, player.global_position.z)
	await physics_frames(60)
	assert_near(_height_above_floor(player), Player.FLOAT_HEIGHT, 0.1, "float height ignores the crate")


func test_zero_g_without_floor_below_holds_height() -> void:
	var player := await _spawn()
	await _float(player)
	var before := Vector2(player.global_position.y, player.global_position.z).length()
	player.ship.get_node("Section0/Floor").free()
	await physics_frames(60)
	var after := Vector2(player.global_position.y, player.global_position.z).length()
	assert_near(after, before, 0.05, "holds its distance from the axis with no floor below")


func test_player_without_ship_logs_nothing() -> void:
	own_player()
	await physics_frames(5)


func _boarder() -> Player:
	return own_player()


func test_board_places_and_faces() -> void:
	var ship: Ship = own(RingShip.new())
	var player := _boarder()
	var spawn := ship.spawn_point()
	player.board(ship, spawn, Vector2(1, 0), true)
	await physics_frames(2)
	assert_near(player.global_position.distance_to(spawn), 0.0, 0.1, "placed at the spawn point")
	assert_true(player.heading.distance_to(Vector2(1, 0)) < 0.01, "faces across (%s)" % player.heading)
	assert_true(player.gravity_enabled, "has gravity")


func test_board_clears_drift() -> void:
	var player := await _spawn()
	await _float(player)
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	var spawn := player.ship.spawn_point()
	player.board(player.ship, spawn, Vector2(0, 1), false)
	await physics_frames(60)
	var up := player.ship.up_at(spawn)
	var offset := player.global_position - spawn
	offset -= up * offset.dot(up)
	assert_true(offset.length() < 0.05, "did not drift (%.3f)" % offset.length())


func test_board_without_gravity_floats() -> void:
	var ship: Ship = own(SkiffShip.new())
	var player := _boarder()
	player.board(ship, ship.spawn_point(), Vector2(0, 1), true)
	assert_true(not player.gravity_enabled, "no gravity aboard the skiff")
	assert_near(player.get_node("Pivot").rotation.x, -PI / 2.0, 0.01, "tipped horizontal at once")


func test_g_does_nothing_without_gravity() -> void:
	var ship: Ship = own(SkiffShip.new())
	var player := _boarder()
	player.board(ship, ship.spawn_point(), Vector2(0, 1), true)
	Player.ensure_input_actions()
	var event := InputEventAction.new()
	event.action = "toggle_gravity"
	event.pressed = true
	player._unhandled_input(event)
	assert_true(not player.gravity_enabled, "G leaves zero-g alone on the skiff")
