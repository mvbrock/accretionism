extends TestCase


func _make_ship() -> RingShip:
	var ship: RingShip = own(RingShip.new())
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func test_builds_twelve_sections_with_panels() -> void:
	var ship := await _make_ship()
	for k in RingGeometry.SECTIONS:
		var section := ship.get_node_or_null("Section%d" % k)
		assert_true(section != null, "Section%d exists" % k)
		if section:
			for panel in ["Floor", "Ceiling", "WallLeft", "WallRight"]:
				assert_true(section.has_node(panel), "Section%d/%s exists" % [k, panel])


func test_floor_surface_at_apothem() -> void:
	var ship := await _make_ship()
	for k in [0, 4, 9]:
		var down := RingGeometry.section_down(k)
		var hit := _ray(down * 47.0, down * 49.0)
		assert_true(not hit.is_empty() and hit.collider == ship.get_node("Section%d/Floor" % k), "floor hit in section %d" % k)
		if not hit.is_empty():
			assert_near(hit.position.distance_to(down * 47.0), RingGeometry.floor_apothem() - 47.0, 0.01, "floor distance %d" % k)


func test_right_wall_at_half_width() -> void:
	var ship := await _make_ship()
	var hit := _ray(Vector3(0, -46, 0), Vector3(8, -46, 0))
	assert_true(not hit.is_empty() and hit.collider == ship.get_node("Section0/WallRight"), "right wall hit")
	if not hit.is_empty():
		assert_near(hit.position.x, 5.0, 0.01, "wall x")


func test_ceiling_is_occluder() -> void:
	var ship := await _make_ship()
	var hit := _ray(Vector3(0.5, 0, 0), RingGeometry.section_down(3) * 46.0, 2)
	assert_true(not hit.is_empty() and hit.collider == ship.get_node("Section3/Ceiling"), "ceiling hit on occluder layer")
	if not hit.is_empty():
		assert_true(hit.collider.get_meta("fade_mesh", null) is MeshInstance3D, "ceiling has fade_mesh")


func test_section_colors_distinct() -> void:
	var seen := {}
	for k in RingGeometry.SECTIONS:
		seen[Ship.room_color(k, RingGeometry.SECTIONS).to_html()] = true
	assert_true(seen.size() == RingGeometry.SECTIONS, "12 distinct colors")


func test_crates_rest_on_floor() -> void:
	var ship := await _make_ship()
	var crates := ship.get_node("Crates").get_children()
	assert_true(crates.size() == 24, "24 crates (got %d)" % crates.size())
	for crate: StaticBody3D in crates:
		var size: float = crate.get_meta("size")
		var outward := RingGeometry.section_down(RingGeometry.section_of(crate.global_position))
		var space := tree.root.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(crate.global_position, crate.global_position + outward * (size / 2.0 + 0.05))
		query.exclude = [crate.get_rid()]
		var hit := space.intersect_ray(query)
		assert_true(not hit.is_empty() and hit.collider.name == "Floor", "%s rests on a floor" % crate.name)


func test_up_at_matches_ring_geometry() -> void:
	var ship := await _make_ship()
	var p := RingGeometry.section_down(3) * 47.0 + Vector3(2, 0, 0)
	assert_true(ship.up_at(p).is_equal_approx(RingGeometry.up_at(p)), "up_at delegates to RingGeometry")


func test_camera_roll_is_angle_around_axis() -> void:
	var ship := await _make_ship()
	assert_near(ship.camera_roll_at(RingGeometry.section_down(4) * 47.0),
			wrapf(RingGeometry.section_angle(4), -PI, PI), 0.001, "roll")


func test_room_fade_meshes_by_position() -> void:
	var ship := await _make_ship()
	var p := RingGeometry.section_down(5) * 46.0
	# The real camera always looks down at the player's section, so the views include that component.
	var look_down := RingGeometry.section_down(5) * 0.58 + RingGeometry.section_tangent(5) * 0.58
	var right := ship.room_fade_meshes(p, (Vector3(0.58, 0, 0) + look_down).normalized())
	assert_true(right == [ship.get_node("Section5/Ceiling/Mesh"), ship.get_node("Section5/WallLeft/Mesh")], "view +x fades ceiling and left wall")
	var left := ship.room_fade_meshes(p, (Vector3(-0.58, 0, 0) + look_down).normalized())
	assert_true(left == [ship.get_node("Section5/Ceiling/Mesh"), ship.get_node("Section5/WallRight/Mesh")], "view -x fades ceiling and right wall")


func test_spawn_point_is_on_section_zero_floor() -> void:
	var ship := await _make_ship()
	var spawn := ship.spawn_point()
	assert_true(RingGeometry.section_of(spawn) == 0, "spawn in section 0")
	assert_near(spawn.length(), RingGeometry.floor_apothem() - 0.05, 0.01, "spawn height")


func test_only_floors_on_floor_layer() -> void:
	var ship := await _make_ship()
	var down := RingGeometry.section_down(2)
	var hit := _ray(down * 40.0, down * 49.0, Ship.FLOOR_LAYER)
	assert_true(not hit.is_empty() and hit.collider == ship.get_node("Section2/Floor"), "floor ray hits the floor")
	for crate: StaticBody3D in ship.get_node("Crates").get_children():
		assert_true(crate.collision_layer & Ship.FLOOR_LAYER == 0, "%s is not on the floor layer" % crate.name)
