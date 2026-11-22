extends TestCase

func test_idle_ship_draw() -> void:
	var ship := ShipFixture.make()
	ship.advance(1.0)
	assert_near(ship.draw_w("light-main"), 40.0, 0.001, "lit light")
	assert_near(ship.draw_w("d1"), 5.0, 0.001, "idle door")
	assert_near(ship.computer_draw_w(), 150.0, 0.001, "computer")

func test_moving_door_draw() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("d1", true)
	ship.advance(0.5)
	assert_near(ship.draw_w("d1"), 200.0, 0.001, "moving door")

func test_tripped_breaker_draws_nothing() -> void:
	var ship := ShipFixture.make()
	ship.advance(1.0)
	ship.breaker_trip("hvac")
	assert_near(ship.draw_w("hvac"), 0.0, 0.001, "tripped hvac")

func test_total_is_sum() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("d1", true)
	ship.advance(5.0)
	var expected := ship.computer_draw_w()
	for id in ship.power.breaker_ids:
		expected += ship.draw_w(id)
	assert_near(ship.total_draw_w(), expected, 0.001, "total")

func test_moving_hatch_draw() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("hatch", true)
	ship.advance(0.5)
	assert_near(ship.draw_w("hatch"), 500.0, 0.001, "moving hatch")

func test_hvac_draw_is_base_plus_heat() -> void:
	var ship := ShipFixture.make()
	ship.room("main").temperature = Units.kelvin(10.0)
	ship.advance(5.0)
	var heat := 0.0
	for room_id in ship.last_hvac_w:
		heat += absf(ship.last_hvac_w[room_id])
	assert_true(heat > 0.0, "hvac is heating")
	assert_near(ship.draw_w("hvac"), 200.0 + heat, 0.001, "hvac draw")

func test_recycler_draw() -> void:
	var ship := ShipFixture.make()
	ship.advance(1.0)
	assert_near(ship.draw_w("air-recycler"), 50.0, 0.001, "idle recycler")
	ship.room("main").set_partial_pressure("CO2", 500.0)
	ship.advance(0.1)
	assert_true(ship.recycler_scrubbing, "scrubbing")
	assert_near(ship.draw_w("air-recycler"), 800.0, 0.001, "scrubbing recycler")

func test_pressure_control_draw() -> void:
	var ship := ShipFixture.make()
	ship.advance(1.0)
	assert_near(ship.draw_w("pressure-control"), 300.0, 0.001, "pressure control")

func test_light_off_draws_nothing() -> void:
	var ship := ShipFixture.make()
	ship.set_light("main", false)
	assert_near(ship.draw_w("light-main"), 0.0, 0.001, "unlit light")
