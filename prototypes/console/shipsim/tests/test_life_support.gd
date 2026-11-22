extends TestCase

const DT := 0.1
const SETPOINTS := {"O2": 21200.0, "N2": 80100.0}

func _tanks(o2_mol := 3000.0, n2_mol := 8000.0) -> Dictionary:
	return {"O2": Tank.new("O2", 3000.0, o2_mol), "N2": Tank.new("N2", 8000.0, n2_mol)}

func _main_room(co2_pa: float) -> Room:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.set_partial_pressure("O2", 21200.0)
	room.set_partial_pressure("N2", 80100.0)
	room.set_partial_pressure("CO2", co2_pa)
	return room

func test_refill_cargo_from_vacuum() -> void:
	var cargo := Room.new("cargo", 30.0, 294.15, 0)
	var tanks := _tanks()
	for i in 600:
		LifeSupport.pressure_control(cargo, false, tanks, SETPOINTS, 20.0, DT)
	assert_near(cargo.pressure(), 101300.0, 100.0, "refilled to 101.3 kPa")
	assert_near(cargo.partial_pressure("O2"), 21200.0, 50.0, "ppO2 at setpoint")

func test_never_feeds_exposed_room() -> void:
	var cargo := Room.new("cargo", 30.0, 294.15, 0)
	cargo.mol["O2"] = 5.0
	var tanks := _tanks()
	for i in 100:
		LifeSupport.pressure_control(cargo, true, tanks, SETPOINTS, 20.0, DT)
	assert_near(cargo.total_mol(), 5.0, 0.0, "room moles unchanged")
	assert_near(tanks["O2"].mol, 3000.0, 0.0, "O2 tank unchanged")
	assert_near(tanks["N2"].mol, 8000.0, 0.0, "N2 tank unchanged")

func test_empty_o2_tank_stops_only_o2() -> void:
	var cargo := Room.new("cargo", 30.0, 294.15, 0)
	var tanks := _tanks(0.0)
	for i in 600:
		LifeSupport.pressure_control(cargo, false, tanks, SETPOINTS, 20.0, DT)
	assert_near(cargo.partial_pressure("N2"), 80100.0, 50.0, "N2 reaches setpoint")
	assert_near(cargo.partial_pressure("O2"), 0.0, 0.0, "O2 stays 0")

func test_hvac_output_clamped() -> void:
	var room := Room.new("main", 40.0, Units.kelvin(0.0), 0)
	assert_near(LifeSupport.hvac_heat_w(room, Units.kelvin(21.0), 5000.0, 1500.0), 1500.0, 1e-9, "heating clamped")
	room.temperature = Units.kelvin(30.0)
	assert_near(LifeSupport.hvac_heat_w(room, Units.kelvin(21.0), 5000.0, 1500.0), -1500.0, 1e-9, "cooling clamped")

func test_recycler_returns_o2_one_for_one() -> void:
	var room := _main_room(1000.0)
	var tank := Tank.new("O2", 3000.0, 1000.0)
	var co2_before: float = room.mol["CO2"]
	var removed := LifeSupport.recycle(room, false, tank, 300.0, 10000.0, 0.01, DT)
	assert_near(removed, 0.001, 1e-9, "removed at the rate limit")
	assert_near(co2_before - room.mol["CO2"], 0.001, 1e-9, "room lost the CO2")
	assert_near(tank.mol, 1000.001, 1e-9, "tank gained the same moles")

func test_recycler_stops_at_target() -> void:
	var room := _main_room(300.0)
	var tank := Tank.new("O2", 3000.0, 1000.0)
	assert_near(LifeSupport.recycle(room, false, tank, 300.0, 10000.0, 0.01, DT), 0.0, 1e-9, "nothing above target")

func test_recycler_skips_vacuum() -> void:
	var room := Room.new("main", 40.0, 294.15, 0)
	room.set_partial_pressure("CO2", 5000.0)
	var tank := Tank.new("O2", 3000.0, 1000.0)
	assert_near(LifeSupport.recycle(room, false, tank, 300.0, 10000.0, 0.01, DT), 0.0, 0.0, "below min pressure")
	assert_near(tank.mol, 1000.0, 0.0, "tank untouched")

func test_passengers_stop_breathing_without_o2() -> void:
	var room := Room.new("main", 40.0, 294.15, 2)
	room.set_partial_pressure("N2", 80100.0)
	room.set_partial_pressure("CO2", 100.0)
	var co2_before: float = room.mol["CO2"]
	LifeSupport.breathe(room, 0.01, 0.008, DT)
	assert_near(room.mol["CO2"], co2_before, 0.0, "no O2, no CO2 produced")
	for gas in Units.GASES:
		assert_true(room.mol[gas] >= 0.0, "%s never negative" % gas)

func test_breathe_scales_by_passengers() -> void:
	var room := Room.new("main", 40.0, 294.15, 2)
	room.mol["O2"] = 100.0
	room.mol["CO2"] = 1.0
	LifeSupport.breathe(room, 0.01, 0.008, DT)
	assert_near(room.mol["O2"], 100.0 - 0.002, 1e-9, "O2 used by two passengers")
	assert_near(room.mol["CO2"], 1.0 + 0.0016, 1e-9, "CO2 made by two passengers")

func test_breathe_starved_scales_co2() -> void:
	var room := Room.new("main", 40.0, 294.15, 2)
	room.mol["O2"] = 0.001  # half of the 0.002 the passengers need this step
	room.mol["CO2"] = 1.0
	LifeSupport.breathe(room, 0.01, 0.008, DT)
	assert_near(room.mol["O2"], 0.0, 1e-12, "all O2 used")
	assert_near(room.mol["CO2"], 1.0 + 0.0008, 1e-9, "half the CO2")

func test_recycler_skips_exposed_room() -> void:
	var room := _main_room(1000.0)
	var tank := Tank.new("O2", 3000.0, 1000.0)
	assert_near(LifeSupport.recycle(room, true, tank, 300.0, 10000.0, 0.01, DT), 0.0, 0.0, "exposed")
	assert_near(tank.mol, 1000.0, 0.0, "tank untouched")

func test_recycler_with_full_tank_discards_o2() -> void:
	var room := _main_room(1000.0)
	var tank := Tank.new("O2", 3000.0, 3000.0)
	var removed := LifeSupport.recycle(room, false, tank, 300.0, 10000.0, 0.01, DT)
	assert_near(removed, 0.001, 1e-9, "CO2 still removed")
	assert_near(tank.mol, 3000.0, 0.0, "tank stays at capacity")
