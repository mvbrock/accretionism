extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON
const MARS := Orbits.Body.MARS
const SPEED := Units.TRANSPORT_SPEED_KM_PER_DAY
const LOCAL_SPEED := Units.LOCAL_SPEED_KM_PER_DAY
const MOON_TRIP_DAYS := 384400.0 / LOCAL_SPEED
const POSITION_TOLERANCE_KM := 1000.0


## Six cyclers (Aldrin I..VI, phases 0..650 step 130, alternating UP/DOWN) and no transports.
func _fleet_with_cyclers() -> Fleet:
	Orbits.configure({EARTH: 0.0, MOON: 0.0, MARS: 45.0})
	var fleet := Fleet.new()
	var names := ["Aldrin I", "Aldrin II", "Aldrin III", "Aldrin IV", "Aldrin V", "Aldrin VI"]
	for i in names.size():
		var direction := Cycler.Direction.UP if i % 2 == 0 else Cycler.Direction.DOWN
		fleet.cyclers.append(Cycler.new(names[i], direction, 130.0 * i))
	return fleet


func _parked(fleet: Fleet, ship_name: String, body: Orbits.Body) -> Transport:
	var transport := Transport.parked_at(ship_name, body)
	fleet.transports.append(transport)
	return transport


func _docked(fleet: Fleet, ship_name: String, host: Cycler) -> Transport:
	var transport := Transport.docked_to(ship_name, host)
	fleet.transports.append(transport)
	return transport


func test_valid_targets_excludes_current_place() -> void:
	var fleet := _fleet_with_cyclers()
	var parked := _parked(fleet, "Kestrel", EARTH)
	var expected: Array = [MOON, MARS]
	expected.append_array(fleet.cyclers)
	assert_true(fleet.valid_targets(parked) == expected, "parked at Earth: Moon, Mars, then all cyclers")

	var docked := _docked(fleet, "Wren", fleet.cyclers[0])
	var docked_targets := fleet.valid_targets(docked)
	assert_true(docked_targets.slice(0, 3) == [EARTH, MOON, MARS], "docked: all three bodies first")
	assert_true(docked_targets.slice(3) == fleet.cyclers.slice(1), "docked: the other five cyclers, in fleet order")


func test_a_ship_in_flight_keeps_its_destination() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MARS)
	fleet.advance_to(10.0)
	var arrival := transport.t_arrive
	assert_true(fleet.valid_targets(transport).is_empty(), "a ship in flight has nowhere else to go")
	for target in [EARTH, MOON, fleet.cyclers[0]]:
		assert_true(fleet.estimate_days(transport, target) < 0.0, "no estimate to %s" % Fleet.target_name(target))
		assert_true(not fleet.depart(transport, target), "can't be sent to %s" % Fleet.target_name(target))
	assert_true(transport.target == MARS and transport.t_arrive == arrival, "still headed to Mars on the same arrival day")


func test_depart_and_arrive_at_body() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	assert_true(fleet.depart(transport, MOON), "departure accepted")
	fleet.advance_to(fleet.day + 0.05)
	assert_true(transport.state == Transport.State.IN_TRANSIT, "still flying after 0.05 d")
	fleet.advance_to(transport.t_arrive)
	assert_true(transport.state == Transport.State.AT_BODY and transport.body == MOON, "parked at the Moon on arrival")


func test_arrive_at_cycler_docks() -> void:
	var fleet := _fleet_with_cyclers()
	var cycler := fleet.cyclers[0]
	fleet.advance_to(50.0)
	var transport := _parked(fleet, "Kestrel", EARTH)
	assert_true(fleet.depart(transport, cycler), "departure accepted")
	fleet.advance_to(transport.t_arrive)
	assert_true(transport.state == Transport.State.DOCKED and transport.host == cycler, "docked to the cycler")
	var later := transport.t_arrive + 100.0
	assert_near(fleet.position_of(transport, later).distance_to(cycler.position(later)), 0.0, POSITION_TOLERANCE_KM,
		"rides along with the cycler")


func test_estimate_matches_flight_for_parked_and_docked() -> void:
	var fleet := _fleet_with_cyclers()
	fleet.advance_to(30.0) # paused mid-leg: the cycler is not at a planet
	var parked := _parked(fleet, "Kestrel", EARTH)
	var docked := _docked(fleet, "Wren", fleet.cyclers[0])
	for transport in [parked, docked]:
		var estimate := fleet.estimate_days(transport, MARS)
		var departure_point := fleet.position_of(transport, fleet.day)
		assert_true(fleet.depart(transport, MARS), "%s departs" % transport.name)
		assert_near(transport.t_arrive - transport.t0, estimate, 1e-9, "%s: estimate equals the trip flown" % transport.name)
		assert_near(transport.t0, 30.0, 1e-9, "%s leaves at the current day" % transport.name)
		assert_near(transport.depart_point.distance_to(departure_point), 0.0, POSITION_TOLERANCE_KM,
			"%s leaves from where it is now" % transport.name)


func test_estimate_is_negative_for_invalid_target() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	assert_near(fleet.estimate_days(transport, EARTH), -1.0, 0.0, "can't target the current body")


