extends TestCase


func _make_hull() -> RingHull:
	var hull := RingHull.new()
	hull.room_prefix = "R/"
	hull.center_x = 10.0
	return hull


func _build(hull: RingHull) -> Ship:
	var ship: Ship = own(Ship.new())
	hull.build(ship, ship)
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func test_floor_at_apothem() -> void:
	var hull := _make_hull()
	await _build(hull)
	var down := RingGeometry.section_down(3)
	var origin := Vector3(10, 0, 0)
	var hit := _ray(origin, origin + down * (hull.floor_apothem() + 5.0), Ship.FLOOR_LAYER)
	assert_true(not hit.is_empty(), "floor hit")
	if not hit.is_empty():
		assert_near(hit.position.distance_to(origin), hull.floor_apothem(), 0.01, "floor distance")


func test_room_at() -> void:
	var hull := _make_hull()
	await _build(hull)
	var p := RingGeometry.section_down(4) * (hull.floor_apothem() - 1.0)
	assert_true(hull.room_at(p + Vector3(10, 0, 0)) == "R/Section4", "inside the hull")
	assert_true(hull.room_at(p + Vector3(30, 0, 0)) == "", "beyond the hull's width")


func test_ceiling_hole() -> void:
	var hull := _make_hull()
	hull.add_ceiling_hole(2, 12.0, 0.85)
	await _build(hull)
	var down := RingGeometry.section_down(2)
	var through := _ray(Vector3(12, 0, 0) + down * (hull.ceiling_apothem() - 2.0), Vector3(12, 0, 0) + down * (hull.ceiling_apothem() + 1.0))
	assert_true(through.is_empty(), "ray passes through the hole")
	var beside := _ray(Vector3(8, 0, 0) + down * (hull.ceiling_apothem() - 2.0), Vector3(8, 0, 0) + down * (hull.ceiling_apothem() + 1.0))
	assert_true(not beside.is_empty() and str(beside.collider.name).begins_with("Ceiling"), "ray beside the hole hits the ceiling")


func test_second_hole_in_a_section_is_an_error() -> void:
	var hull := _make_hull()
	hull.add_ceiling_hole(2, 12.0, 0.85)
	expect_error("already has a ceiling hole")
	hull.add_ceiling_hole(2, 8.0, 0.85)


func test_defaults_keep_ring_floor_and_lights() -> void:
	var ship := await _build(_make_hull())
	var panel: StaticBody3D = ship.get_node("Section0/Floor")
	assert_true(panel.collision_layer == (Ship.WORLD_LAYER | Ship.FLOOR_LAYER), "floor on world and floor layers")
	assert_true(ship.get_node("Section0").has_node("Light"), "a light per section")
