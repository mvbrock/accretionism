extends TestCase
## The skiff, tug and freighter: their rooms, doors, hatch, and that they hold their air.

const NO_TRIPS := ShipChecks.NO_TRIPS


func _tug() -> Ship:
	return TugShip.new(NO_TRIPS)


func _freighter() -> Ship:
	return FreighterShip.new(NO_TRIPS)


func _skiff() -> Ship:
	return SkiffShip.new(NO_TRIPS)


func _pipe_door_ids(decks: int) -> Array[String]:
	var ids: Array[String] = []
	for k in range(1, decks + 1):
		ids.append("deck%d-pipe%d" % [k, k])
	for k in range(1, decks):
		ids.append("pipe%d-pipe%d" % [k, k + 1])
	return ids


func _deck_room_ids(decks: int) -> Array[String]:
	var ids: Array[String] = []
	for k in range(1, decks + 1):
		ids.append("deck%d" % k)
	for k in range(1, decks + 1):
		ids.append("pipe%d" % k)
	return ids


func _check_hatch(ship: Ship, room_id: String, face: Room.Face) -> void:
	var hatches := ShipChecks.hatches(ship)
	assert_true(hatches.size() == 1, "one hatch, got %d" % hatches.size())
	if hatches.size() == 1:
		assert_true(hatches[0].id == "hatch", "hatch id %s" % hatches[0].id)
		assert_true(hatches[0].room_a == room_id, "hatch on %s" % hatches[0].room_a)
		assert_true(hatches[0].face_a == face, "hatch face %s" % hatches[0].face_a)


# Skiff

func test_skiff_rooms_and_doors() -> void:
	var ship := _skiff()
	assert_true(ShipChecks.room_ids(ship) == (["cockpit", "cabin", "hold"] as Array[String]), "rooms %s" % [ShipChecks.room_ids(ship)])
	assert_true(ShipChecks.door_ids(ship) == (["cockpit-cabin", "cabin-hold"] as Array[String]), "doors %s" % [ShipChecks.door_ids(ship)])
	assert_near(ship.room("cockpit").volume, 192.0, 1e-9, "cockpit")
	assert_near(ship.room("cabin").volume, 320.0, 1e-9, "cabin")
	assert_near(ship.room("hold").volume, 256.0, 1e-9, "hold")
	assert_true(ship.room("cockpit").passengers == 1 and ship.room("cabin").passengers == 1, "crew in cockpit and cabin")
	assert_true(ship.room("hold").passengers == 0, "hold is empty")

func test_skiff_hatch_is_on_the_holds_aft_wall() -> void:
	_check_hatch(_skiff(), "hold", Room.Face.PLUS_Z)

func test_skiff_doorways_are_2_by_3_2_at_floor_level() -> void:
	var door := _skiff().opening("cockpit-cabin")
	assert_true(door.size == Vector2(2.0, 3.2), "size %s" % door.size)
	assert_true(door.position.is_equal_approx(Vector3(0, 1.6, -6)), "position %s" % door.position)

func test_skiff_hatch_exposes_the_hold_and_the_rest_seals() -> void:
	var problems := ShipChecks.hatch_seal_problems(_skiff(), "hatch", SimClock.step_sizes().back())
	assert_true(problems.is_empty(), "seal: %s" % [problems])

func test_skiff_venting_is_stable_at_every_clock_step() -> void:
	for step_s in SimClock.step_sizes():
		var problems := ShipChecks.venting_problems(_skiff(), "hatch", step_s, 120.0)
		assert_true(problems.is_empty(), "step %s: %s" % [step_s, problems])


# Tug

func test_tug_rooms_and_doors() -> void:
	var ship := _tug()
	assert_true(ShipChecks.room_ids(ship) == _deck_room_ids(2), "rooms %s" % [ShipChecks.room_ids(ship)])
	assert_true(ShipChecks.door_ids(ship) == _pipe_door_ids(2), "doors %s" % [ShipChecks.door_ids(ship)])
	assert_near(ship.room("deck1").volume, 576.0, 1e-9, "deck volume")
	assert_near(ship.room("pipe1").volume, 1.4 * 4.4 * 1.4, 1e-4, "pipe volume")

func test_tug_hatch_is_in_the_bottom_decks_floor() -> void:
	_check_hatch(_tug(), "deck1", Room.Face.MINUS_Y)

