extends TestCase

const P0 := 101300.0
const T0 := 294.15

func _room(id: String, volume: float, pressure_pa: float) -> Room:
	var room := Room.new(id, volume, T0, 0)
	room.heat_capacity = 5000.0 * volume
	room.hull_conductance = 0.5 * volume
	room.set_partial_pressure("O2", pressure_pa * 0.21)
	room.set_partial_pressure("N2", pressure_pa * 0.79)
	return room

func _door(id: String, a: String, b: String, fraction: float) -> Opening:
	var door := Opening.new(id, a, b, 2.0)
	door.conductance = 10.0
	door.mixing = 0.5
	door.heat_conductance = 100.0
	door.fraction = fraction
	return door

func _hatch(fraction: float) -> Opening:
	var hatch := Opening.new("hatch", "cargo", Opening.OUTSIDE, 6.0)
	hatch.conductance = 5.0
	hatch.fraction = fraction
	return hatch

func test_rooms_equalize_and_conserve_moles() -> void:
	var cockpit := _room("cockpit", 12.0, P0)
	var main := _room("main", 40.0, 50000.0)
	var door := _door("d1", "cockpit", "main", 1.0)
	var start := cockpit.total_mol() + main.total_mol()
	for i in 300:
		Atmosphere.flow_through_door(cockpit, main, door, 0.1)
	assert_near(cockpit.pressure(), 61838.0, 100.0, "cockpit settles")
	assert_near(main.pressure(), 61838.0, 100.0, "main settles")
	assert_near(cockpit.total_mol() + main.total_mol(), start, 1e-6, "moles conserved")

func test_closed_door_passes_nothing() -> void:
	var cockpit := _room("cockpit", 12.0, P0)
	var main := _room("main", 40.0, 50000.0)
	main.temperature = 280.0
	var door := _door("d1", "cockpit", "main", 0.0)
	var cockpit_mol := cockpit.total_mol()
	var main_mol := main.total_mol()
	for i in 50:
		Atmosphere.flow_through_door(cockpit, main, door, 0.1)
	assert_true(cockpit.total_mol() == cockpit_mol, "cockpit moles unchanged")
	assert_true(main.total_mol() == main_mol, "main moles unchanged")
	assert_true(cockpit.temperature == T0, "cockpit temperature unchanged")
	assert_true(main.temperature == 280.0, "main temperature unchanged")

func test_mixing_carries_co2_at_equal_pressure() -> void:
	var cockpit := _room("cockpit", 12.0, P0)
	var main := _room("main", 40.0, P0)
	main.set_partial_pressure("CO2", 1000.0)
	main.set_partial_pressure("N2", P0 * 0.79 - 1000.0)
	var door := _door("d1", "cockpit", "main", 1.0)
	for i in 100:
		Atmosphere.flow_through_door(cockpit, main, door, 0.1)
	assert_true(cockpit.mol["CO2"] > 0.0, "CO2 reaches the cockpit")

func test_heat_conducts_from_warm_to_cool() -> void:
	var cockpit := _room("cockpit", 12.0, P0)
	var main := _room("main", 40.0, P0)
	main.temperature = T0 + 10.0
	var door := _door("d1", "cockpit", "main", 1.0)
	var energy := cockpit.heat_capacity * cockpit.temperature + main.heat_capacity * main.temperature
	Atmosphere.flow_through_door(cockpit, main, door, 0.1)
	assert_true(cockpit.temperature > T0, "cool room warms")
	assert_true(main.temperature < T0 + 10.0, "warm room cools")
	var after := cockpit.heat_capacity * cockpit.temperature + main.heat_capacity * main.temperature
	assert_near(after, energy, 1e-3, "heat conserved")

func test_cargo_vents_on_schedule() -> void:
	var cargo := _room("cargo", 30.0, P0)
	var hatch := _hatch(1.0)
	for i in 60:
		Atmosphere.vent_through_hatch(cargo, hatch, 0.1)
	assert_near(cargo.pressure(), 37270.0, 100.0, "37.27 kPa after 6 s")
	for i in 240:
		Atmosphere.vent_through_hatch(cargo, hatch, 0.1)
	assert_true(cargo.pressure() < 1000.0, "below 1 kPa after 30 s")

func test_vent_returns_moles_lost() -> void:
	var cargo := _room("cargo", 30.0, P0)
	var before := cargo.total_mol()
	var lost := Atmosphere.vent_through_hatch(cargo, _hatch(1.0), 0.1)
	assert_near(lost, before - cargo.total_mol(), 1e-9, "returns what left")
	assert_true(lost > 0.0, "something left")

func test_whole_ship_vents_in_about_95_s() -> void:
	var cockpit := _room("cockpit", 12.0, P0)
	var main := _room("main", 40.0, P0)
	var cargo := _room("cargo", 30.0, P0)
	var d1 := _door("d1", "cockpit", "main", 1.0)
	var d2 := _door("d2", "main", "cargo", 1.0)
	var hatch := _hatch(1.0)
	var rooms := [cockpit, main, cargo]
	for i in 750:
		Atmosphere.flow_through_door(cockpit, main, d1, 0.1)
		Atmosphere.flow_through_door(main, cargo, d2, 0.1)
		Atmosphere.vent_through_hatch(cargo, hatch, 0.1)
	for room: Room in rooms:
		assert_true(room.pressure() > 1000.0, "%s still above 1 kPa at 75 s" % room.id)
	for i in 350:
		Atmosphere.flow_through_door(cockpit, main, d1, 0.1)
		Atmosphere.flow_through_door(main, cargo, d2, 0.1)
		Atmosphere.vent_through_hatch(cargo, hatch, 0.1)
	for room: Room in rooms:
		assert_true(room.pressure() < 1000.0, "%s below 1 kPa at 110 s" % room.id)

func test_unheated_room_cools() -> void:
	var main := _room("main", 40.0, P0)
	main.temperature = Units.kelvin(21.0)
	var hull := Units.kelvin(-20.0)
	for i in 36000:
		Atmosphere.add_heat(main, 140.0 * 0.1)
		Atmosphere.hull_loss(main, hull, 0.1)
	assert_near(Units.celsius(main.temperature), 10.72, 0.1, "settles toward 10.72 C after 1 h")
