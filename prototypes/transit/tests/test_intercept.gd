extends TestCase

const SPEED := Units.TRANSPORT_SPEED_KM_PER_DAY


func _use_all_bodies_at_angle_zero() -> void:
	Orbits.configure({Orbits.Body.EARTH: 0.0, Orbits.Body.MOON: 0.0, Orbits.Body.MARS: 0.0})


func _body_target(body: Orbits.Body) -> Callable:
	return func(day: float) -> Vector2: return Orbits.body_position(body, day)


func test_stationary_target() -> void:
	var target_at := func(_day: float) -> Vector2: return Vector2(SPEED, 0.0)
	var duration := Intercept.solve(Vector2.ZERO, 0.0, SPEED, target_at)
	assert_near(duration, 1.0, 1e-6, "one day to cover one day's flight")


func test_earth_to_moon() -> void:
	# The Moon travels with Earth at about 30 km/s around the Sun, so the
	# transport has to chase it: 0.113 d (2.7 h), not the 0.089 d (2.1 h) that
	# 384,400 km at 50 km/s would give against a stationary Moon.
	_use_all_bodies_at_angle_zero()
	var duration := Intercept.solve(
		Orbits.body_position(Orbits.Body.EARTH, 0.0), 0.0, SPEED, _body_target(Orbits.Body.MOON))
	assert_true(duration > 0.105 and duration < 0.12, "about 2.7 h, got %.4f d" % duration)


func test_earth_to_mars_closest() -> void:
	# Mars's sideways motion (about 24 km/s) makes the trip longer than the
	# straight-line 0.524 AU / speed = 18.2 d: the exact answer is the closed
	# form for a target moving at right angles, D / sqrt(v^2 - u^2).
	_use_all_bodies_at_angle_zero()
	var from := Orbits.body_position(Orbits.Body.EARTH, 0.0)
	var duration := Intercept.solve(from, 0.0, SPEED, _body_target(Orbits.Body.MARS))
	var straight_line_days := 0.524 * Units.AU_KM / SPEED
	assert_true(duration > straight_line_days and duration < straight_line_days + 4.0,
		"a little over the straight-line %.1f d, got %.2f d" % [straight_line_days, duration])


func test_moving_target_closed_form() -> void:
	var distance_km := 50000000.0
	var target_speed := 0.6 * SPEED
	var target_at := func(day: float) -> Vector2: return Vector2(distance_km, target_speed * day)
	var duration := Intercept.solve(Vector2.ZERO, 0.0, SPEED, target_at)
	var expected := distance_km / sqrt(SPEED * SPEED - target_speed * target_speed)
	assert_near(duration, expected, 1e-4, "closed-form intercept time")


func test_unreachable() -> void:
	var target_at := func(day: float) -> Vector2: return Vector2(1000.0 + 2.0 * SPEED * day, 0.0)
	assert_near(Intercept.solve(Vector2.ZERO, 0.0, SPEED, target_at), -1.0, 0.0, "fleeing target is unreachable")


func test_arrival_matches() -> void:
	_use_all_bodies_at_angle_zero()
	var start_day := 40.0
	var from := Orbits.body_position(Orbits.Body.EARTH, start_day)
	var duration := Intercept.solve(from, start_day, SPEED, _body_target(Orbits.Body.MARS))
	var target_position := Orbits.body_position(Orbits.Body.MARS, start_day + duration)
	assert_near(target_position.distance_to(from), SPEED * duration, 1000.0, "target is exactly in reach at arrival")
