extends TestCase

var _bands: Dictionary = Ship.default_params().status

func _level(row: String, value: float) -> Status.Level:
	return Status.classify(value, _bands[row])

func test_pressure_bounds() -> void:
	assert_true(_level("pressure_kpa", 95.0) == Status.Level.NORMAL, "95 normal")
	assert_true(_level("pressure_kpa", 94.9) == Status.Level.DANGER, "94.9 danger")
	assert_true(_level("pressure_kpa", 69.9) == Status.Level.CRITICAL, "69.9 critical")
	assert_true(_level("pressure_kpa", 110.0) == Status.Level.DANGER, "110 danger, no upper critical limit")

func test_o2_bounds() -> void:
	assert_true(_level("o2_kpa", 23.5) == Status.Level.NORMAL, "23.5 normal")
	assert_true(_level("o2_kpa", 19.0) == Status.Level.NORMAL, "19 normal")
	assert_true(_level("o2_kpa", 18.9) == Status.Level.DANGER, "18.9 danger")
	assert_true(_level("o2_kpa", 15.9) == Status.Level.CRITICAL, "15.9 critical")
	assert_true(_level("o2_kpa", 30.1) == Status.Level.CRITICAL, "30.1 critical")

func test_co2_bounds() -> void:
	assert_true(_level("co2_kpa", 0.5) == Status.Level.NORMAL, "0.5 normal")
	assert_true(_level("co2_kpa", 0.51) == Status.Level.DANGER, "0.51 danger")
	assert_true(_level("co2_kpa", 1.01) == Status.Level.CRITICAL, "1.01 critical")

func test_temperature_bounds() -> void:
	assert_true(_level("temperature_c", 18.0) == Status.Level.NORMAL, "18 normal")
	assert_true(_level("temperature_c", 9.9) == Status.Level.CRITICAL, "9.9 critical")
	assert_true(_level("temperature_c", 32.1) == Status.Level.CRITICAL, "32.1 critical")
	assert_true(_level("temperature_c", 30.0) == Status.Level.DANGER, "30 danger")

func test_tank_bounds() -> void:
	assert_true(_level("tank_percent", 25.0) == Status.Level.NORMAL, "25 normal")
	assert_true(_level("tank_percent", 24.0) == Status.Level.DANGER, "24 danger")
	assert_true(_level("tank_percent", 4.9) == Status.Level.CRITICAL, "4.9 critical")

func test_worst() -> void:
	assert_true(Status.worst([]) == Status.Level.NORMAL, "empty is normal")
	assert_true(Status.worst([Status.Level.DANGER, Status.Level.CRITICAL, Status.Level.NORMAL]) == Status.Level.CRITICAL, "critical wins")
