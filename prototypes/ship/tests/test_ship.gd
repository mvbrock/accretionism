extends TestCase


func test_base_ship_defaults() -> void:
	var ship := Ship.new()
	assert_true(ship.up_at(Vector3(1, 2, 3)) == Vector3.UP, "up is +Y")
	assert_near(ship.camera_roll_at(Vector3(1, 2, 3)), 0.0, 0.0001, "no roll")
	assert_true(ship.room_fade_meshes(Vector3.ZERO, Vector3.FORWARD).is_empty(), "nothing to fade")
	assert_true(ship.room_at(Vector3.ZERO) == "", "no rooms by default")
	assert_true(ship.cutaway_nodes(Vector3.ZERO).is_empty(), "no cutaway by default")
	assert_true(ship.spawn_point() == Vector3.ZERO, "spawn at origin")
	assert_true(ship.has_gravity(), "gravity by default")
	assert_true(ship.ladders.is_empty(), "no ladders by default")
	ship.free()
