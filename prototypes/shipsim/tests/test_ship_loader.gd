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
