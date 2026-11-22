extends TestCase

func _vent_cargo(ship: Ship) -> void:
	ship.set_opening("hatch", true)
	ship.advance(60.0)

func test_cargo_vents_alone_with_d2_closed() -> void:
	var ship := ShipFixture.make()
	var main_before := ship.room("main").pressure()
	var cockpit_before := ship.room("cockpit").pressure()
	_vent_cargo(ship)
	assert_true(ship.room("cargo").pressure() < 1000.0, "cargo below 1 kPa")
	assert_near(ship.room("main").pressure(), main_before, 50.0, "main unchanged")
	assert_near(ship.room("cockpit").pressure(), cockpit_before, 50.0, "cockpit unchanged")

func test_cargo_refills_after_hatch_closes() -> void:
	var ship := ShipFixture.make()
	_vent_cargo(ship)
	ship.set_opening("hatch", false)
	ship.advance(90.0)
	assert_near(ship.room("cargo").pressure(), 101300.0, 200.0, "cargo refilled")

func test_hvac_holds_setpoint() -> void:
	var ship := ShipFixture.make()
	ship.advance(7200.0)
	for room in ship.rooms:
		assert_near(Units.celsius(room.temperature), 21.0, 0.5, "%s temperature" % room.id)

func test_recycler_holds_co2_down() -> void:
	var ship := ShipFixture.make()
	ship.advance(86400.0)
	for room in ship.rooms:
		assert_true(room.partial_pressure("CO2") < 500.0, "%s CO2 below 0.5 kPa" % room.id)

func test_co2_rises_with_recycler_tripped() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("air-recycler")
	ship.advance(6 * 3600.0)
	assert_true(ship.room("cockpit").partial_pressure("CO2") > 1000.0, "cockpit CO2 above 1 kPa")

func test_o2_tank_steady_with_recycler() -> void:
	var ship := ShipFixture.make()
	ship.advance(86400.0)
	assert_true(3000.0 - ship.tanks["O2"].mol < 20.0, "O2 tank lost less than 20 mol")

func test_o2_tank_drains_without_recycler() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("air-recycler")
	ship.advance(86400.0)
	assert_true(3000.0 - ship.tanks["O2"].mol > 45.0, "O2 tank lost more than 45 mol")

func test_trip_removes_function() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("light-cargo")
	assert_true(not ship.light_lit("cargo"), "tripped light is dark")
	ship.breaker_trip("d1")
	assert_true(ship.set_opening("d1", true).result == Opening.CommandResult.NO_POWER, "tripped door has no power")
	ship.breaker_trip("pressure-control")
	_vent_cargo(ship)
	ship.set_opening("hatch", false)
	ship.advance(90.0)
	assert_true(ship.room("cargo").pressure() < 1000.0, "no refill without pressure control")
	ship.breaker_trip("hvac")
	ship.advance(1.0)
	for room in ship.rooms:
		assert_near(ship.last_hvac_w[room.id], 0.0, 0.0, "%s HVAC output" % room.id)

func test_reset_boots_system() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("hvac")
	ship.advance(0.5)
	ship.breaker_reset("hvac")
	ship.advance(0.5)
	assert_true(ship.systems["hvac"].state == SystemUnit.State.BOOTING, "booting after reset")
	ship.advance(7.0)
	assert_true(ship.systems["hvac"].state == SystemUnit.State.BOOTING, "still booting just under 8 s")
	ship.advance(1.0)
	assert_true(ship.systems["hvac"].state == SystemUnit.State.RUNNING, "running after 8 s")

func test_light_switch_survives_trip() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("light-main")
	assert_true(not ship.light_lit("main"), "dark while tripped")
	ship.breaker_reset("light-main")
	assert_true(ship.light_lit("main"), "lit again after reset")

func test_life_support_runs_with_computer_down() -> void:
	var ship := ShipFixture.make()
	ship.fault_system("computer")
	_vent_cargo(ship)
	ship.set_opening("hatch", false)
	ship.advance(90.0)
	assert_near(ship.room("cargo").pressure(), 101300.0, 200.0, "cargo refilled")

func test_long_frame_runs_whole_steps() -> void:
	var ship := ShipFixture.make()
	assert_true(ship.advance(25.0) == 250, "25 s is 250 steps")
	assert_true(ship.advance(0.05) == 0, "half a step runs nothing")
	assert_true(ship.advance(0.05) == 1, "the other half runs one")

func test_no_negative_moles_through_full_vent() -> void:
	var ship := ShipFixture.make()
	var d2 := ship.opening("d2")
	d2.fraction = 1.0
	d2.state = Opening.State.OPEN
	ship.breaker_trip("d2")
	ship.set_opening("hatch", true)
	ship.advance(300.0)
	for room in ship.rooms:
		for gas in Units.GASES:
			assert_true(room.mol[gas] >= 0.0, "%s %s not negative" % [room.id, gas])

func _random_trip_run() -> Ship:
	var ship := ShipFixture.make({"breakers": {"mean_time_between_trips_h": 0.01}})
	ship.set_opening("hatch", true)
	ship.advance(3600.0)
	return ship

func _trip_log(ship: Ship) -> Array:
	return ship.events.entries.filter(func(e: Dictionary) -> bool: return e.text.contains("breaker tripped"))

func test_same_seed_same_run() -> void:
	var a := _random_trip_run()
	var b := _random_trip_run()
	assert_true(not _trip_log(a).is_empty(), "at least one trip happened")
	assert_true(_trip_log(a) == _trip_log(b), "same trips at the same times")
	for room in a.rooms:
		for gas in Units.GASES:
			assert_near(room.mol[gas], b.room(room.id).mol[gas], 1e-9, "%s %s" % [room.id, gas])

func test_exposure_is_logged() -> void:
	var ship := ShipFixture.make()
	assert_true(ship.events.entries.is_empty(), "nothing logged at load")
	ship.set_opening("hatch", true)
	ship.advance(1.0)
	assert_true(ship.events.has_text("cargo: exposed to vacuum"), "exposure logged")
	assert_true(ship.events.has_text("pressure-control: not feeding cargo (exposed)"), "not feeding logged")
	ship.set_opening("hatch", false)
	ship.advance(10.0)
	assert_true(ship.events.has_text("cargo: sealed"), "sealed logged")

func test_empty_tank_is_logged_once() -> void:
	var ship := ShipFixture.make({"tanks": {"O2": {"start_mol": 1.0}}})
	_vent_cargo(ship)
	ship.set_opening("hatch", false)
	ship.advance(90.0)
	var count := ship.events.entries.filter(func(e: Dictionary) -> bool: return e.text == "O2 tank empty").size()
	assert_true(count == 1, "O2 tank empty logged exactly once (got %d)" % count)