func test_tug_hatch_exposes_deck1_and_the_rest_seals() -> void:
	var problems := ShipChecks.hatch_seal_problems(_tug(), "hatch", SimClock.step_sizes().back())
	assert_true(problems.is_empty(), "seal: %s" % [problems])

func test_tug_venting_is_stable_at_every_clock_step() -> void:
	for step_s in SimClock.step_sizes():
		var problems := ShipChecks.venting_problems(_tug(), "hatch", step_s, 120.0)
		assert_true(problems.is_empty(), "step %s: %s" % [step_s, problems])


# Freighter

func test_freighter_rooms_and_doors() -> void:
	var ship := _freighter()
	assert_true(ShipChecks.room_ids(ship) == _deck_room_ids(4), "rooms %s" % [ShipChecks.room_ids(ship)])
	assert_true(ShipChecks.door_ids(ship) == _pipe_door_ids(4), "doors %s" % [ShipChecks.door_ids(ship)])

func test_freighter_hatch_is_in_the_bottom_decks_floor() -> void:
	_check_hatch(_freighter(), "deck1", Room.Face.MINUS_Y)

func test_freighter_hatch_exposes_deck1_and_the_rest_seals() -> void:
	var problems := ShipChecks.hatch_seal_problems(_freighter(), "hatch", SimClock.step_sizes().back())
	assert_true(problems.is_empty(), "seal: %s" % [problems])

func test_freighter_venting_is_stable_at_every_clock_step() -> void:
	for step_s in SimClock.step_sizes():
		var problems := ShipChecks.venting_problems(_freighter(), "hatch", step_s, 120.0)
		assert_true(problems.is_empty(), "step %s: %s" % [step_s, problems])


# Deck ships

func test_each_deck_has_one_crew_member() -> void:
	for ship in [_tug(), _freighter()]:
		for room in ship.rooms:
			assert_true(room.passengers == (1 if room.id.begins_with("deck") else 0), "%s crew %d" % [room.id, room.passengers])

func test_a_pipe_door_is_floor_level_on_the_pipes_near_wall() -> void:
	var door := _tug().opening("deck2-pipe2")
	assert_true(door.size == Vector2(1.4, 2.6), "size %s" % door.size)
	assert_true(door.position.is_equal_approx(Vector3(3.5, 5.7, 6.0)), "position %s" % door.position)

func test_pipe_segments_join_ceiling_to_floor() -> void:
	var door := _freighter().opening("pipe2-pipe3")
	assert_true(door.face_a == Room.Face.PLUS_Y and door.face_b == Room.Face.MINUS_Y, "faces")
	assert_true(door.position.is_equal_approx(Vector3(3.5, 8.8, 6.7)), "position %s" % door.position)

func test_a_deck_ship_takes_any_deck_count() -> void:
	var ship := DeckShip.new(3, NO_TRIPS)
	assert_true(ship.rooms.size() == 6 and ShipChecks.door_ids(ship).size() == 5, "three decks: %d rooms" % ship.rooms.size())


# Scaling

func test_tanks_and_pressure_control_scale_with_volume() -> void:
	var small := ShipFixture.make()
	assert_near(small.tanks["O2"].capacity, 3000.0, 1e-9, "82 m3 ship keeps the reference tank")
	var tug := _tug()
	var factor := (2 * 576.0 + 2 * 1.4 * 4.4 * 1.4) / 82.0
	assert_near(tug.tanks["O2"].capacity, 3000.0 * factor, 0.05, "O2 capacity")
	assert_near(tug.tanks["O2"].mol, 3000.0 * factor, 0.05, "O2 start")
	assert_near(tug.tanks["N2"].capacity, 8000.0 * factor, 0.05, "N2 capacity")

func test_door_strength_scales_with_opening_area() -> void:
	var tug := _tug()
	assert_near(tug.opening("deck1-pipe1").conductance, 10.0 * 3.64 / 2.0, 1e-3, "conductance")
	assert_near(tug.opening("deck1-pipe1").mixing, 0.5 * 3.64 / 2.0, 1e-3, "mixing")
	assert_near(tug.opening("deck1-pipe1").heat_conductance, 100.0 * 3.64 / 2.0, 1e-3, "heat")
	var reference := ShipFixture.make().opening("d1")
	assert_near(reference.conductance, 10.0, 1e-9, "the 1 x 2 m reference door is unchanged")
	assert_near(tug.opening("hatch").conductance, 5.0, 1e-9, "hatches are not scaled")
