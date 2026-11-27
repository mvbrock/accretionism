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
	assert_true(ship.room_at(Vector3(0, -5, 0)) == "Hub1", "inside the middle hub room")
	assert_true(not ship.has_gravity_at(Vector3(0, -5, 0)), "no gravity in a hub room")
	assert_true(ship.room_at(Vector3(-24, 5, 0)) == "Hub0", "inside the first hub room")
	var frame := ship.spoke_frame(1, 0)
	assert_true(ship.room_at(frame * Vector3(0, 20, 0)) == "Spoke1_0", "inside the spoke's shaft")
	assert_true(ship.has_gravity_at(frame * Vector3(0, 20, 0)), "gravity in a spoke")


func test_two_spokes_per_ring() -> void:
	var ship := await _make_ship()
	assert_true(ship.ladders.size() == 6, "six ladders (got %d)" % ship.ladders.size())
	for ladder in ship.ladders:
		assert_near(ladder.length, RingGeometry.floor_apothem() - 6.0, 0.01, "a spoke runs from the ring's floor to the hub room's")
		assert_true(ladder.landings.size() == 2, "two landings")
		if ladder.landings.size() != 2:
			continue
		assert_true(ship.room_at(ladder.landings[0].exit).begins_with("Ring"), "landing 0 is in a ring room")
		assert_true(ship.room_at(ladder.landings[1].exit).begins_with("Hub"), "landing 1 is in a hub room")


func test_spoke_holes_open() -> void:
	var ship := await _make_ship()
	for k: int in WheelShip.SPOKE_SECTIONS:
		var frame := ship.spoke_frame(1, k)
		var hit := _ray(frame * Vector3(0, 1, 0), frame * Vector3(0, ship.spoke_length() - 0.5, 0))
		assert_true(hit.is_empty(), "spoke (1, %d)'s interior is clear through the ring and the hub slab (hit %s)" % [k, hit.get("collider")])


func test_hub_nodes() -> void:
	var ship := await _make_ship()
	for i in 3:
		var room := "Hub%d" % i
		for panel_name in ["Floora", "Ceilinga", "WallLeft", "WallRight"]:
			var panel: StaticBody3D = ship.get_node("%s/%s" % [room, panel_name])
			assert_true(panel.collision_layer == (Ship.WORLD_LAYER | Ship.FLOOR_LAYER | Ship.OCCLUDER_LAYER), "%s/%s is on every panel layer" % [room, panel_name])
		var light: OmniLight3D = ship.get_node("%s/Light" % room)
		assert_true(light.position.is_equal_approx(Vector3(WheelShip.RING_CENTERS[i], 0, 0)) and light.omni_range == 16.0, "%s has a light at its center" % room)
	for end in ["HubEndFore", "HubEndAft"]:
		assert_true(ship.has_node(end), "%s closes the row" % end)
	for bulkhead in ["Bulkhead1", "Bulkhead2"]:
		assert_true(ship.has_node(bulkhead + "/Left") and ship.has_node(bulkhead + "/Right"), "%s has two pieces" % bulkhead)
	assert_true(ship.has_node("Spoke1_0/RingSeg/PipeLeft") and ship.has_node("Spoke1_0/Shaft/PipeLeft"), "spoke segments")
	assert_true(not ship.has_node("Spoke1_0/Collar"), "no collar")


func test_doorway_between_hub_rooms() -> void:
	var ship := await _make_ship()
	assert_true(_ray(Vector3(-6, -4, 0), Vector3(6, -4, 0)).is_empty(), "nothing inside a hub room")
	assert_true(_ray(Vector3(6, -4, 0), Vector3(18, -4, 0)).is_empty(), "the doorway is open")
	var wall := _ray(Vector3(6, -4, 4), Vector3(18, -4, 4))
	assert_true(not wall.is_empty() and ship.get_path_to(wall.collider) == ^"Bulkhead2/Right", "beside the doorway is bulkhead 2 (hit %s)" % wall.get("collider"))
	var end := _ray(Vector3(-30, -4, 0), Vector3(-40, -4, 0))
	assert_true(not end.is_empty() and end.collider.name == "HubEndFore", "the fore end is solid (hit %s)" % end.get("collider"))


func test_hub_far_side_fades() -> void:
	var ship := await _make_ship()
	var faded := ship.room_fade_meshes(Vector3(0, -4, 0), Vector3(-0.58, -0.58, -0.58))
	var names := []
	for mesh in faded:
		names.append(ship.get_path_to(mesh.get_parent()))
	assert_true(names.any(func(n: NodePath) -> bool: return str(n).begins_with("Hub1/Ceiling")), "the ceiling fades")
	assert_true(names.has(^"Hub1/WallRight"), "the wall on the camera's side fades")
	assert_true(not names.any(func(n: NodePath) -> bool: return str(n).begins_with("Hub1/Floor")), "the floor under the player stays")
	assert_true(not names.has(^"Hub1/WallLeft"), "the far wall stays")


