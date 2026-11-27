extends TestCase

const EARTH := Orbits.Body.EARTH
const MARS := Orbits.Body.MARS
const POSITION_TOLERANCE_KM := 1000.0


func _use_default_epoch() -> void:
	Orbits.configure({EARTH: 0.0, Orbits.Body.MOON: 0.0, MARS: 45.0})


func _assert_leg(leg: Dictionary, from: Orbits.Body, to: Orbits.Body, start_day: float, end_day: float, label: String) -> void:
	assert_true(leg.from == from and leg.to == to, "%s: from/to were %s -> %s" % [label, leg.from, leg.to])
	assert_near(leg.start_day, start_day, 1e-9, "%s: start day" % label)
	assert_near(leg.end_day, end_day, 1e-9, "%s: end day" % label)


func test_up_leg_durations() -> void:
	var cycler := Cycler.new("Up", Cycler.Direction.UP, 0.0)
	_assert_leg(cycler.leg_at(10.0), EARTH, MARS, 0.0, 146.0, "short leg")
	_assert_leg(cycler.leg_at(200.0), MARS, EARTH, 146.0, 780.0, "long leg")


func test_down_mirrors() -> void:
	var cycler := Cycler.new("Down", Cycler.Direction.DOWN, 130.0)
	_assert_leg(cycler.leg_at(140.0), MARS, EARTH, 130.0, 276.0, "short leg")
	_assert_leg(cycler.leg_at(300.0), EARTH, MARS, 276.0, 910.0, "long leg")


func test_flybys_meet_planets() -> void:
	_use_default_epoch()
	for cycler in [Cycler.new("Up", Cycler.Direction.UP, 0.0), Cycler.new("Down", Cycler.Direction.DOWN, 130.0)]:
		var boundary: float = cycler.phase_day
		for leg_number in 10:
			var leg: Dictionary = cycler.leg_at(boundary + 0.5)
			var planet_at_boundary := Orbits.body_position(leg.from, boundary)
			assert_near(cycler.position(boundary).distance_to(planet_at_boundary), 0.0, POSITION_TOLERANCE_KM,
				"%s meets %s on day %s" % [cycler.name, leg.from, boundary])
			boundary = leg.end_day


func test_negative_days() -> void:
	_use_default_epoch()
	var cycler := Cycler.new("Up", Cycler.Direction.UP, 260.0)
	var leg := cycler.leg_at(-100.0)
	_assert_leg(leg, MARS, EARTH, -374.0, 260.0, "long leg before day 0")
	var start := Orbits.body_position(MARS, -374.0)
	var end := Orbits.body_position(EARTH, 260.0)
	var expected := start.lerp(end, (-100.0 - -374.0) / 634.0)
	assert_near(cycler.position(-100.0).distance_to(expected), 0.0, POSITION_TOLERANCE_KM, "position on the line between the planets")


func test_progress() -> void:
	var cycler := Cycler.new("Up", Cycler.Direction.UP, 0.0)
	assert_near(cycler.progress(73.0), 0.5, 1e-9, "halfway through the short leg")


func test_last_flyby() -> void:
	var cycler := Cycler.new("Up", Cycler.Direction.UP, 0.0)
	assert_true(cycler.last_flyby(10.0) == EARTH, "Earth on the way out")
	assert_true(cycler.last_flyby(200.0) == MARS, "Mars on the way back")


func test_never_faster_than_transport() -> void:
	_use_default_epoch()
	var cycler := Cycler.new("Up", Cycler.Direction.UP, 0.0)
	var day := 0.0
	while day < 10.0 * Cycler.cycle_days:
		var leg := cycler.leg_at(day)
		var distance_km: float = Orbits.body_position(leg.from, leg.start_day).distance_to(Orbits.body_position(leg.to, leg.end_day))
		var speed: float = distance_km / (leg.end_day - leg.start_day)
		assert_true(speed < Units.TRANSPORT_SPEED_KM_PER_DAY, "leg starting day %s runs at %.0f km/d" % [leg.start_day, speed])
		day = leg.end_day + 0.5
