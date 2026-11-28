extends TestCase


func _histories(sim: Sim) -> Array:
	return sim.parties.map(func(party: Party) -> Array:
		return party.members.map(func(member: Passenger) -> Array[Dictionary]: return member.history))


func _party_where(sim: Sim, condition: Callable) -> Party:
	for party in sim.parties:
		if condition.call(party):
			return party
	return null


func _is_on_cycler(party: Party) -> bool:
	return party.aboard == null and party.place is Cycler


func test_warmup_spreads_parties() -> void:
	var sim := Sim.new()
	assert_near(sim.day, 0.0, 1e-9, "the warm-up ends at day 0")
	var aboard_transport := sim.parties.filter(func(party: Party) -> bool: return party.aboard != null)
	var on_cycler := sim.parties.filter(_is_on_cycler)
	var at_body := sim.parties.filter(func(party: Party) -> bool: return party.aboard == null and party.place is int)
	assert_true(not aboard_transport.is_empty(), "some parties are aboard a transport")
	assert_true(not on_cycler.is_empty(), "some parties are on a cycler")
	assert_true(not at_body.is_empty(), "some parties are at a body")


func test_unstarted_sim_plans_nothing() -> void:
	var sim := Sim.new(false, false)
	assert_near(sim.day, Config.WARMUP_START, 1e-9, "it sits at the warm-up's first day")
	for party in sim.parties:
		assert_true(party.route.is_empty() and party.aboard == null, "party %d has no route" % party.id)
		assert_near(sim.progress(party), -1.0, 1e-9, "a waiting party shows no progress")
		for member in party.members:
			assert_true(member.history.is_empty(), "%s has no history yet" % member.id)


func test_same_seed_same_run() -> void:
	var first := Sim.new()
	var second := Sim.new()
	first.advance_to(200.0)
	second.advance_to(200.0)
	assert_true(_histories(first) == _histories(second), "the same seed gives the same histories")
	var set_off_again := 0
	for party in first.parties:
		for entry in party.members[0].history:
			if entry.cause == "new journey":
				set_off_again += 1
	assert_true(set_off_again > 0, "the run includes new journeys, which draw from the rng")


func test_fast_step_matches_slow_steps() -> void:
	var fast := Sim.new()
	var slow := Sim.new()
	fast.advance_to(30.0)
	for i in 720:
		slow.advance_to((i + 1) / 24.0)
	assert_near(slow.day, 30.0, 1e-9, "the slow run ends on the same day")
	assert_true(_histories(fast) == _histories(slow), "one big step equals many small ones")
	var fast_seats := fast.schedule.trips.map(func(trip: Trip) -> int: return trip.booked)
	var slow_seats := slow.schedule.trips.map(func(trip: Trip) -> int: return trip.booked)
	assert_true(fast_seats == slow_seats, "the bookings match too")


func test_histories_ascending() -> void:
	var sim := Sim.new()
	sim.advance_to(100.0)
	var entries := 0
	for party in sim.parties:
		for member in party.members:
			var previous := -INF
			for entry in member.history:
				entries += 1
				assert_true(entry.day >= previous, "%s: day %.2f follows day %.2f" % [member.id, entry.day, previous])
				assert_true(entry.day <= sim.day, "%s has an entry from the future" % member.id)
				previous = entry.day
	assert_true(entries > 0, "there is history to check")


func test_fleet_replay_never_errors() -> void:
	var sim := Sim.new()
	sim.advance_to(400.0)
	assert_near(sim.fleet.day, 400.0, 1e-9, "the fleet reaches day 400")
	assert_near(sim.day, 400.0, 1e-9, "so does the sim")


func test_bookings_match_routes() -> void:
	var sim := Sim.new()
	sim.advance_to(150.0)
	for party in sim.parties:
		for trip in party.route:
			assert_true(not party.done_trips.has(trip), "party %d has a flown trip on its route" % party.id)
		if party.aboard != null:
			assert_true(party.route.has(party.aboard), "party %d is aboard a trip that is not on its route" % party.id)
	for trip in sim.schedule.trips:
		if trip.arrive_day <= sim.day:
			continue
		var booked := 0
		var carries_patient := false
		for party in sim.parties:
			if party.route.has(trip) or party.aboard == trip:
				booked += party.size()
				carries_patient = carries_patient or party.stable_until > -INF
		assert_true(trip.booked == booked, "%s's trip on day %.2f has %d seats booked for %d travelling" % [
			trip.ship.name, trip.depart_day, trip.booked, booked])
		assert_true(trip.booked <= trip.seats or carries_patient, "no trip is overbooked, except for a stabilizing patient's party")


