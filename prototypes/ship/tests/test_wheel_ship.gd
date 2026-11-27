extends TestCase


func _make_ship() -> WheelShip:
	var ship := WheelShip.new()
	own(ship)
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func test_rooms_and_gravity() -> void:
	var ship := await _make_ship()
	assert_true(ship.room_at(ship.spawn_point()) == "Ring1/Section0", "spawn is in the middle ring's section 0")
	assert_true(ship.has_gravity_at(ship.spawn_point()), "gravity in the ring")
	assert_true(ship.room_at(Vector3(0, -3, 0)) == "Hub1", "inside the middle hub room")
	assert_true(not ship.has_gravity_at(Vector3(0, -3, 0)), "no gravity in a hub room")
	assert_true(ship.room_at(Vector3(-24, 3, 0)) == "Hub0", "inside the first hub room")
	assert_true(ship.room_at(Vector3(2.5, -20, 0)) == "Spoke1", "inside ring 1's pipe")
	assert_true(ship.has_gravity_at(Vector3(2.5, -20, 0)), "gravity in the pipe below the hub")


func test_three_ladders_three_landings() -> void:
	var ship := await _make_ship()
	assert_true(ship.ladders.size() == 3, "one ladder per ring (got %d)" % ship.ladders.size())
	var apothem := RingGeometry.floor_apothem()
	for ring in 3:
		var ladder := ship.ring_ladder(ring)
		assert_near(ladder.length, 2.0 * apothem - 0.1 - Player.BODY_HEIGHT, 0.01, "ladder %d runs ring floor to ring floor" % ring)
		assert_true(ladder.landings.size() == 3, "ladder %d has three landings" % ring)
		if ladder.landings.size() != 3:
			continue
		assert_near(ladder.landings[1].s, apothem - WheelShip.HUB_HALF_SIZE, 0.01, "landing 1 is the hub floor")
		assert_near(ladder.landings[2].s, ladder.length, 0.01, "landing 2 is the end")
		assert_true(ship.room_at(ladder.landings[0].exit).begins_with("Ring%d/" % ring), "landing 0 is in ring %d's room" % ring)
		assert_true(ship.room_at(ladder.landings[1].exit) == "Hub%d" % ring, "landing 1 is in Hub%d" % ring)
		assert_true(ship.room_at(ladder.landings[2].exit).begins_with("Ring%d/" % ring), "landing 2 is in ring %d's room" % ring)
		assert_near(ladder.landings[0].exit.y, -apothem + 0.05, 0.01, "the bottom exit is 5 cm above the floor")
		assert_near(ladder.landings[2].exit.y, apothem - 0.05, 0.01, "the top exit is 5 cm off the top ring's floor")
		for landing in ladder.landings:
			assert_near(landing.exit.z, -(Ship.PIPE_OUTER + WheelShip.EXIT_GAP), 0.001, "exits stand off toward -Z")
			assert_true(landing.facing.is_equal_approx(Vector3.BACK), "landings face +Z, toward the rungs")


func test_ladder_holes_open() -> void:
	var ship := await _make_ship()
	var x := WheelShip.RING_CENTERS[1] + WheelShip.LADDER_X
	var hit := _ray(Vector3(x, -46, 0), Vector3(x, 46, 0))
	assert_true(hit.is_empty(), "ring 1's ladder axis is clear from ring floor to ring floor (hit %s)" % hit.get("collider"))


func test_hub_nodes() -> void:
	var ship := await _make_ship()
	for i in 3:
		var room := "Hub%d" % i
		assert_true((ship.get_node("%s/Floora" % room) as StaticBody3D).collision_layer == (Ship.WORLD_LAYER | Ship.FLOOR_LAYER), "%s's floor is a floor" % room)
		for panel_name in ["Ceilinga", "WallLeft", "WallRight"]:
			var panel: StaticBody3D = ship.get_node("%s/%s" % [room, panel_name])
			assert_true(panel.collision_layer == (Ship.WORLD_LAYER | Ship.OCCLUDER_LAYER), "%s/%s is an occluder" % [room, panel_name])
		var light: OmniLight3D = ship.get_node("%s/Light" % room)
		assert_true(light.position.is_equal_approx(Vector3(WheelShip.RING_CENTERS[i], 0, 0)) and light.omni_range == 16.0, "%s has a light at its center" % room)
	for end in ["HubEndFore", "HubEndAft"]:
		assert_true(ship.has_node(end), "%s closes the row" % end)
	for bulkhead in ["Bulkhead1", "Bulkhead2"]:
		for piece in ["Left", "Right", "Lintel"]:
			assert_true(ship.has_node("%s/%s" % [bulkhead, piece]), "%s has a %s piece" % [bulkhead, piece])
	for segment in ["BottomRingSeg", "BottomShaft", "HubSeg", "TopShaft", "TopRingSeg"]:
		assert_true(ship.has_node("Spoke1/%s/PipeLeft" % segment), "Spoke1 has a %s" % segment)


