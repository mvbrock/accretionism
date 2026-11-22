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
	var expected: Array[String] = ["light-treehouse", "light-cockpit", "light-main", "light-cargo",
			"d0", "d1", "d2", "hatch", "pressure-control", "hvac", "air-recycler"]
	var ids := _ship().power.breaker_ids
	assert_true(ids == expected, str(ids))

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
	var trips_a := _trips(a)
	assert_true(trips_a.size() > 0, "some breakers tripped")
	assert_true(trips_a == _trips(b), "same trips at the same times")

func _trips(ship: Ship) -> Array:
	var trips := []
	for entry in ship.events.entries:
		if entry.text.ends_with("breaker tripped"):
			trips.append([entry.text, entry.time_s])
	return trips

func test_schematic_draws_rooms_and_doors_in_data_order() -> void:
	var view := DashboardView.new()
	own(view)
	view.show_ship(_ship())
	var order := _schematic_order(view)
	assert_true(order == ["TREEHOUSE", "d0", "COCKPIT", "d1", "MAIN", "d2", "CARGO", "hatch"], str(order))

func _schematic_order(view: DashboardView) -> Array[String]:
	var order: Array[String] = []
	for node in view.get_child(1).get_children():
		order.append(node.text.split("\n")[0] if node is Label else _tile_title(view, node))
	return order

func _tile_title(view: DashboardView, tile: Node) -> String:
	for room_id in ["treehouse", "cockpit", "main", "cargo"]:
		if view.tile(room_id) == tile:
			return room_id.to_upper()
	return "?"

func test_schematic_places_a_door_after_the_earlier_of_its_rooms() -> void:
	var data := ShipFixture.four_room_data()
	data.openings[0].between = ["cockpit", "treehouse"]
	var view := DashboardView.new()
	own(view)
	view.show_ship(ShipLoader.from_dict(data))
	var order := _schematic_order(view)
	assert_true(order == ["TREEHOUSE", "d0", "COCKPIT", "d1", "MAIN", "d2", "CARGO", "hatch"], str(order))
