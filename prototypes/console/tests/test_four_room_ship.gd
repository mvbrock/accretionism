extends TestCase

func _ship(mean_trip_h := 0.0) -> Ship:
	var data := ShipFixture.four_room_data()
	data.breakers.mean_time_between_trips_h = mean_trip_h
	return ShipLoader.from_dict(data)

func test_loads_with_a_breaker_per_room_light_and_opening() -> void:
	var ship := _ship()
	assert_true(ship != null, "four-room data loads")
	assert_true(ship.power.has("light-treehouse"), "light-treehouse")
	assert_true(ship.power.has("d0"), "d0")

func test_breaker_order_is_lights_then_openings_then_systems() -> void:
	var expected: Array[String] = ["light-cockpit", "light-main", "light-cargo", "light-treehouse",
			"d0", "d1", "d2", "hatch", "pressure-control", "hvac", "air-recycler"]
	assert_true(_ship().power.breaker_ids == expected, str(_ship().power.breaker_ids))

func test_steps_for_a_minute_without_errors() -> void:
	var ship := _ship()
	ship.set_opening("d0", true)
	ship.advance(60.0)
	assert_true(ship.total_draw_w() > 0.0, "draws power")
	assert_near(ship.room("treehouse").pressure(), ship.room("cockpit").pressure(), 200.0, "treehouse shares cockpit air")

func test_same_seed_gives_the_same_trips() -> void:
	var a := _ship(0.01)
	var b := _ship(0.01)
	for i in 600:
		a.step()
		b.step()
	assert_true(a.events.entries.size() > 0, "some breakers tripped")
	assert_true(a.power.tripped == b.power.tripped, "same breakers tripped")
	assert_true(a.events.entries.size() == b.events.entries.size(), "same events")
