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
	for id in PowerPanel.BREAKER_IDS:
		expected += ship.draw_w(id)
	assert_near(ship.total_draw_w(), expected, 0.001, "total")
