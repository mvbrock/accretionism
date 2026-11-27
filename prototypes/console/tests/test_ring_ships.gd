extends TestCase
## The ring and the Wheel: their segments, spokes and hub, hatches, and that they hold their air.

const NO_TRIPS := ShipChecks.NO_TRIPS


func _ring() -> Ship:
	return RingShip.new(NO_TRIPS)


func _wheel() -> Ship:
	return WheelShip.new(NO_TRIPS)


func _segment_ids(prefix: String) -> Array[String]:
	var ids: Array[String] = []
	for k in 12:
		ids.append("%s%d" % [prefix, k])
	return ids


func _segment_door_ids(prefix: String) -> Array[String]:
	var ids: Array[String] = []
	for k in 12:
		ids.append("%s%d-%s%d" % [prefix, k, prefix, (k + 1) % 12])
	return ids


func _check_shape(ship: Ship) -> void:
	assert_true(ShipChecks.overfull_rooms(ship).is_empty(), "over six doors: %s" % [ShipChecks.overfull_rooms(ship)])
	assert_true(ShipChecks.unreachable_rooms(ship).is_empty(), "unreachable: %s" % [ShipChecks.unreachable_rooms(ship)])
	assert_true(ShipChecks.misplaced_doors(ship).is_empty(), "doors off their faces: %s" % [ShipChecks.misplaced_doors(ship)])


func _check_hatches(ship: Ship, expected: Dictionary) -> void:
	var found := {}
	for hatch in ShipChecks.hatches(ship):
		found[hatch.id] = [hatch.room_a, hatch.face_a]
	assert_true(found == expected, "hatches %s" % [found])


# Ring

func test_ring_rooms_and_doors() -> void:
	var ship := _ring()
	assert_true(ShipChecks.room_ids(ship) == _segment_ids("s"), "rooms %s" % [ShipChecks.room_ids(ship)])
	assert_true(ShipChecks.door_ids(ship) == _segment_door_ids("s"), "doors %s" % [ShipChecks.door_ids(ship)])
	_check_shape(ship)

func test_ring_segments_are_the_corridor_between_floor_and_ceiling() -> void:
	var segment := _ring().room("s0")
	assert_near(segment.volume, 1227.1, 0.1, "the floor and ceiling panels' trapezoid")
	assert_true(segment.position.is_equal_approx(Vector3(0, -45.796, 0)), "s0 hangs straight down: %s" % segment.position)
	var door := _ring().opening("s0-s1")
	assert_true(door.size == Vector2(10, 5), "the corridor's full cross-section: %s" % door.size)
	assert_near(door.conductance, 250.0, 1e-3, "conductance")

func test_ring_crew() -> void:
	for room in _ring().rooms:
		var crew := 1 if room.id in ["s0", "s3", "s6", "s9"] else 0
		assert_true(room.passengers == crew, "%s crew %d" % [room.id, room.passengers])

func test_ring_hatches_are_in_s0s_and_s6s_outer_floors() -> void:
	_check_hatches(_ring(), {"hatch0": ["s0", Room.Face.MINUS_Y], "hatch6": ["s6", Room.Face.MINUS_Y]})

func test_ring_holds_its_air_for_a_day_with_doors_open() -> void:
	var problems := ShipChecks.steady_state_problems(_ring())
	assert_true(problems.is_empty(), "steady state: %s" % [problems])

func test_ring_hatches_expose_their_segment_and_the_rest_seals() -> void:
	for hatch_id in ["hatch0", "hatch6"]:
		var problems := ShipChecks.hatch_seal_problems(_ring(), hatch_id)
		assert_true(problems.is_empty(), "%s: %s" % [hatch_id, problems])

func test_ring_venting_is_stable_at_both_step_sizes() -> void:
	for step_s in [0.1, 1.0]:
		var problems := ShipChecks.venting_problems(_ring(), "hatch0", step_s, 120.0)
		assert_true(problems.is_empty(), "step %s: %s" % [step_s, problems])


