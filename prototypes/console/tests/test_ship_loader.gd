extends TestCase

func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/ship.json"))

func test_loads_three_rooms_at_setpoint() -> void:
	var ship := ShipLoader.load_file("res://data/ship.json")
	assert_true(ship.rooms.size() == 3, "three rooms")
	for room in ship.rooms:
		assert_near(room.pressure(), 101340.0, 10.0, "%s pressure" % room.id)
		assert_near(room.partial_pressure("CO2"), 40.0, 0.5, "%s CO2" % room.id)
		assert_near(Units.celsius(room.temperature), 21.0, 0.001, "%s temperature" % room.id)

func test_missing_key_is_reported() -> void:
	var data := _data()
	data.erase("tanks")
	expect_error("missing 'tanks'")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_unknown_room_in_opening_is_reported() -> void:
	var data := _data()
	data.openings[0].between = ["cockpit", "galley"]
	expect_error("unknown room 'galley'")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_bad_room_volume_is_reported() -> void:
	var data := _data()
	data.rooms[0].volume_m3 = 0
	expect_error("volume 0")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_negative_passenger_count_is_reported() -> void:
	var data := _data()
	data.rooms[1].passengers = -1
	expect_error("room 'main' has passengers -1; it must be a whole number of at least 0")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_fractional_passenger_count_is_reported() -> void:
	var data := _data()
	data.rooms[1].passengers = 1.5
	expect_error("room 'main' has passengers 1.5; it must be a whole number of at least 0")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_temperature_below_absolute_zero_is_reported() -> void:
	var data := _data()
	data.rooms[0].start.temperature_c = -300
	expect_error("-300")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_bad_tank_capacity_is_reported() -> void:
	var data := _data()
	data.tanks.O2.capacity_mol = 0
	expect_error("tank 'O2' has capacity 0")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_outside_first_is_reported() -> void:
	var data := _data()
	data.openings[2].between = ["outside", "cargo"]
	expect_error("opening 'hatch'")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_opening_to_itself_is_reported() -> void:
	var data := _data()
	data.openings[0].between = ["main", "main"]
	expect_error("opening 'd1'")
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func _assert_rejected(data: Dictionary, message: String) -> void:
	expect_error(message)
	assert_true(ShipLoader.from_dict(data) == null, "no ship from bad data")

func test_room_missing_key_is_reported() -> void:
	var data := _data()
	data.rooms[0].erase("passengers")
	_assert_rejected(data, "room is missing 'passengers'")

func test_room_start_missing_key_is_reported() -> void:
	var data := _data()
	data.rooms[0].start.erase("co2_kpa")
	_assert_rejected(data, "room 'cockpit' start is missing 'co2_kpa'")

func test_duplicate_room_is_reported() -> void:
	var data := _data()
	data.rooms[1].id = "cockpit"
	_assert_rejected(data, "duplicate room 'cockpit'")

func test_opening_missing_key_is_reported() -> void:
	var data := _data()
	data.openings[0].erase("travel_s")
	_assert_rejected(data, "opening is missing 'travel_s'")

func test_duplicate_opening_is_reported() -> void:
	var data := _data()
	data.openings[1].id = "d1"
	_assert_rejected(data, "duplicate opening 'd1'")

func test_opening_joining_three_places_is_reported() -> void:
	var data := _data()
	data.openings[0].between = ["cockpit", "main", "cargo"]
	_assert_rejected(data, "opening 'd1' must join exactly two places")

func test_missing_tank_is_reported() -> void:
	var data := _data()
	data.tanks.erase("N2")
	_assert_rejected(data, "missing tank 'N2'")

func test_no_outside_opening_is_reported() -> void:
	var data := _data()
	data.openings[2].between = ["cargo", "main"]
	_assert_rejected(data, "exactly one opening to outside")

func test_two_outside_openings_are_reported() -> void:
	var data := _data()
	data.openings[1].between = ["cargo", "outside"]
	_assert_rejected(data, "exactly one opening to outside")

func test_outside_opening_not_named_hatch_is_reported() -> void:
	var data := _data()
	data.openings[1].between = ["cargo", "outside"]
	data.openings[2].between = ["cargo", "main"]
	_assert_rejected(data, "opening to outside is 'd2', which must be 'hatch'")

func test_tank_missing_capacity_is_reported() -> void:
	var data := _data()
	data.tanks.O2.erase("capacity_mol")
	_assert_rejected(data, "tank 'O2' is missing 'capacity_mol'")

func test_tank_missing_start_is_reported() -> void:
	var data := _data()
	data.tanks.O2.erase("start_mol")
	_assert_rejected(data, "tank 'O2' is missing 'start_mol'")

func test_tank_start_above_capacity_is_reported() -> void:
	var data := _data()
	data.tanks.O2.start_mol = data.tanks.O2.capacity_mol + 1
	_assert_rejected(data, "tank 'O2' starts at")

func test_tank_start_below_zero_is_reported() -> void:
	var data := _data()
	data.tanks.O2.start_mol = -1
	_assert_rejected(data, "tank 'O2' starts at -1")

func test_opening_named_after_a_system_breaker_is_reported() -> void:
	var data := _data()
	data.openings[0].id = "hvac"
	_assert_rejected(data, "opening 'hvac' has the same id as a breaker")

func test_opening_named_after_a_room_light_is_reported() -> void:
	var data := _data()
	data.openings[0].id = "light-main"
	_assert_rejected(data, "opening 'light-main' has the same id as a breaker")

func test_room_and_opening_ids_are_free() -> void:
	var data := _data()
	data.rooms[0].id = "galley"
	data.openings[0].between = ["galley", "main"]
	data.openings[0].id = "d9"
	assert_true(ShipLoader.from_dict(data) != null, "any room and door ids load")

func test_tank_starting_empty_is_accepted() -> void:
	var data := _data()
	data.tanks.O2.start_mol = 0
	assert_true(ShipLoader.from_dict(data) != null, "empty tank loads")

func test_tank_starting_full_is_accepted() -> void:
	var data := _data()
	data.tanks.O2.start_mol = data.tanks.O2.capacity_mol
	assert_true(ShipLoader.from_dict(data) != null, "full tank loads")
