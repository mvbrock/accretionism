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
	for action in ["move_forward", "move_back", "move_left", "move_right", "toggle_gravity", "next_ship", "interact"]:
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
	player.board(ship, PlayerPose.new(spawn, Vector2(1, 0), true))
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
	player.board(player.ship, PlayerPose.new(spawn, Vector2(0, 1), false))
	await physics_frames(60)
	var up := player.ship.up_at(spawn)
	var offset := player.global_position - spawn
	offset -= up * offset.dot(up)
	assert_true(offset.length() < 0.05, "did not drift (%.3f)" % offset.length())


func test_board_without_gravity_floats() -> void:
	var ship: Ship = own(SkiffShip.new())
	var player := _boarder()
	player.board(ship, PlayerPose.new(ship.spawn_point(), Vector2(0, 1), true))
	assert_true(not player.gravity_enabled, "no gravity aboard the skiff")
	assert_near(player.get_node("Pivot").rotation.x, -PI / 2.0, 0.01, "tipped horizontal at once")


func test_g_does_nothing_without_gravity() -> void:
	var ship: Ship = own(SkiffShip.new())
	var player := _boarder()
	player.board(ship, PlayerPose.new(ship.spawn_point(), Vector2(0, 1), true))
	Player.ensure_input_actions()
	var event := InputEventAction.new()
	event.action = "toggle_gravity"
	event.pressed = true
	player._unhandled_input(event)
	assert_true(not player.gravity_enabled, "G leaves zero-g alone on the skiff")


## A DeckShip with a player boarded at deck 0's landing exit, facing the pipe, with gravity.
func _at_ladder() -> Player:
	var ship: DeckShip = own(DeckShip.new())
	var player := own_player(ship)
	await physics_frames(2)
	player.board(ship, PlayerPose.new(ship.ladders[0].landings[0].exit, Vector2(0, -1), true))
	await physics_frames(2)
	return player


func test_interact_grabs_nearby_ladder() -> void:
	var player := await _at_ladder()
	player.interact()
	await physics_frames(2)
	assert_true(player.climbing != null, "climbing after interact")
	assert_near(player.global_position.x, 3.5, 0.05, "on the pipe axis (x)")
	assert_near(player.global_position.z, 3.5, 0.05, "on the pipe axis (z)")
	assert_true(player.interact_hint() == "W/S: climb   E: let go", "hint at a landing while climbing")


func test_climb_up_and_off() -> void:
	var player := await _at_ladder()
	player.interact()
	player.move_input = Vector2(0, 1)
	var frames := 0
	while player.global_position.y <= DeckShip.PITCH - 0.2 and frames < 300:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	player.interact()
	var exit: Vector3 = (player.ship as DeckShip).ladders[0].landings[1].exit
	assert_true(player.climbing == null, "let go at the top")
	assert_true(player.global_position.distance_to(exit) < 0.1, "stands at landing 1's exit")
	await physics_frames(30)
	assert_true(player.is_on_floor(), "on deck 1's floor")
	assert_near(player.global_position.y, DeckShip.PITCH, 0.1, "at deck 1's height")


func test_climb_clamps_at_ends() -> void:
	var player := await _at_ladder()
	player.interact()
	player.move_input = Vector2(0, -1)
	await physics_frames(60)
	assert_true(player.global_position.y >= 0.04, "not below the bottom (y %.3f)" % player.global_position.y)
	player.move_input = Vector2(0, 1)
	await physics_frames(400)
	assert_true(player.global_position.y <= DeckShip.PITCH + 0.06, "not above the top (y %.3f)" % player.global_position.y)


func test_cannot_let_go_mid_shaft() -> void:
	var player := await _at_ladder()
	player.interact()
	player.move_input = Vector2(0, 1)
	var frames := 0
	while player.global_position.y < DeckShip.PITCH / 2.0 and frames < 300:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	player.interact()
	assert_true(player.climbing != null, "still climbing mid-shaft")
	assert_true(player.interact_hint() == "W/S: climb", "hint mid-shaft")


func test_far_from_ladder_cannot_grab() -> void:
	var ship: DeckShip = own(DeckShip.new())
	var player := own_player(ship)
	await physics_frames(2)
	player.board(ship, PlayerPose.new(ship.spawn_point(), Vector2(0, -1), true))
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == null, "nothing to grab")
	assert_true(player.interact_hint() == "", "no hint")


func test_g_ignored_while_climbing() -> void:
	var player := await _at_ladder()
	player.interact()
	var event := InputEventAction.new()
	event.action = "toggle_gravity"
	event.pressed = true
	player._unhandled_input(event)
	await physics_frames(10)
	assert_true(player.gravity_enabled, "gravity stays on")
	assert_near(player.get_node("Pivot").rotation.x, 0.0, 0.01, "stays upright")


