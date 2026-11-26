extends TestCase

const POSITION_TOLERANCE_KM := 1000.0


func _assert_same_position(a: Vector2, b: Vector2, message: String) -> void:
	assert_near(a.distance_to(b), 0.0, POSITION_TOLERANCE_KM, message)


func _use_default_epoch() -> void:
	Orbits.configure({Orbits.Body.EARTH: 0.0, Orbits.Body.MOON: 0.0, Orbits.Body.MARS: 45.0})


func test_earth_radius_and_period() -> void:
	_use_default_epoch()
	for day in [0.0, 17.0, 100.5, 300.0]:
		assert_near(Orbits.body_position(Orbits.Body.EARTH, day).length(), Units.AU_KM, POSITION_TOLERANCE_KM, "Earth radius on day %s" % day)
	_assert_same_position(Orbits.body_position(Orbits.Body.EARTH, 365.256), Orbits.body_position(Orbits.Body.EARTH, 0.0), "Earth repeats after one period")


func test_mars_radius_and_period() -> void:
	_use_default_epoch()
	for day in [0.0, 17.0, 100.5, 600.0]:
		assert_near(Orbits.body_position(Orbits.Body.MARS, day).length(), 1.524 * Units.AU_KM, POSITION_TOLERANCE_KM, "Mars radius on day %s" % day)
	_assert_same_position(Orbits.body_position(Orbits.Body.MARS, 686.98), Orbits.body_position(Orbits.Body.MARS, 0.0), "Mars repeats after one period")


func test_moon_orbits_earth() -> void:
	_use_default_epoch()
	for day in [0.0, 5.0, 20.0]:
		var offset := Orbits.body_position(Orbits.Body.MOON, day) - Orbits.body_position(Orbits.Body.EARTH, day)
		assert_near(offset.length(), 384400.0, POSITION_TOLERANCE_KM, "Moon distance on day %s" % day)
	var offset_now := Orbits.body_position(Orbits.Body.MOON, 3.0) - Orbits.body_position(Orbits.Body.EARTH, 3.0)
	var offset_later := Orbits.body_position(Orbits.Body.MOON, 3.0 + 27.32) - Orbits.body_position(Orbits.Body.EARTH, 3.0 + 27.32)
	_assert_same_position(offset_now, offset_later, "Moon offset repeats after 27.32 d")


func test_epoch_angles() -> void:
	Orbits.configure({Orbits.Body.EARTH: 90.0, Orbits.Body.MOON: 0.0, Orbits.Body.MARS: 0.0})
	var direction := Orbits.body_position(Orbits.Body.EARTH, 0.0).normalized()
	assert_near(direction.distance_to(Vector2(0, 1)), 0.0, 1e-4, "Earth at 90 degrees points along +y")


func test_prograde() -> void:
	_use_default_epoch()
	var angle_day_0 := Orbits.body_position(Orbits.Body.EARTH, 0.0).angle()
	var angle_day_1 := Orbits.body_position(Orbits.Body.EARTH, 1.0).angle()
	assert_true(angle_day_1 > angle_day_0, "Earth's angle increases (counter-clockwise)")


func test_negative_days() -> void:
	_use_default_epoch()
	_assert_same_position(Orbits.body_position(Orbits.Body.MARS, -686.98), Orbits.body_position(Orbits.Body.MARS, 0.0), "Mars one period before epoch")


func test_body_names() -> void:
	assert_true(Orbits.body_name(Orbits.Body.EARTH) == "Earth", "Earth name")
	assert_true(Orbits.body_name(Orbits.Body.MOON) == "Moon", "Moon name")
	assert_true(Orbits.body_name(Orbits.Body.MARS) == "Mars", "Mars name")


func test_format_distance() -> void:
	assert_true(Units.format_distance(384400.0) == "384,400.00 km", "got %s" % Units.format_distance(384400.0))
	assert_true(Units.format_distance(0.999) == "1.00 km", "rounds up into the next km, got %s" % Units.format_distance(0.999))
	assert_true(Units.format_distance(78400000.0) == "78.40 M km", "got %s" % Units.format_distance(78400000.0))


func test_format_duration() -> void:
	assert_true(Units.format_duration(31.1667) == "31.17 d", "got %s" % Units.format_duration(31.1667))
	assert_true(Units.format_duration(0.0875) == "0.09 d", "got %s" % Units.format_duration(0.0875))