func test_hub_is_fixed() -> void:
	var ship := await _make_ship()
	for z in [3.0, -3.0]:
		var p := Vector3(0, -2, z)
		assert_true(ship.up_at(p) == Vector3.UP, "up is +Y in the hub at %s" % p)
		assert_true(ship.camera_roll_at(p) == 0.0, "the camera does not roll in the hub at %s" % p)


func test_camera_roll_through_the_top_spoke() -> void:
	var ship := await _make_ship()
	var x := WheelShip.RING_CENTERS[1] + WheelShip.LADDER_X
	var apothem := RingGeometry.floor_apothem()
	var hub_top := WheelShip.HUB_HALF_SIZE + WheelShip.SLAB
	assert_near(ship.camera_roll_at(Vector3(x, -20, 0)), 0.0, 0.001, "no roll in the bottom spoke")
	assert_near(ship.camera_roll_at(Vector3(x, hub_top - 0.01, 0)), 0.0, 0.001, "no roll inside the hub")
	assert_near(ship.camera_roll_at(Vector3(x, (hub_top + apothem) / 2.0, 0)), PI / 2.0, 0.05, "a quarter turn halfway up the top spoke")
	assert_near(ship.camera_roll_at(Vector3(x, apothem - 0.05, 0)), PI, 0.05, "a half turn at the top ring's floor")
	assert_true(ship.up_at(Vector3(x, 10, 0)).is_equal_approx(Vector3.DOWN), "up is toward the axis in the top spoke")
	assert_true(ship.up_at(Vector3(x, -10, 0)).is_equal_approx(Vector3.UP), "up is toward the axis in the bottom spoke")


func test_doorway_between_hub_rooms() -> void:
	var ship := await _make_ship()
	assert_true(_ray(Vector3(-6, -3, 2.5), Vector3(18, -3, 2.5)).is_empty(), "the doorway is open at z = 2.5")
	var wall := _ray(Vector3(-6, -3, -2.5), Vector3(18, -3, -2.5))
	assert_true(not wall.is_empty() and ship.get_path_to(wall.collider).get_name(0) == &"Bulkhead2", "beside the doorway is bulkhead 2 (hit %s)" % wall.get("collider"))
	var lintel := _ray(Vector3(6, 0, 2.5), Vector3(18, 0, 2.5))
	assert_true(not lintel.is_empty() and ship.get_path_to(lintel.collider).get_name(0) == &"Bulkhead2", "above the doorway is bulkhead 2 (hit %s)" % lintel.get("collider"))
	var end := _ray(Vector3(-30, -3, 0), Vector3(-40, -3, 0))
	assert_true(not end.is_empty() and end.collider.name == "HubEndFore", "the fore end is solid (hit %s)" % end.get("collider"))


func test_hub_far_side_fades() -> void:
	var ship := await _make_ship()
	var faded := ship.room_fade_meshes(Vector3(0, -3, 0), Vector3(-0.58, -0.58, -0.58))
	var names := []
	for mesh in faded:
		names.append(ship.get_path_to(mesh.get_parent()))
	assert_true(names.any(func(n: NodePath) -> bool: return str(n).begins_with("Hub1/Ceiling")), "the ceiling fades")
	assert_true(names.has(^"Hub1/WallRight"), "the wall on the camera's side fades")
	assert_true(not names.any(func(n: NodePath) -> bool: return str(n).begins_with("Hub1/Floor")), "the floor under the player is not a bound")
	assert_true(not names.has(^"Hub1/WallLeft"), "the far wall stays")


func test_float_between_rooms() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	player.board(ship, PlayerPose.new(Vector3(-6, -WheelShip.HUB_HALF_SIZE + 0.05, 2.5), Vector2(1, 0), false))
	await physics_frames(180)
	assert_true(ship.room_at(player.global_position) == "Hub1", "floating in Hub1")
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	await physics_frames(400)
	assert_true(ship.room_at(player.global_position) == "Hub2", "drifted through the doorway into the next room (at %s)" % player.global_position)


