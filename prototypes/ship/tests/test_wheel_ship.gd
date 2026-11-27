extends TestCase

const L := 38.6


func _make_ship() -> WheelShip:
	var ship := WheelShip.new()
	own(ship)
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


## The ladder of the spoke on ring `ring` at section `k`.
func _ladder(ship: WheelShip, ring: int, k: int) -> Ladder:
	return ship.ladders[ring * WheelShip.SPOKE_SECTIONS.size() + WheelShip.SPOKE_SECTIONS.find(k)]


func test_rooms_and_gravity() -> void:
	var ship := await _make_ship()
	assert_true(ship.room_at(ship.spawn_point()) == "Ring1/Section0", "spawn is in the middle ring's section 0")
	assert_true(ship.has_gravity_at(ship.spawn_point()), "gravity in the ring")
	assert_true(ship.room_at(Vector3(0, -5, 0)) == "Hub", "inside the hub")
	assert_true(not ship.has_gravity_at(Vector3(0, -5, 0)), "no gravity in the hub")
	var frame := ship.spoke_frame(1, 2)
	assert_true(ship.room_at(frame * Vector3(0, 20, 0)) == "Spoke1_2", "inside the spoke's shaft")
	assert_true(ship.has_gravity_at(frame * Vector3(0, 20, 0)), "gravity in a spoke")


func test_spoke_ladders() -> void:
	var ship := await _make_ship()
	assert_true(ship.ladders.size() == 9, "nine ladders (got %d)" % ship.ladders.size())
	for ladder in ship.ladders:
		assert_true(ladder.landings.size() == 2, "two landings")
		if ladder.landings.size() != 2:
			continue
		assert_true(ship.room_at(ladder.landings[0].exit).begins_with("Ring"), "landing 0 is in a ring room")
		assert_true(ship.room_at(ladder.landings[1].exit) == "Hub", "landing 1 is in the hub")


func test_spoke_holes_open() -> void:
	var ship := await _make_ship()
	var frame := ship.spoke_frame(1, 6)
	var hit := _ray(frame * Vector3(0, 1, 0), frame * Vector3(0, ship.spoke_length() - 1.0, 0))
	assert_true(hit.is_empty(), "the pipe interior is clear through both slabs (hit %s)" % hit.get("collider"))


func test_collar_doorway_blocked_for_hatch() -> void:
	var ship := await _make_ship()
	var exit := _ladder(ship, 1, 6).landings[1].exit
	var frame := ship.spoke_frame(1, 6)
	var toward_axis := frame * Vector3(0, ship.spoke_length() + 1.0, 0)
	assert_true(not _ray(exit, toward_axis, Ship.HATCH_LAYER).is_empty(), "the collar's hatch blocks")
	assert_true(_ray(exit, toward_axis, Ship.WORLD_LAYER).is_empty(), "the collar's doorway is open to the world")


func test_hub_far_side_fades() -> void:
	var ship := await _make_ship()
	var faded := ship.room_fade_meshes(Vector3(0, -8, 0), Vector3(-0.58, -0.58, -0.58))
	var top := 0
	for mesh in faded:
		var y := mesh.mesh.get_aabb().get_center().y
		assert_true(y >= -5.0, "a hub panel at y = %.2f fades" % y)
		if y > 0.0:
			top += 1
	assert_true(top > 0, "hub panels on the far side fade")


func test_spoke_length_and_hub_geometry() -> void:
	var ship := await _make_ship()
	assert_near(ship.spoke_length(), L, 0.05, "spoke length")
	assert_true(ship.get_node("Hub/Section0/Floor").collision_layer & Ship.OCCLUDER_LAYER != 0, "hub floors can fade")
	assert_true(ship.get_node("Hub/Section0").get_node_or_null("Light") != null, "a hub light per section")
	assert_true(not ship.get_node("Hub/Section0/Light").shadow_enabled, "hub lights cast no shadows")
	assert_true(ship.has_node("HubCapFore/Cap0") and ship.has_node("HubCapAft/Cap0"), "hub end caps")
	assert_true(ship.has_node("Spoke1_2/RingSeg/PipeLeft") and ship.has_node("Spoke1_2/Shaft/PipeLeft") and ship.has_node("Spoke1_2/Collar/PipeCap"), "spoke segments")


func test_climb_spoke_into_hub_floats() -> void:
	var ship := await _make_ship()
	var player := own_player(ship)
	var ladder := _ladder(ship, 1, 2)
	player.board(ship, PlayerPose.new(ladder.landings[0].exit, Vector2(0, -1), true))
	await physics_frames(2)
	player.interact()
	assert_true(player.climbing == ladder, "grabbed the spoke's ladder")
	player.climb_speed = 30.0
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