func test_climb_spoke_into_hub_floats() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	var ladder := ship.spoke_ladder(1, 0)
	player.board(ship, PlayerPose.new(ladder.landings[0].exit, Vector2(0, -1), true))
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed the spoke's ladder")
	player.climb_speed = 40.0
	player.move_input = Vector2(0, 1)
	var frames := 0
	while player.climb_s < ladder.length - 0.1 and frames < 120:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	assert_true(player.climb_s >= ladder.length - 0.1, "reached the top within 120 frames (s = %.2f)" % player.climb_s)
	player.interact()
	assert_true(player.climbing == null, "let go at the top")
	assert_true(not player.gravity_enabled, "floating in the hub")
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed the ladder again from the hub")
	player.move_input = Vector2(0, -1)
	frames = 0
	while player.climb_s > 0.1 and frames < 120:
		await tree.physics_frame
		frames += 1
	player.move_input = Vector2.ZERO
	player.interact()
	assert_true(player.climbing == null, "let go at the bottom")
	assert_true(player.gravity_enabled, "gravity back in the ring")
	await physics_frames(30)
	assert_true(player.is_on_floor(), "standing on the ring floor")


func test_ceiling_spoke_arrival_floats_off_the_ceiling() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	player.board(ship, PlayerPose.new(ship.spoke_ladder(1, 6).landings[1].exit, Vector2(0, -1), false))
	await physics_frames(180)
	var from_ceiling := WheelShip.HUB_HALF_SIZE - player.global_position.y
	assert_near(from_ceiling, Player.FLOAT_HEIGHT, 0.2, "floats off the ceiling, which is its floor")
	assert_true(ship.room_at(player.global_position) == "Hub1", "still in the hub room")


func test_float_through_hub_doorway() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	player.board(ship, PlayerPose.new(Vector3(0, -WheelShip.HUB_HALF_SIZE + 0.05, 0), Vector2(1, 0), false))
	await physics_frames(180)
	player.move_input = Vector2(0, 1)
	await physics_frames(10)
	player.move_input = Vector2.ZERO
	await physics_frames(300)
	assert_true(ship.room_at(player.global_position) == "Hub2", "drifted through the doorway into the next room (at %s)" % player.global_position)


## The names of the nodes `ship.cutaway_nodes(p)` returns.
func _cutaway_names(ship: WheelShip, p: Vector3) -> Array:
	var names := []
	for node in ship.cutaway_nodes(p):
		names.append(str(node.name))
	names.sort()
	return names


func _ring_with_spokes(ring: int) -> Array:
	var names := ["Ring%d" % ring]
	for k: int in WheelShip.SPOKE_SECTIONS:
		names.append("Spoke%d_%d" % [ring, k])
	return names


func test_cutaway() -> void:
	var ship := await _make_ship()
	var expected := _ring_with_spokes(2) + ["Hub2", "Bulkhead2", "HubEndAft"]
	expected.sort()
	assert_true(_cutaway_names(ship, ship.spawn_point()) == expected, "ring 1 hides ring 2, its spokes, Hub2, bulkhead 2 and the aft end")
	expected = _ring_with_spokes(1) + _ring_with_spokes(2) + ["Hub1", "Hub2", "Bulkhead2", "HubEndAft"]
	expected.sort()
	var in_hub0 := _cutaway_names(ship, Vector3(-24, -4, 0))
	assert_true(in_hub0 == expected, "Hub0 hides rings 1 and 2, their spokes, Hub1, Hub2, bulkhead 2 and the aft end, not bulkhead 1 (got %s)" % [in_hub0])
	assert_true(_cutaway_names(ship, Vector3(24, -4, 0)).is_empty(), "Hub2 hides no bulkhead or end wall")
	assert_true(_cutaway_names(ship, Vector3(24, -47, 0)) == ["HubEndAft"], "ring 2 hides only the aft end wall beyond it")


func test_every_hub_landing_is_lit() -> void:
	var ship := await _make_ship()
	var lights := ship.find_children("*", "OmniLight3D", true, false)
	for ladder in ship.ladders:
		var exit := ladder.landings[1].exit
		var nearest := INF
		for light: OmniLight3D in lights:
			nearest = minf(nearest, light.global_position.distance_to(exit))
		assert_true(nearest < 9.0, "a light within 9 m of the hub landing at %s (nearest %.1f m)" % [exit, nearest])


func test_crates_clear_of_spokes() -> void:
	var ship := await _make_ship()
	var crates := ship.find_children("Crate*", "StaticBody3D", true, false)
	assert_true(crates.size() == 3 * RingGeometry.SECTIONS * WheelShip.CRATES_PER_SECTION, "all crates are placed (got %d)" % crates.size())
	for ladder in ship.ladders:
		for crate: Node3D in crates:
			for spot in [ladder.landings[0].exit, ladder.start]:
				assert_true(crate.global_position.distance_to(spot) > 2.0, "%s is %.1f m from a spoke foot at %s" % [crate.get_path(), crate.global_position.distance_to(spot), spot])