func test_board_ends_climb() -> void:
	var player := await _at_ladder()
	player.interact()
	var ring: Ship = own(RingShip.new())
	player.board(ring, PlayerPose.new(ring.spawn_point(), Vector2(0, 1), true))
	assert_true(player.climbing == null, "boarding lets go")


func test_pose_round_trips_a_climb() -> void:
	var player := await _at_ladder()
	var deck: DeckShip = player.ship
	player.interact()
	player.move_input = Vector2(0, 1)
	var frames := 0
	while player.global_position.y <= 2.0 and frames < 300:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	var saved := player.pose()
	var ring: Ship = own(RingShip.new())
	player.board(ring, PlayerPose.at_spawn(ring))
	player.board(deck, saved)
	assert_true(player.climbing == deck.ladders[0], "back on the deck ship's ladder")
	assert_near(player.climb_s, saved.climb_s, 0.01, "same height on the ladder")
	assert_near(player.global_position.x, 3.5, 0.05, "on the pipe axis (x)")
	assert_near(player.global_position.z, 3.5, 0.05, "on the pipe axis (z)")


func test_pose_at_spawn() -> void:
	var skiff: Ship = own(SkiffShip.new())
	var pose := PlayerPose.at_spawn(skiff)
	assert_true(pose.position == skiff.spawn_point(), "at the spawn point")
	assert_true(pose.heading == Vector2(0, 1), "facing heading (0, 1), perpendicular to up and world X")
	assert_true(not pose.gravity, "no gravity on the skiff")


func test_walking_into_doorway_is_blocked() -> void:
	var player := await _at_ladder()
	player.move_input = Vector2(0, 1)
	await physics_frames(90)
	var limit := DeckShip.PIPE_CENTER.y - DeckShip.PIPE_INNER - DeckShip.PIPE_WALL
	assert_true(player.global_position.z < limit, "never enters the shaft (z %.3f)" % player.global_position.z)


func test_floating_player_can_grab() -> void:
	var player := await _at_ladder()
	player.set_gravity_enabled(false)
	await physics_frames(180)
	player.interact()
	assert_true(player.climbing != null, "grabbed while floating")
	await physics_frames(2)
	assert_near(player.global_position.x, 3.5, 0.05, "on the pipe axis (x)")
	assert_near(player.global_position.z, 3.5, 0.05, "on the pipe axis (z)")
	assert_near(player.get_node("Pivot").rotation.x, 0.0, 0.01, "upright on the ladder")


func test_let_go_clears_aim() -> void:
	var player := await _at_ladder()
	player.interact()
	player.aim_heading = Vector2(0, -1)
	player.interact()
	await physics_frames(30)
	assert_true(player.heading.y > 0.9, "still faces away from the pipe (heading %s)" % player.heading)


## A ship with gravity only below y = 10.
class SplitShip extends Ship:
	func has_gravity_at(p: Vector3) -> bool:
		return p.y < 10.0


## A player boarded on a SplitShip at `at`, wanting gravity.
func _on_split_ship(at: Vector3) -> Player:
	var ship: Ship = own(SplitShip.new())
	var player := own_player(ship)
	await physics_frames(2)
	player.board(ship, PlayerPose.new(at, Vector2(0, 1), true))
	return player


## Puts the body at `at` at rest and lets two frames pass.
func _move_to(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	await physics_frames(2)


func test_gravity_follows_position() -> void:
	var player := await _on_split_ship(Vector3(0, 20, 0))
	assert_true(not player.gravity_enabled, "no gravity up high")
	await _move_to(player, Vector3.ZERO)
	assert_true(player.gravity_enabled, "gravity once low")


func test_g_ignored_where_no_gravity() -> void:
	var player := await _on_split_ship(Vector3(0, 20, 0))
	Player.ensure_input_actions()
	var event := InputEventAction.new()
	event.action = "toggle_gravity"
	event.pressed = true
	player._unhandled_input(event)
	assert_true(player.wants_gravity, "G changes nothing where there is no gravity")


func test_wants_gravity_survives_zero_g() -> void:
	var player := await _on_split_ship(Vector3.ZERO)
	player.set_gravity_enabled(false)
	await _move_to(player, Vector3(0, 20, 0))
	await _move_to(player, Vector3.ZERO)
	assert_true(not player.gravity_enabled, "still floating after passing through zero-g")


func test_pose_stores_wants() -> void:
	var player := await _on_split_ship(Vector3(0, 20, 0))
	assert_true(player.pose().gravity, "pose keeps what the player wants")