func test_big_step_arrives_everyone() -> void:
	var fleet := _fleet_with_cyclers()
	var to_moon := _parked(fleet, "Kestrel", EARTH)
	var to_mars := _parked(fleet, "Heron", EARTH)
	var to_earth := _parked(fleet, "Osprey", MARS)
	var to_cycler := _parked(fleet, "Wren", EARTH)
	fleet.depart(to_moon, MOON)
	fleet.depart(to_mars, MARS)
	fleet.depart(to_earth, EARTH)
	fleet.depart(to_cycler, fleet.cyclers[1])
	fleet.advance_to(300.0)
	assert_true(to_moon.state == Transport.State.AT_BODY and to_moon.body == MOON, "Moon trip arrived")
	assert_true(to_mars.state == Transport.State.AT_BODY and to_mars.body == MARS, "Mars trip arrived")
	assert_true(to_earth.state == Transport.State.AT_BODY and to_earth.body == EARTH, "Earth trip arrived")
	assert_true(to_cycler.state == Transport.State.DOCKED, "cycler trip docked")
	assert_near(fleet.position_of(to_cycler, 300.0).distance_to(fleet.cyclers[1].position(300.0)), 0.0, POSITION_TOLERANCE_KM,
		"docked transport stays with its cycler after the big step")


func test_progress() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	assert_near(fleet.progress(transport), -1.0, 0.0, "parked ships have no progress")
	fleet.depart(transport, MARS)
	fleet.advance_to(transport.t0 + (transport.t_arrive - transport.t0) / 2.0)
	assert_near(fleet.progress(transport), 0.5, 1e-6, "halfway by time")


func test_rejects_invalid_targets() -> void:
	var fleet := _fleet_with_cyclers()
	var other := _parked(fleet, "Heron", MARS)
	var parked := _parked(fleet, "Kestrel", EARTH)
	var docked := _docked(fleet, "Wren", fleet.cyclers[0])
	assert_true(not fleet.depart(parked, other), "another transport is refused")
	assert_true(not fleet.depart(parked, EARTH), "the current body is refused")
	assert_true(not fleet.depart(docked, fleet.cyclers[0]), "the current host is refused")
	assert_true(parked.state == Transport.State.AT_BODY and parked.body == EARTH, "parked ship unchanged")
	assert_true(docked.state == Transport.State.DOCKED and docked.host == fleet.cyclers[0], "docked ship unchanged")


func test_target_names() -> void:
	var fleet := _fleet_with_cyclers()
	assert_true(Fleet.target_name(MARS) == "Mars", "body name")
	assert_true(Fleet.target_name(fleet.cyclers[2]) == "Aldrin III", "cycler name")


func test_earth_moon_trips_take_about_the_same_time_both_ways() -> void:
	var fleet := _fleet_with_cyclers()
	var from_earth := fleet.estimate_days(_parked(fleet, "Kestrel", EARTH), MOON)
	var from_moon := fleet.estimate_days(_parked(fleet, "Heron", MOON), EARTH)
	assert_near(from_earth, MOON_TRIP_DAYS, 0.03, "Earth to Moon is about 21 h")
	assert_near(from_moon, MOON_TRIP_DAYS, 0.03, "Moon to Earth is about 21 h")
	assert_near(from_earth, from_moon, 0.05, "the two directions are within about an hour of each other")


func test_local_estimate_equals_flown_time() -> void:
	var fleet := _fleet_with_cyclers()
	fleet.advance_to(10.0)
	var transport := _parked(fleet, "Kestrel", EARTH)
	var estimate := fleet.estimate_days(transport, MOON)
	fleet.depart(transport, MOON)
	assert_near(transport.t_arrive - transport.t0, estimate, 1e-9, "estimate equals the trip flown")


func test_local_transport_arrives_at_the_moon() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MOON)
	var moon_at_arrival := Orbits.body_position(MOON, transport.t_arrive)
	assert_near(fleet.position_of(transport, transport.t_arrive).distance_to(moon_at_arrival), 0.0, POSITION_TOLERANCE_KM,
		"position at arrival is the Moon's")


func test_local_transport_flies_at_local_speed_in_earths_frame() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MOON)
	var halfway := (transport.t0 + transport.t_arrive) / 2.0
	fleet.advance_to(halfway)
	assert_near(fleet.progress(transport), 0.5, 1e-6, "halfway by time")
	var earth_to_ship_km := fleet.position_of(transport, halfway).distance_to(Orbits.body_position(EARTH, halfway))
	assert_near(earth_to_ship_km, transport.leg_km / 2.0, POSITION_TOLERANCE_KM, "half the leg from Earth, in Earth's frame")
	assert_near(transport.leg_km, LOCAL_SPEED * (transport.t_arrive - transport.t0), 1.0, "leg length uses the local speed")


func test_other_legs_stay_in_the_sun_frame_at_full_speed() -> void:
	var fleet := _fleet_with_cyclers()
	var to_mars := _parked(fleet, "Kestrel", EARTH)
	var moon_to_cycler := _parked(fleet, "Heron", MOON)
	fleet.depart(to_mars, MARS)
	fleet.depart(moon_to_cycler, fleet.cyclers[1])
	for transport in [to_mars, moon_to_cycler]:
		assert_near(transport.leg_km, SPEED * (transport.t_arrive - transport.t0), 1.0, "%s flies at 50 km/s" % transport.name)
		assert_near(transport.depart_point.distance_to(Orbits.body_position(transport.body, 0.0)), 0.0, POSITION_TOLERANCE_KM,
			"%s's departure point is a Sun-frame position" % transport.name)
