extends TestCase

func _vent_cargo(ship: Ship) -> void:
	ship.set_opening("hatch", true)
	ship.advance(60.0)

func test_tile_at_start() -> void:
	var tile := DashboardModel.room_tile(ShipFixture.make(), "cockpit")
	assert_true(tile.title == "COCKPIT", "title")
	assert_true(tile.pressure == "101.3 kPa", "pressure: %s" % tile.pressure)
	assert_true(tile.temperature == "21.0 °C", "temperature: %s" % tile.temperature)
	assert_true(tile.o2 == "20.9 %", "o2: %s" % tile.o2)
	assert_true(tile.n2 == "79.0 %", "n2: %s" % tile.n2)
	assert_true(tile.co2 == "0.04 kPa", "co2: %s" % tile.co2)
	assert_true(tile.lit, "lit")
	assert_true(tile.level == Status.Level.NOMINAL, "nominal")

func test_tile_shows_passenger_count() -> void:
	var ship := ShipFixture.make()
	assert_true(DashboardModel.room_tile(ship, "main").passengers == "passengers 1", "one")
	ship.add_passenger("main")
	assert_true(DashboardModel.room_tile(ship, "main").passengers == "passengers 2", "two")
	assert_true(DashboardModel.room_tile(ship, "cargo").passengers == "passengers 0", "none")

func test_vacuum_tile_shows_dashes() -> void:
	var ship := ShipFixture.make()
	_vent_cargo(ship)
	var tile := DashboardModel.room_tile(ship, "cargo")
	assert_true(tile.o2 == "—" and tile.n2 == "—" and tile.co2 == "—", "dashes")
	assert_true(tile.level == Status.Level.DANGER, "danger")

func test_opening_and_system_text() -> void:
	var ship := ShipFixture.make()
	assert_true(DashboardModel.opening_text(ship, "d1") == "CLOSED", "closed")
	var d1 := ship.opening("d1")
	d1.fraction = 0.4
	d1.state = Opening.State.OPENING
	assert_true(DashboardModel.opening_text(ship, "d1") == "OPENING 40 %", "opening")
	d1.state = Opening.State.CLOSING
	d1.fraction = 0.6
	assert_true(DashboardModel.opening_text(ship, "d1") == "CLOSING 60 %", "closing")
	d1.state = Opening.State.OPENING
	d1.fraction = 0.4
	ship.breaker_trip("d1")
	assert_true(DashboardModel.opening_text(ship, "d1") == "OPENING 40 % (no power)", "no power")
	assert_true(DashboardModel.system_text(ship, "hvac") == "RUN", "run")
	ship.restart_system("hvac")
	ship.advance(0.5)
	assert_true(DashboardModel.system_text(ship, "hvac") == "BOOT 8s", DashboardModel.system_text(ship, "hvac"))
	ship.fault_system("computer")
	assert_true(DashboardModel.system_text(ship, "computer") == "FAULT", "fault")

func test_breaker_text() -> void:
	var ship := ShipFixture.make()
	assert_true(DashboardModel.breaker_text(ship, "light-cockpit") == "■ 40 W", DashboardModel.breaker_text(ship, "light-cockpit"))
	ship.breaker_trip("light-cockpit")
	assert_true(DashboardModel.breaker_text(ship, "light-cockpit") == "□ TRIP", "trip")

func test_tank_percent_and_level() -> void:
	var ship := ShipFixture.make()
	assert_true(DashboardModel.tank_percent(ship, "O2") == 100, "full")
	assert_true(DashboardModel.tank_level(ship, "O2") == Status.Level.NOMINAL, "nominal")
	var capacity: float = ship.tanks["O2"].capacity
	ship.tanks["O2"].mol = capacity * 0.249
	assert_true(DashboardModel.tank_percent(ship, "O2") == 24, "rounded down")
	assert_true(DashboardModel.tank_level(ship, "O2") == Status.Level.WARNING, "warning")
	ship.tanks["O2"].mol = capacity * 0.04
	assert_true(DashboardModel.tank_level(ship, "O2") == Status.Level.DANGER, "danger")

