extends TestCase

func test_partial_pressure_from_moles() -> void:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.mol["O2"] = 1000.0
	assert_near(room.partial_pressure("O2"), 61142.48, 0.01, "nRT/V")
	assert_near(room.pressure(), 61142.48, 0.01, "only O2 present")

func test_setpoint_air_is_101_3_kpa() -> void:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.set_partial_pressure("O2", 21200.0)
	room.set_partial_pressure("N2", 80100.0)
	assert_near(room.pressure(), 101300.0, 1e-6, "sum of partial pressures")
	assert_near(room.share("O2"), 21200.0 / 101300.0, 1e-9, "O2 share")

func test_vacuum_has_zero_shares() -> void:
	var room := Room.new("cargo", 30.0, 294.15, 0)
	assert_near(room.pressure(), 0.0, 0.0, "empty room")
	assert_near(room.share("O2"), 0.0, 0.0, "no divide by zero")

func test_mol_for_round_trips() -> void:
	var n := Room.mol_for(101300.0, 30.0, 294.15)
	assert_near(n, 1242.59, 0.01, "PV/RT for the cargo hold")
