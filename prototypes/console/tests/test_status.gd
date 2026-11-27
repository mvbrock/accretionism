extends TestCase

var _bands: Dictionary = Ship.default_params().status

func _level(row: String, value: float) -> Status.Level:
	return Status.classify(value, _bands[row])

func test_pressure_bounds() -> void:
	assert_true(_level("pressure_kpa", 95.0) == Status.Level.NOMINAL, "95 nominal")
	assert_true(_level("pressure_kpa", 94.9) == Status.Level.WARNING, "94.9 warning")
	assert_true(_level("pressure_kpa", 69.9) == Status.Level.DANGER, "69.9 danger")
	assert_true(_level("pressure_kpa", 110.0) == Status.Level.WARNING, "110 warning, no upper danger")

func test_o2_bounds() -> void:
	assert_true(_level("o2_kpa", 23.5) == Status.Level.NOMINAL, "23.5 nominal")
	assert_true(_level("o2_kpa", 19.0) == Status.Level.NOMINAL, "19 nominal")
	assert_true(_level("o2_kpa", 18.9) == Status.Level.WARNING, "18.9 warning")
	assert_true(_level("o2_kpa", 15.9) == Status.Level.DANGER, "15.9 danger")
	assert_true(_level("o2_kpa", 30.1) == Status.Level.DANGER, "30.1 danger")

func test_co2_bounds() -> void:
	assert_true(_level("co2_kpa", 0.5) == Status.Level.NOMINAL, "0.5 nominal")
	assert_true(_level("co2_kpa", 0.51) == Status.Level.WARNING, "0.51 warning")
	assert_true(_level("co2_kpa", 1.01) == Status.Level.DANGER, "1.01 danger")

func test_temperature_bounds() -> void:
	assert_true(_level("temperature_c", 18.0) == Status.Level.NOMINAL, "18 nominal")
	assert_true(_level("temperature_c", 9.9) == Status.Level.DANGER, "9.9 danger")
	assert_true(_level("temperature_c", 32.1) == Status.Level.DANGER, "32.1 danger")
	assert_true(_level("temperature_c", 30.0) == Status.Level.WARNING, "30 warning")

func test_tank_bounds() -> void:
	assert_true(_level("tank_percent", 25.0) == Status.Level.NOMINAL, "25 nominal")
	assert_true(_level("tank_percent", 24.0) == Status.Level.WARNING, "24 warning")
	assert_true(_level("tank_percent", 4.9) == Status.Level.DANGER, "4.9 danger")

func test_worst() -> void:
	assert_true(Status.worst([]) == Status.Level.NOMINAL, "empty is nominal")
	assert_true(Status.worst([Status.Level.WARNING, Status.Level.DANGER, Status.Level.NOMINAL]) == Status.Level.DANGER, "danger wins")