func test_climb_bottom_to_hub_to_top() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	var ladder := ship.ring_ladder(1)
	player.board(ship, PlayerPose.new(ladder.landings[0].exit, Vector2(0, -1), true))
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed ring 1's ladder")
	player.climb_speed = 15.0
	player.move_input = Vector2(0, 1)
	var hub_s := ladder.landings[1].s
	var frames := 0
	while hub_s - player.climb_s > 0.3 and frames < 300:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	assert_near(player.climb_s, hub_s, 0.3, "reached the hub landing")
	player.interact()
	assert_true(player.climbing == null, "let go at the hub landing")
	assert_true(not player.gravity_enabled, "floating in the hub")
	assert_true(ship.up_at(player.global_position) == Vector3.UP, "up is +Y in the hub")
	assert_near(ship.camera_roll_at(player.global_position), 0.0, 0.001, "the camera has not rolled in the hub")
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed the ladder again from the hub")
	player.move_input = Vector2(0, 1)
	frames = 0
	while player.climb_s < ladder.length - 0.1 and frames < 400:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	assert_true(player.climb_s >= ladder.length - 0.1, "reached the top within 400 frames (s = %.2f)" % player.climb_s)
	player.interact()
	assert_true(player.climbing == null, "let go at the top ring")
	assert_true(player.gravity_enabled, "gravity in the top ring")
	await physics_frames(30)
	assert_true(player.is_on_floor(), "standing on the top ring's floor")
	assert_true(player.global_basis.y.distance_to(Vector3.DOWN) < 0.05, "upside down in world terms (up %s)" % player.global_basis.y)
	assert_near(absf(ship.camera_roll_at(player.global_position)), PI, 0.1, "the camera is turned over to match the top ring")


func test_climb_down_from_the_top_ring() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	var ladder := ship.ring_ladder(1)
	player.board(ship, PlayerPose.new(ladder.landings[2].exit, Vector2(0, 1), true))
	await physics_frames(30)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed the ladder at the top ring")
	assert_near(player.climb_s, ladder.length, 0.01, "at the top")
	player.climb_speed = 15.0
	player.move_input = Vector2(0, -1)
	var frames := 0
	while player.climb_s > ladder.landings[1].s + 0.3 and frames < 400:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	player.interact()
	assert_true(player.climbing == null, "let go at the hub landing")
	assert_true(ship.room_at(player.global_position) == "Hub1", "in the hub")
	assert_true(not player.gravity_enabled, "floating in the hub")


## The names of the nodes `ship.cutaway_nodes(p)` returns.
func _cutaway_names(ship: WheelShip, p: Vector3) -> Array:
	var names := []
	for node in ship.cutaway_nodes(p):
		names.append(str(node.name))
	names.sort()
	return names


func _ring_with_ladder(ring: int) -> Array:
	return ["Ring%d" % ring, "Spoke%d" % ring]


func test_cutaway() -> void:
	var ship := await _make_ship()
	var expected := _ring_with_ladder(2) + ["Hub2", "HubEndAft"]
	expected.sort()
	assert_true(_cutaway_names(ship, ship.spawn_point()) == expected, "ring 1 hides ring 2, its ladder, Hub2 and the aft end")
	expected = _ring_with_ladder(1) + _ring_with_ladder(2) + ["Hub1", "Hub2", "Bulkhead2", "HubEndAft"]
	expected.sort()
	var in_hub0 := _cutaway_names(ship, Vector3(-24, -3, 0))
	assert_true(in_hub0 == expected, "Hub0 hides rings 1 and 2, their ladders, Hub1, Hub2, bulkhead 2 and the aft end, not bulkhead 1 (got %s)" % [in_hub0])
	assert_true(_cutaway_names(ship, Vector3(24, -3, 0)).is_empty(), "Hub2 hides nothing")
	assert_true(_cutaway_names(ship, Vector3(24, -47, 0)).is_empty(), "ring 2 hides nothing")


func test_cutaway_keeps_the_players_own_slice() -> void:
	var ship := await _make_ship()
	# In the left half of Hub1, ring 1 lies wholly toward +X of the player, but its ladder runs through this room.
	var names := _cutaway_names(ship, Vector3(-9, -3, 2.5))
	for kept in _ring_with_ladder(1) + ["Hub1", "Bulkhead2"]:
		assert_true(kept not in names, "%s stays visible from the left half of Hub1 (got %s)" % [kept, names])


func test_every_hub_landing_is_lit() -> void:
	var ship := await _make_ship()
	var lights := ship.find_children("*", "OmniLight3D", true, false)
	for ladder in ship.ladders:
		var exit := ladder.landings[1].exit
		var nearest := INF
		for light: OmniLight3D in lights:
			nearest = minf(nearest, light.global_position.distance_to(exit))
		assert_true(nearest < 6.0, "a light within 6 m of the hub landing at %s (nearest %.1f m)" % [exit, nearest])


func test_crates_clear_of_spokes() -> void:
	var ship := await _make_ship()
	var crates := ship.find_children("Crate*", "StaticBody3D", true, false)
	assert_true(crates.size() == 3 * RingGeometry.SECTIONS * WheelShip.CRATES_PER_SECTION, "all crates are placed (got %d)" % crates.size())
	for ladder in ship.ladders:
		var spots := [ladder.landings[0].exit, ladder.landings[2].exit, ladder.start, ladder.point_at(ladder.length) + ladder.axis * Player.BODY_HEIGHT]
		for crate: Node3D in crates:
			for spot: Vector3 in spots:
				assert_true(crate.global_position.distance_to(spot) > 2.0, "%s is %.1f m from a ladder end at %s" % [crate.get_path(), crate.global_position.distance_to(spot), spot])
