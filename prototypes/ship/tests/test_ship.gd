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


func test_pipe_segment_along_a_tilted_frame() -> void:
	var ship := Ship.new()
	own(ship)
	var frame := Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3.ZERO)
	var parent := Node3D.new()
	ship.add_child(parent)
	ship.add_pipe_segment(parent, frame, 0.0, 4.0, 2.6, true, Color.WHITE, "P")
	await physics_frames(2)
	for piece in ["PipeLeft", "PipeRight", "PipeAft", "PipeLintel", "PipeCap", "Hatch"]:
		assert_true(parent.get_node_or_null(piece) != null, "segment has %s" % piece)
	var space := tree.root.get_world_3d().direct_space_state
	var axis := frame.basis.y
	var across := frame.basis.z
	var door_at := frame.origin + axis * 1.0
	var door_ray := PhysicsRayQueryParameters3D.create(door_at - across * 2.0, door_at + across * 2.0, Ship.HATCH_LAYER)
	var door_hit := space.intersect_ray(door_ray)
	assert_true(not door_hit.is_empty() and door_hit.collider.name == "Hatch", "a ray across the doorway hits the hatch")
	var axis_ray := PhysicsRayQueryParameters3D.create(frame.origin + axis * 1.0, frame.origin + axis * 5.0, Ship.WORLD_LAYER)
	var axis_hit := space.intersect_ray(axis_ray)
	assert_true(not axis_hit.is_empty() and axis_hit.collider.name == "PipeCap", "a ray along the axis hits the cap")
