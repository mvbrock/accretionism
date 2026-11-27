extends TestCase


func test_the_standard_fleet_is_one_of_each_ship_type_in_order() -> void:
	var fleet := Fleet.standard()
	assert_true(fleet.names() == PackedStringArray(["ring", "skiff", "tug", "freighter", "wheel"]), "got %s" % fleet.names())
	assert_true(fleet.ships.ring is RingShip, "ring is a RingShip")
	assert_true(fleet.ships.skiff is SkiffShip, "skiff is a SkiffShip")
	assert_true(fleet.ships.tug is TugShip, "tug is a TugShip")
	assert_true(fleet.ships.freighter is FreighterShip, "freighter is a FreighterShip")
	assert_true(fleet.ships.wheel is WheelShip, "wheel is a WheelShip")


func test_the_standard_fleet_ships_are_typeable_names() -> void:
	for ship_name in Fleet.standard().names():
		assert_true(CommandInterpreter.is_typeable(ship_name), "'%s' can be typed" % ship_name)


func test_every_standard_ship_is_reachable_and_has_its_doors_on_their_faces() -> void:
	var fleet := Fleet.standard()
	for ship_name in fleet.ships:
		var problems := ShipChecks.shape_problems(fleet.ships[ship_name])
		assert_true(problems.is_empty(), "%s: %s" % [ship_name, problems])


func test_every_standard_ship_holds_its_air_for_a_day_with_doors_open() -> void:
	var fleet := Fleet.standard()
	for ship_name in fleet.ships:
		# A fresh ship of the same type, with random breaker trips off so the day is not cut short.
		var ship: Ship = fleet.ships[ship_name].get_script().new(ShipChecks.NO_TRIPS)
		var problems := ShipChecks.steady_state_problems(ship, SimClock.step_sizes().back())
		assert_true(problems.is_empty(), "%s steady state: %s" % [ship_name, problems])


func test_a_fleet_keeps_the_ships_it_is_given() -> void:
	var fleet := ShipFixture.make_fleet()
	assert_true(fleet.names() == PackedStringArray(["kestrel", "wren"]), "got %s" % fleet.names())
	assert_true(fleet.ships.wren.room("treehouse") != null, "wren has the treehouse")
	assert_true(fleet.ships.kestrel.room("treehouse") == null, "kestrel does not")


func test_a_ship_name_must_be_typeable() -> void:
	expect_error("Ship name 'Big Ship' must be lowercase")
	var fleet := Fleet.new({"Big Ship": ShipFixture.make(), "wren": ShipFixture.make_four_room()})
	assert_true(fleet.names() == PackedStringArray(["wren"]), "the bad name is left out, got %s" % fleet.names())


func test_advance_runs_every_ship() -> void:
	var fleet := Fleet.standard()
	fleet.advance(2.0, Ship.STEP_S)
	for ship_name in fleet.ships:
		assert_near(fleet.ships[ship_name].time_s, 2.0, 1e-6, "%s advanced" % ship_name)
