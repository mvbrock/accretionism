extends TestCase

const WINDOW_END := Config.WARMUP_START + Config.WINDOW_DAYS


func _planned() -> Dictionary:
	var fleet := World.build()
	var schedule := Schedule.new()
	var dispatcher := Dispatcher.new(fleet, schedule)
	dispatcher.extend_to(WINDOW_END)
	return {fleet = fleet, schedule = schedule, dispatcher = dispatcher}


func _ships_of(fleet: Fleet, service: String) -> Array[Transport]:
	var ships: Array[Transport] = []
	for ship in fleet.transports:
		if fleet.service_of[ship] == service:
			ships.append(ship)
	return ships


func test_schedule_sorted_and_covers_window() -> void:
	var planned := _planned()
	var trips: Array[Trip] = planned.schedule.trips
	for i in range(1, trips.size()):
		assert_true(trips[i - 1].depart_day <= trips[i].depart_day, "trip %d is out of order" % i)
	for service in ["shuttle", "express", "tender"]:
		for ship in _ships_of(planned.fleet, service):
			var ship_trips: Array[Trip] = planned.schedule.trips_of(ship)
			assert_true(not ship_trips.is_empty(), "%s has trips" % ship.name)
			assert_true(ship_trips.back().depart_day <= WINDOW_END, "%s plans nothing past the window" % ship.name)
			assert_true(ship_trips.back().arrive_day > WINDOW_END - 800.0 / 2.0, "%s is planned to the window's end" % ship.name)
	for ship in planned.fleet.transports:
		if planned.fleet.service_of[ship] in ["standby", "spare"]:
			assert_true(planned.schedule.trips_of(ship).is_empty(), "%s has no service trips" % ship.name)


func test_shuttle_alternates_with_turnaround() -> void:
	var planned := _planned()
	var ship: Transport = planned.fleet.transports[0]
	var ship_trips: Array[Trip] = planned.schedule.trips_of(ship)
	assert_true(ship_trips[0].from == Orbits.Body.EARTH and ship_trips[0].to == Orbits.Body.MOON, "Earth ship goes to the Moon first")
	assert_near(ship_trips[0].depart_day, Config.WARMUP_START, 1e-9, "first departure at the start")
	for i in range(1, ship_trips.size()):
		assert_true(ship_trips[i].to == ship_trips[i - 1].from, "trip %d returns" % i)
		assert_near(ship_trips[i].depart_day - ship_trips[i - 1].arrive_day, Config.SHUTTLE_TURNAROUND_DAYS, 1e-6, "turnaround %d" % i)
		assert_true(ship_trips[i].seats == 20, "shuttle seats")
		assert_true(ship_trips[i].kind == "service", "service kind")


func test_express_alternates_earth_mars() -> void:
	var planned := _planned()
	for ship in _ships_of(planned.fleet, "express"):
		var ship_trips: Array[Trip] = planned.schedule.trips_of(ship)
		for i in ship_trips.size():
			var trip := ship_trips[i]
			assert_true(trip.seats == 8, "express seats")
			assert_true((trip.from == Orbits.Body.EARTH and trip.to == Orbits.Body.MARS)
				or (trip.from == Orbits.Body.MARS and trip.to == Orbits.Body.EARTH), "%s trip %d is Earth-Mars" % [ship.name, i])
			if i > 0:
				assert_true(trip.from == ship_trips[i - 1].to, "alternates")
				assert_near(trip.depart_day - ship_trips[i - 1].arrive_day, Config.EXPRESS_TURNAROUND_DAYS, 1e-6, "turnaround")


func test_tender_meets_every_flyby() -> void:
	var planned := _planned()
	var fleet: Fleet = planned.fleet
	for cycler in fleet.cyclers:
		var probe := Config.WARMUP_START + 2.0
		while probe < WINDOW_END - 2.0:
			var leg := cycler.leg_at(probe)
			probe = leg.end_day + 1e-6
			var flyby: float = leg.end_day
			if flyby < Config.WARMUP_START + 2.0 or flyby > WINDOW_END - 2.0:
				continue
			var met := false
			var out_trip: Trip = null
			for trip: Trip in planned.schedule.trips:
				if fleet.service_of[trip.ship] == "tender" and is_same(trip.to, cycler) \
						and trip.arrive_day < flyby and trip.depart_day <= flyby:
					out_trip = trip
					for back: Trip in planned.schedule.trips_of(trip.ship):
						if is_same(back.from, cycler) and back.depart_day > flyby and back.depart_day > trip.arrive_day:
							met = true
			assert_true(met, "%s flyby on day %.1f is met" % [cycler.name, flyby])


func test_trips_chain() -> void:
	var planned := _planned()
	for ship in planned.fleet.transports:
		var ship_trips: Array[Trip] = planned.schedule.trips_of(ship)
		for i in range(1, ship_trips.size()):
			assert_true(is_same(ship_trips[i].from, ship_trips[i - 1].to), "%s trip %d starts where the last ended" % [ship.name, i])
			assert_true(ship_trips[i].depart_day >= ship_trips[i - 1].arrive_day, "%s trip %d waits for arrival" % [ship.name, i])


func test_extend_is_idempotent() -> void:
	var planned := _planned()
	var count: int = planned.schedule.trips.size()
	planned.dispatcher.extend_to(WINDOW_END)
	assert_true(planned.schedule.trips.size() == count, "no new trips")


func test_extending_in_steps_matches_one_step() -> void:
	var planned := _planned()
	var fleet := World.build()
	var schedule := Schedule.new()
	var dispatcher := Dispatcher.new(fleet, schedule)
	for day in [-200.0, 0.0, 123.0, WINDOW_END]:
		dispatcher.extend_to(day)
	assert_true(schedule.trips.size() == planned.schedule.trips.size(), "same trip count")


func test_trips_due_are_those_departing_in_the_range() -> void:
	var planned := _planned()
	var due: Array[Trip] = planned.dispatcher.transport_trips_due(0.0, 10.0)
	assert_true(not due.is_empty(), "some trips depart in the first ten days")
	for trip in due:
		assert_true(trip.depart_day >= 0.0 and trip.depart_day < 10.0, "in range")