# Wheel

func test_wheel_rooms_and_doors() -> void:
	var ship := _wheel()
	var rooms: Array[String] = []
	var doors: Array[String] = []
	for ring in ["a", "b", "c"]:
		rooms.append_array(_segment_ids(ring))
		doors.append_array(_segment_door_ids(ring))
	for ring in ["a", "b", "c"]:
		for k in [0, 6]:
			rooms.append("spoke%s%d" % [ring, k])
			doors.append_array(["%s%d-spoke%s%d" % [ring, k, ring, k], "spoke%s%d-hub" % [ring, k]])
	rooms.append("hub")
	assert_true(ShipChecks.room_ids(ship) == rooms, "rooms %s" % [ShipChecks.room_ids(ship)])
	assert_true(ShipChecks.door_ids(ship) == doors, "doors %s" % [ShipChecks.door_ids(ship)])
	_check_shape(ship)

func test_wheel_hub_has_exactly_six_doors_one_per_spoke() -> void:
	var doors := _wheel().doors_of("hub")
	assert_true(doors.size() == 6, "hub doors %d" % doors.size())
	for door in doors:
		assert_true(door.id.begins_with("spoke") and door.id.ends_with("-hub"), "door %s" % door.id)

func test_wheel_rings_sit_24_m_apart_along_the_axis() -> void:
	var ship := _wheel()
	var axial := {"a": -24.0, "b": 0.0, "c": 24.0}
	for ring in axial:
		var segment := ship.room("%s0" % ring)
		assert_true(segment.position.is_equal_approx(Vector3(axial[ring], -45.796, 0)), "%s0 at %s" % [ring, segment.position])

func test_wheel_spokes_reach_from_the_ring_ceiling_to_the_prototype_hub() -> void:
	var ship := _wheel()
	var hub := ship.room("hub")
	assert_near(hub.size.y, 2.0 * 10.0 * cos(deg_to_rad(15.0)), 1e-3, "hub as across as prototypes/ship's")
	assert_near(hub.size.x, 60.0, 1e-9, "hub length")
	var spoke := ship.room("spokeb6")
	assert_near(spoke.size.z, 40.0 * cos(deg_to_rad(15.0)) - 5.0, 1e-3, "ceiling to hub")
	assert_true(Vector2(spoke.size.x, spoke.size.y).is_equal_approx(Vector2(1.4, 1.4)), "a 1.4 m square ladder pipe")
	assert_true(ship.opening("b6-spokeb6").position.is_equal_approx(Vector3(0, 43.296, 0)), "b6's ceiling centre")
	assert_true(ship.opening("spokeb6-hub").position.is_equal_approx(Vector3(0, hub.size.y / 2.0, 0)), "hub's ceiling")

func test_wheel_crew() -> void:
	for room in _wheel().rooms:
		var crew := 1 if room.id in ["hub", "b0", "a3", "c9"] else 0
		assert_true(room.passengers == crew, "%s crew %d" % [room.id, room.passengers])

func test_wheel_hatch_is_in_b3s_outer_floor() -> void:
	_check_hatches(_wheel(), {"hatch": ["b3", Room.Face.MINUS_Y]})

func test_wheel_holds_its_air_for_a_day_with_doors_open() -> void:
	var problems := ShipChecks.steady_state_problems(_wheel())
	assert_true(problems.is_empty(), "steady state: %s" % [problems])

func test_wheel_hatch_exposes_b3_and_the_rest_seals() -> void:
	var problems := ShipChecks.hatch_seal_problems(_wheel(), "hatch")
	assert_true(problems.is_empty(), "seal: %s" % [problems])

func test_wheel_venting_is_stable_at_both_step_sizes() -> void:
	for step_s in [0.1, 1.0]:
		var problems := ShipChecks.venting_problems(_wheel(), "hatch", step_s, 120.0)
		assert_true(problems.is_empty(), "step %s: %s" % [step_s, problems])
