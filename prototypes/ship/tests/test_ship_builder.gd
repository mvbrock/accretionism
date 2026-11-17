extends TestCase


func _make_ship() -> ShipBuilder:
	var ship: ShipBuilder = own(ShipBuilder.new())
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
		seen[ShipBuilder.section_color(k).to_html()] = true
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
