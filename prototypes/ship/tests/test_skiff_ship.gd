extends TestCase


func _make_ship() -> SkiffShip:
	var ship: SkiffShip = own(SkiffShip.new())
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func test_has_no_gravity() -> void:
	var ship := SkiffShip.new()
	assert_true(not ship.has_gravity(), "no gravity")
	assert_true(ship.up_at(Vector3(0, 1, 0)) == Vector3.UP, "up is +Y")
	assert_near(ship.camera_roll_at(Vector3(0, 1, -5)), 0.0, 0.0001, "no roll")
	ship.free()


func test_box_points_order() -> void:
	var points := Ship.box_points(Vector3(0, 0, 0), Vector3(1, 2, 3))
	assert_true(points[5] == Vector3(1, 0, 3), "corner 5 is x hi, y lo, z hi")
	assert_true(points[2] == Vector3(0, 2, 0), "corner 2 is x lo, y hi, z lo")


func test_builds_rooms() -> void:
	var ship := await _make_ship()
	for room in ["Cockpit", "Cabin", "Hold"]:
		for part in ["Floor", "Ceiling", "WallLeft", "WallRight", "Light"]:
			assert_true(ship.has_node("%s/%s" % [room, part]), "%s/%s exists" % [room, part])
	assert_true(ship.has_node("Cockpit/WallFore"), "Cockpit/WallFore exists")
	assert_true(ship.has_node("Hold/WallAft"), "Hold/WallAft exists")
	for bulkhead in ["Bulkhead1", "Bulkhead2"]:
		for part in ["Left", "Right", "Lintel"]:
			assert_true(ship.has_node("%s/%s" % [bulkhead, part]), "%s/%s exists" % [bulkhead, part])


func test_floor_on_floor_layer() -> void:
	var ship := await _make_ship()
	var hit := _ray(Vector3(0, 2, 0), Vector3(0, -1, 0), Ship.FLOOR_LAYER)
	assert_true(not hit.is_empty() and hit.collider == ship.get_node("Cabin/Floor"), "floor ray hits Cabin/Floor")
	if not hit.is_empty():
		assert_near(hit.position.y, 0.0, 0.01, "floor top")


func test_ceiling_height() -> void:
	var ship := await _make_ship()
	var hit := _ray(Vector3(2, 1, 0), Vector3(2, 6, 0), Ship.OCCLUDER_LAYER)
	assert_true(not hit.is_empty() and hit.collider == ship.get_node("Cabin/Ceiling"), "ceiling ray hits Cabin/Ceiling")
	if not hit.is_empty():
		assert_near(hit.position.y, 4.0, 0.01, "ceiling underside")


func test_doorway_is_open() -> void:
	var ship := await _make_ship()
	assert_true(_ray(Vector3(0, 2, -3), Vector3(0, 2, -9)).is_empty(), "doorway is clear")
	var side := _ray(Vector3(2.5, 2, -3), Vector3(2.5, 2, -9))
	assert_true(not side.is_empty() and side.collider == ship.get_node("Bulkhead1/Right"), "bulkhead right panel")
	var lintel := _ray(Vector3(0, 3.6, -3), Vector3(0, 3.6, -9))
	assert_true(not lintel.is_empty() and lintel.collider == ship.get_node("Bulkhead1/Lintel"), "bulkhead lintel")


func _meshes(ship: Ship, paths: Array) -> Array:
	var meshes := []
	for path in paths:
		meshes.append(ship.get_node(path + "/Mesh"))
	return meshes


func _same_meshes(actual: Array[MeshInstance3D], expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for mesh in expected:
		if not actual.has(mesh):
			return false
	return true


func test_room_fade_meshes() -> void:
	var ship := await _make_ship()
	var toward_fore := ship.room_fade_meshes(Vector3(0, 1, 0), Vector3(-0.58, -0.58, -0.58))
	assert_true(_same_meshes(toward_fore, _meshes(ship, ["Cabin/Ceiling", "Cabin/WallRight",
			"Bulkhead2/Left", "Bulkhead2/Right", "Bulkhead2/Lintel"])), "cabin, view -x -z")
	var toward_aft := ship.room_fade_meshes(Vector3(0, 1, 0), Vector3(0.58, -0.58, 0.58))
	assert_true(_same_meshes(toward_aft, _meshes(ship, ["Cabin/Ceiling", "Cabin/WallLeft",
			"Bulkhead1/Left", "Bulkhead1/Right", "Bulkhead1/Lintel"])), "cabin, view +x +z")
	var cockpit := ship.room_fade_meshes(Vector3(0, 1, -9), Vector3(0.58, -0.58, 0.58))
	assert_true(_same_meshes(cockpit, _meshes(ship, ["Cockpit/Ceiling", "Cockpit/WallLeft", "Cockpit/WallFore"])), "cockpit")
	assert_true(ship.room_fade_meshes(Vector3(0, 1, 20), Vector3(0.58, -0.58, 0.58)).is_empty(), "outside every room")


func test_spawn_point_in_cabin() -> void:
	var ship := SkiffShip.new()
	var spawn := ship.spawn_point()
	assert_true(spawn.z >= -6.0 and spawn.z <= 4.0, "spawn in the Cabin")
	assert_near(spawn.y, 0.05, 0.001, "spawn height")
	ship.free()


func test_floating_player_drifts_through_doorway() -> void:
	var skiff := await _make_ship()
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	player.drive_by_code = true
	player.ship = skiff
	own(player)
	player.global_position = skiff.spawn_point()
	player.set_gravity_enabled(false)
	await physics_frames(180)
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	await physics_frames(300)
	assert_true(player.global_position.z < -7.0, "drifted into the Cockpit (z = %.2f)" % player.global_position.z)
