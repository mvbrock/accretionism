extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON
const MARS := Orbits.Body.MARS
const SPEED := Units.TRANSPORT_SPEED_KM_PER_DAY
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


func test_valid_targets_in_flight_allows_everything() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MARS)
	assert_true(fleet.valid_targets(transport).size() == 3 + 6, "a ship in flight isn't at any place")


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


func test_redirect_progress() -> void:
	var fleet := _fleet_with_cyclers()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MARS)
	fleet.advance_to(10.0)
	assert_true(fleet.depart(transport, EARTH), "redirecting back to the starting body is allowed in flight")
	assert_true(transport.origin_name == "Earth", "origin is unchanged by a redirect")
	assert_near(transport.flown_before_km, 10.0 * SPEED, 1.0, "ten days of flying counted")
	fleet.advance_to(12.0)
	var expected := (transport.flown_before_km + 2.0 * SPEED) / (transport.flown_before_km + transport.leg_km)
	assert_near(fleet.progress(transport), expected, 1e-6, "progress counts the earlier flying in both numbers")


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