func test_clock_text() -> void:
	assert_true(DashboardModel.clock_text(2537.0) == "T+00:42:17", DashboardModel.clock_text(2537.0))
	assert_true(DashboardModel.clock_text(90061.0) == "T+25:01:01", DashboardModel.clock_text(90061.0))

func test_total_draw_text() -> void:
	var ship := ShipFixture.make()
	# 3 lights 120 + 3 idle openings 15 + pressure control 300 + HVAC base 200 + idle recycler 50 + computer 150
	assert_near(ship.total_draw_w(), 835.0, 0.001, "the known draw")
	assert_true(DashboardModel.total_draw_text(ship) == "total 0.8 kW", DashboardModel.total_draw_text(ship))

func test_top_alarm_prefers_exposure() -> void:
	var ship := ShipFixture.make()
	_vent_cargo(ship)
	ship.breaker_trip("hvac")
	var alarm := DashboardModel.top_alarm(ship)
	assert_true(alarm.text == "CARGO EXPOSED", alarm.text)
	assert_true(alarm.level == Status.Level.DANGER, "danger")

func test_top_alarm_trip_only() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("hvac")
	ship.advance(0.1)
	var alarm := DashboardModel.top_alarm(ship)
	assert_true(alarm.text == "HVAC NO POWER", alarm.text)
	assert_true(alarm.level == Status.Level.WARNING, "warning")

func test_top_alarm_names_a_tripped_breaker_before_the_next_step() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("d1")
	assert_true(DashboardModel.top_alarm(ship).text == "BREAKER d1 TRIPPED", "breaker")

func test_top_alarm_reading_direction() -> void:
	var ship := ShipFixture.make()
	ship.room("main").temperature = Units.kelvin(5.0)
	var alarm := DashboardModel.top_alarm(ship)
	assert_true(alarm.text == "MAIN TEMPERATURE LOW", alarm.text)
	assert_true(alarm.level == Status.Level.DANGER, "danger")

func test_top_alarm_nominal() -> void:
	var alarm := DashboardModel.top_alarm(ShipFixture.make())
	assert_true(alarm.text == "", "empty")
	assert_true(alarm.level == Status.Level.NOMINAL, "nominal")

func test_system_and_breaker_levels() -> void:
	var ship := ShipFixture.make()
	assert_true(DashboardModel.system_level(ship, "hvac") == Status.Level.NOMINAL, "running is nominal")
	ship.restart_system("hvac")
	assert_true(DashboardModel.system_level(ship, "hvac") == Status.Level.NOMINAL, "booting is nominal")
	ship.fault_system("hvac")
	assert_true(DashboardModel.system_level(ship, "hvac") == Status.Level.WARNING, "fault is a warning")
	ship.breaker_trip("hvac")
	ship.advance(0.1)
	assert_true(DashboardModel.system_level(ship, "hvac") == Status.Level.WARNING, "no power is a warning")
	assert_true(DashboardModel.breaker_level(ship, "hvac") == Status.Level.WARNING, "tripped is a warning")
	assert_true(DashboardModel.breaker_level(ship, "d1") == Status.Level.NOMINAL, "closed is nominal")

func test_clock_reads_exact_after_whole_steps() -> void:
	var ship := ShipFixture.make()
	for i in 1200:
		ship.step()
	assert_true(DashboardModel.clock_text(ship.time_s) == "T+00:02:00", "got %s" % DashboardModel.clock_text(ship.time_s))

func test_gas_names_use_subscripts() -> void:
	assert_true(DashboardModel.gas_name("O2") == "O₂", "O2")
	assert_true(DashboardModel.gas_name("N2") == "N₂", "N2")
	assert_true(DashboardModel.gas_name("CO2") == "CO₂", "CO2")
