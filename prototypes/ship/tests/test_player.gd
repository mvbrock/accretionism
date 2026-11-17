extends TestCase

const PLAYER_SCENE := "res://scenes/player.tscn"


func _spawn(offset_along: float = 0.0, x: float = 0.0) -> Player:
	own(ShipBuilder.new())
	var player: Player = load(PLAYER_SCENE).instantiate()
	player.drive_by_code = true
	own(player)
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
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		assert_true(InputMap.has_action(action), "%s registered" % action)


func test_nose_turns_around_when_reversing() -> void:
	var player := await _spawn()
	player.move_input = Vector2(0, 1)
	await physics_frames(40)
	player.move_input = Vector2(0, -1)
	await physics_frames(60)
	var around := RingGeometry.up_at(player.global_position).cross(Vector3.RIGHT)
	var nose := -player.global_basis.z
	assert_true(nose.dot(around) < -0.9, "nose faces backward after reversing (dot %.3f)" % nose.dot(around))
