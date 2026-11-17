extends TestCase


func test_dimensions() -> void:
	assert_near(RingGeometry.floor_apothem(), 48.296, 0.001, "floor apothem")
	assert_near(RingGeometry.floor_side_length(), 25.882, 0.001, "floor side length")
	assert_near(RingGeometry.ceiling_apothem(), 43.296, 0.001, "ceiling apothem")


func test_angle_of_round_trips_section_angle() -> void:
	for k in RingGeometry.SECTIONS:
		var angle := RingGeometry.angle_of(RingGeometry.section_down(k) * 48.0)
		var expected := wrapf(RingGeometry.section_angle(k), -PI, PI)
		assert_near(wrapf(angle - expected, -PI, PI), 0.0, 0.0001, "angle_of section %d" % k)


func test_section_of() -> void:
	for k in RingGeometry.SECTIONS:
		var p := RingGeometry.section_down(k) * 48.0 + Vector3(3, 0, 0)
		assert_true(RingGeometry.section_of(p) == k, "section_of section %d" % k)


func test_up_points_to_axis() -> void:
	assert_true(RingGeometry.up_at(Vector3(2, -10, 0)).is_equal_approx(Vector3.UP), "up at bottom")


func test_tangent_is_perpendicular_to_down() -> void:
	for k in RingGeometry.SECTIONS:
		assert_near(RingGeometry.section_tangent(k).dot(RingGeometry.section_down(k)), 0.0, 0.0001, "tangent ⟂ down %d" % k)