func test_arrival_then_new_journey() -> void:
	var sim := Sim.new()
	var arrived := _party_where(sim, func(party: Party) -> bool: return party.state == Party.State.ARRIVED)
	assert_true(arrived != null, "someone has arrived by day 0")
	if arrived == null:
		return
	var member := arrived.members[0]
	var body_name := Fleet.target_name(arrived.place)
	assert_true(member.history.back().text == "Arrived at %s" % body_name, "the last entry is the arrival")
	assert_true(arrived.place == arrived.destination, "it is at its destination")
	var set_off_day := arrived.arrived_until
	assert_near(set_off_day - member.history.back().day, Config.ARRIVED_LINGER_DAYS, 1e-9, "it lingers for 10 days")
	var history_size := member.history.size()
	sim.advance_to(set_off_day - 0.01)
	assert_true(arrived.state == Party.State.ARRIVED and member.history.size() == history_size, "still arrived just before")
	sim.advance_to(set_off_day + 0.01)
	assert_true(arrived.state != Party.State.ARRIVED, "it has set off")
	assert_true(arrived.destination != arrived.origin, "the new destination is another body")
	assert_near(arrived.journey_start, set_off_day, 1e-9, "the new journey starts when the linger ends")
	assert_true(arrived.done_trips.is_empty(), "the new journey starts with no flown trips")
	var entry: Dictionary = member.history[history_size]
	assert_true(entry.text == "Set off for %s" % Fleet.target_name(arrived.destination), "it writes where it set off for")
	assert_true(entry.cause == "new journey" and entry.day == set_off_day, "with the cause and day")
	assert_true(sim.passengers_by_id.size() == 300, "the cast stays the same")


func test_held_on_cycler_retries() -> void:
	var sim := Sim.new()
	var on_cycler := _party_where(sim, _is_on_cycler)
	assert_true(on_cycler != null, "someone is on a cycler at day 0")
	if on_cycler == null:
		return
	var cycler: Cycler = on_cycler.place
	var from_cycler := sim.schedule.trips.filter(func(trip: Trip) -> bool: return is_same(trip.from, cycler))
	for trip in from_cycler:
		trip.blocked = true
	sim.replan(on_cycler, on_cycler.destination, sim.day, "test")
	var member := on_cycler.members[0]
	assert_true(on_cycler.state == Party.State.HELD and on_cycler.route.is_empty(), "with every way off blocked it is HELD")
	assert_true(member.history.back().text == "No route available; waiting", "and says so")
	assert_near(sim.progress(on_cycler), -1.0, 1e-9, "a HELD party with no route shows no progress")
	var history_size := member.history.size()
	sim.advance_to(sim.day + 3.0)
	assert_true(on_cycler.state == Party.State.HELD and member.history.size() == history_size, "retrying without luck writes nothing")
	for trip in from_cycler:
		trip.blocked = false
	sim.advance_to(sim.day + 1.0)
	assert_true(on_cycler.state == Party.State.TRAVELLING and not on_cycler.route.is_empty(), "once unblocked the daily retry finds a route")
	assert_true(member.history.back().cause == "route retry", "and writes that it did")


func test_progress_formula_and_held_dash() -> void:
	var sim := Sim.new(false, false)
	var party := sim.parties[0]
	var ship := Transport.parked_at("Test Ship", Orbits.Body.EARTH)
	var first := Trip.new(ship, Orbits.Body.EARTH, Orbits.Body.MOON, 10.0, 20.0, 20, "service")
	var last := Trip.new(ship, Orbits.Body.MOON, Orbits.Body.MARS, 25.0, 50.0, 20, "service")
	party.journey_start = 10.0
	party.route = [first, last] as Array[Trip]
	sim.day = 20.0
	assert_near(sim.progress(party), 0.25, 1e-9, "a quarter of the way from day 10 to day 50")
	sim.day = 50.0
	assert_near(sim.progress(party), 1.0, 1e-9, "all of it at the expected arrival")
	party.route = [] as Array[Trip]
	party.state = Party.State.HELD
	assert_near(sim.progress(party), -1.0, 1e-9, "HELD with no route shows the dash")
	party.state = Party.State.ARRIVED
	assert_near(sim.progress(party), 1.0, 1e-9, "arrived is complete")


func test_location_name() -> void:
	var sim := Sim.new()
	var aboard := _party_where(sim, func(party: Party) -> bool: return party.aboard != null)
	assert_true(sim.location_name(aboard.members[0]) == aboard.aboard.ship.name, "aboard shows the ship")
	var on_cycler := _party_where(sim, _is_on_cycler)
	assert_true(sim.location_name(on_cycler.members[0]) == on_cycler.place.name, "on a cycler shows the cycler")
	var at_body := _party_where(sim, func(party: Party) -> bool: return party.aboard == null and party.place is int)
	assert_true(sim.location_name(at_body.members[0]) == Orbits.body_name(at_body.place), "at a body shows the body")


func test_cast_stays_300() -> void:
	var sim := Sim.new()
	sim.advance_to(400.0)
	var total := 0
	for party in sim.parties:
		total += party.size()
		for member in party.members:
			assert_true(sim.passengers_by_id[member.id] == member, "%s is in the lookup" % member.id)
	assert_true(total == 300 and sim.passengers_by_id.size() == 300, "still 300 passengers")
