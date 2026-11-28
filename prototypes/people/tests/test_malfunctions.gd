extends TestCase


## A sim at day 0 with every party mid-journey and no random events, so a test
## strikes the ship it wants.
func _quiet_sim() -> Sim:
	return Sim.new(true, false)


## A quiet sim whose standby transports and spares are all away for good, so a
## life-support fault on a cycler sends its riders off by tender rather than by rescue.
func _quiet_sim_without_rescue_ships() -> Sim:
	var sim := _quiet_sim()
	for ship in sim.fleet.transports:
		if ["standby", "spare"].has(sim.fleet.service_of[ship]):
			ship.state = Transport.State.IN_TRANSIT
			ship.t_arrive = INF
	return sim


func _party_where(sim: Sim, condition: Callable) -> Party:
	for party in sim.parties:
		if condition.call(party):
			return party
	return null


func _following(sim: Sim, trip: Trip) -> Trip:
	return sim.schedule.next_trip_of(trip.ship, trip.arrive_day)


func _is_on_cycler(party: Party) -> bool:
	return party.aboard == null and party.place is Cycler


func _entry_index(party: Party, text: String) -> int:
	return party.members[0].history.find_custom(func(entry: Dictionary) -> bool: return entry.text == text)


func _count_entries_starting(party: Party, prefix: String) -> int:
	return party.members[0].history.filter(func(entry: Dictionary) -> bool: return entry.text.begins_with(prefix)).size()


func _flyby_of(cycler: Cycler, trip: Trip) -> float:
	return cycler.leg_at(trip.depart_day).start_day


func _fill(trips: Array) -> void:
	for trip in trips:
		trip.booked = trip.seats


func _aboard_with_following_trip(sim: Sim) -> Party:
	return _party_where(sim, func(p: Party) -> bool:
		if p.aboard == null or p.aboard.to is Cycler:
			return false
		var following := _following(sim, p.aboard)
		return following != null and not is_same(following.to, p.destination))


func test_transport_docking_failure_rides_on() -> void:
	var sim := _quiet_sim()
	var party := _aboard_with_following_trip(sim)
	var trip := party.aboard
	var following := _following(sim, trip)
	var ship := trip.ship
	var route_before := party.route.duplicate()
	Malfunctions.strike(sim, ship, Malfunctions.DOCKING_FAILURE)
	assert_true(trip.docking_failure_on == ship, "the arrival that is blocked names the ship")
	assert_true(trip.blocked and following.blocked, "that trip and the one after it are closed to planning")
	assert_true(sim.docking_failure_until[ship] == following.depart_day, "the ship is under a malfunction until it sets off again")
	assert_true(party.aboard == trip and party.route == route_before, "a party aboard keeps its route until the stop")
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.aboard == following and is_same(party.place, trip.to), "it stays aboard at the stop")
	assert_true(party.route.size() == 1 and party.route[0] == following and party.state == Party.State.TRAVELLING,
			"and rides the ship's next trip")
	assert_true(party.done_trips.has(trip), "the stop it rode past is behind it")
	var text := "Docking failure on %s; staying aboard past %s" % [ship.name, Fleet.target_name(trip.to)]
	var entry_index := _entry_index(party, text)
	assert_true(entry_index != -1 and party.members[0].history[entry_index].cause == "ship malfunction", "the ride-on is written")
	sim.advance_to(following.arrive_day + 0.001)
	assert_true(party.aboard == null and is_same(party.place, following.to), "it gets off at the end of the following trip")
	var replanned_at := _entry_index(party, "Re-planned from %s to %s" % [
			Fleet.target_name(following.to), Fleet.target_name(party.destination)])
	assert_true(replanned_at != -1 and party.members[0].history[replanned_at].cause == "forced exit", "and re-plans from there")
	assert_true(not sim.docking_failure_until.has(ship), "the ship is clear of the malfunction once it has set off")


func test_docking_failure_replans_parties_booked_to_board() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool:
		if p.aboard != null or p.route.is_empty():
			return false
		var trip := p.route[0]
		return sim.trip_in_flight(trip.ship) == null and sim.schedule.next_trip_of(trip.ship, sim.day) == trip)
	var trip := party.route[0]
	var booked := trip.booked
	Malfunctions.strike(sim, trip.ship, Malfunctions.DOCKING_FAILURE)
	assert_true(trip.blocked and trip.docking_failure_on == trip.ship, "the ship's next trip is the blocked arrival")
	assert_true(not party.route.has(trip), "the party is no longer booked on it")
	assert_true(party.route.all(func(t: Trip) -> bool: return not t.blocked), "and uses no blocked trip")
	assert_true(trip.booked <= booked - party.size(), "its seats are given back")
	var entry_index := _entry_index(party, "Docking failure on %s; re-planning" % trip.ship.name)
	assert_true(entry_index != -1 and party.members[0].history[entry_index].cause == "ship malfunction", "the re-plan is written")


func test_cycler_docking_failure_blocks_trips() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return _is_on_cycler(p) and not p.route.is_empty())
	var cycler: Cycler = party.place
	var booked_off := party.route[0]
	var until: float = cycler.leg_at(sim.day).end_day + Config.TENDER_LINGER_DAYS
	Malfunctions.strike(sim, cycler, Malfunctions.DOCKING_FAILURE)
	assert_true(sim.docking_failure_until[cycler] == until, "the cycler is under a malfunction to its next flyby and the linger")
	var blocked := 0
	for trip in sim.schedule.trips:
		var arrives: bool = is_same(trip.to, cycler) and trip.arrive_day >= sim.day and trip.depart_day <= until
		var leaves: bool = is_same(trip.from, cycler) and trip.depart_day >= sim.day and trip.depart_day <= until
		assert_true(trip.blocked == (arrives or leaves), "%s's trip on day %.2f is blocked only in the window" % [trip.ship.name, trip.depart_day])
		assert_true((trip.docking_failure_on == cycler) == arrives, "arrivals at the cycler name it")
		blocked += 1 if trip.blocked else 0
	assert_true(blocked > 0 and booked_off.blocked, "trips in the window are blocked")
	assert_true(not party.route.has(booked_off) and party.route.all(func(t: Trip) -> bool: return not t.blocked),
			"a party booked on one of them is re-planned onto another")
	assert_true(_entry_index(party, "Docking failure on %s; re-planning" % cycler.name) != -1, "and the entry names the cycler")


func test_tender_bound_for_failed_cycler_rides_on() -> void:
	var sim := _quiet_sim()
	var is_tender_bound_for_cycler := func(p: Party) -> bool:
		return p.aboard != null and p.aboard.to is Cycler and _following(sim, p.aboard) != null
	var party := _party_where(sim, is_tender_bound_for_cycler)
	for day in range(1, 300):
		if party != null:
			break
		sim.advance_to(day)
		party = _party_where(sim, is_tender_bound_for_cycler)
	assert_true(party != null, "someone is on a tender bound for a cycler")
	var trip := party.aboard
	var cycler: Cycler = trip.to
	var back := _following(sim, trip)
	Malfunctions.strike(sim, cycler, Malfunctions.DOCKING_FAILURE)
	assert_true(trip.docking_failure_on == cycler and party.aboard == trip, "the tender's arrival is the blocked one")
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.aboard == back and party.place == cycler, "the party stays aboard the docked tender")
	var text := "Docking failure on %s; staying aboard %s past %s" % [cycler.name, trip.ship.name, cycler.name]
	assert_true(_entry_index(party, text) != -1, "the entry names the cycler and the tender")
	assert_true(_entry_index(party, "Boarded %s" % cycler.name) == -1, "it does not board the cycler")
	sim.advance_to(back.arrive_day + 0.001)
	assert_true(party.aboard == null and is_same(party.place, back.to), "the tender takes it back to where it came from")


func test_life_support_transport_everyone_off() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.aboard != null and p.route.size() >= 2)
	var trip := party.aboard
	var later := party.route[1]
	var later_booked := later.booked
	var riders := sim.parties.filter(func(p: Party) -> bool: return p.aboard == trip)
	Malfunctions.strike(sim, trip.ship, Malfunctions.LIFE_SUPPORT_FAULT)
	var text := "Life-support fault on %s; getting off at %s" % [trip.ship.name, Fleet.target_name(trip.to)]
	for rider in riders:
		assert_true(rider.route.size() == 1 and rider.route[0] == trip, "party %d gets off at the next stop" % rider.id)
		assert_true(_entry_index(rider, text) != -1, "party %d's entry names the ship" % rider.id)
	assert_true(later.booked <= later_booked - party.size(), "the trips after the stop are given back")
	sim.advance_to(trip.arrive_day + 0.001)
	for rider in riders:
		assert_true(rider.aboard == null and is_same(rider.place, trip.to), "party %d is off" % rider.id)
	var replanned_at := _entry_index(party, "Re-planned from %s to %s" % [Fleet.target_name(trip.to), Fleet.target_name(party.destination)])
	assert_true(replanned_at != -1 and party.members[0].history[replanned_at].cause == "forced exit", "a party whose route went on re-plans from the stop")
	assert_true(not party.route.is_empty() and party.route[0].depart_day > trip.arrive_day, "and has a new route from there")


func test_life_support_skips_stabilizing_party() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.aboard != null)
	var trip := party.aboard
	Planner.cancel(party)
	party.state = Party.State.HELD
	party.stable_until = sim.day + 10.0
	var history_size := party.members[0].history.size()
	Malfunctions.strike(sim, trip.ship, Malfunctions.LIFE_SUPPORT_FAULT)
	assert_true(party.aboard == trip and party.route.is_empty() and party.state == Party.State.HELD, "a patient that can't be moved stays put")
	assert_true(party.members[0].history.size() == history_size, "and nothing is written")


func test_forced_exit_at_destination_arrives() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool:
		return p.aboard != null and p.route.size() == 1 and is_same(p.destination, p.aboard.to) and not p.aboard.to is Cycler)
	var trip := party.aboard
	Malfunctions.strike(sim, trip.ship, Malfunctions.LIFE_SUPPORT_FAULT)
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.state == Party.State.ARRIVED, "a party whose stop is its destination arrives")
	assert_true(_count_entries_starting(party, "Re-planned") == 0, "and does not re-plan")


func test_life_support_cycler_plans_trip_off() -> void:
	var sim := _quiet_sim_without_rescue_ships()
	var party := _party_where(sim, func(p: Party) -> bool: return _is_on_cycler(p) and not p.route.is_empty())
	var cycler: Cycler = party.place
	var other := _party_where(sim, func(p: Party) -> bool: return _is_on_cycler(p) and p.place != cycler and not p.route.is_empty())
	var other_route := other.route.duplicate()
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	var group := _next_exit_group(sim, cycler)
	assert_true(not party.route.is_empty() and group.has(party.route[0]), "the party plans the next trip off the cycler")
	assert_true(party.state == Party.State.TRAVELLING and party.route[0].from == cycler, "and is travelling")
	assert_true(_count_entries_starting(party, "Life-support fault on %s; leaving via " % cycler.name) == 1, "the entry names the cycler and the body")
	assert_true(other.route == other_route, "a party on another cycler is not affected")


func _occupied_cyclers(sim: Sim) -> Array[Cycler]:
	var cyclers: Array[Cycler] = []
	for party in sim.parties:
		if _is_on_cycler(party) and not cyclers.has(party.place):
			cyclers.append(party.place)
	return cyclers


func _next_exit_group(sim: Sim, cycler: Cycler) -> Array:
	var groups := Malfunctions.exit_groups(sim, cycler)
	return [] if groups.is_empty() else groups[0]


func _would_ride_past(sim: Sim, riders: Array) -> Array:
	return riders.filter(func(p: Party) -> bool:
		var plain := Planner.plan(sim.schedule, p.place, sim.day, p.destination, p.size())
		return plain.is_empty() or not _next_exit_group(sim, p.place).has(plain[0]))


func _assert_leaving_at_next_open_flyby(sim: Sim, riders: Array) -> void:
	for party in riders:
		var cycler: Cycler = party.place
		assert_true(party.must_leave == cycler, "party %d is still ordered off %s" % [party.id, cycler.name])
		assert_true(not party.route.is_empty() and _next_exit_group(sim, cycler).has(party.route[0]),
				"party %d leaves at the next open flyby" % party.id)


func test_exit_order_survives_docking_failure() -> void:
	var sim := _quiet_sim_without_rescue_ships()
	var riders := sim.parties.filter(_is_on_cycler)
	for cycler in _occupied_cyclers(sim):
		Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
		Malfunctions.strike(sim, cycler, Malfunctions.DOCKING_FAILURE)
	assert_true(not _would_ride_past(sim, riders).is_empty(), "a plain plan would keep someone aboard past the next open flyby")
	_assert_leaving_at_next_open_flyby(sim, riders)


func test_exit_order_survives_change_of_mind() -> void:
	var sim := _quiet_sim_without_rescue_ships()
	var riders := sim.parties.filter(_is_on_cycler)
	for cycler in _occupied_cyclers(sim):
		Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	# Some new destinations are reached sooner by riding on than by leaving at the next flyby.
	var changed: Array = []
	for party in riders:
		for attempt in 40:
			Incidents.change_mind(sim, party)
			if not _would_ride_past(sim, [party]).is_empty():
				changed.append(party)
				break
	assert_true(not changed.is_empty(), "a plain plan to the new destination would keep someone aboard past the next open flyby")
	_assert_leaving_at_next_open_flyby(sim, changed)


func test_exit_order_cleared_once_off() -> void:
	var sim := _quiet_sim_without_rescue_ships()
	var party := _party_where(sim, _is_on_cycler)
	var cycler: Cycler = party.place
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	var tender := party.route[0]
	sim.advance_to(tender.depart_day + 0.001)
	assert_true(party.aboard == tender and party.must_leave == null, "boarding a tender off the cycler ends the order")


func test_tenders_full_stays_aboard() -> void:
	var sim := _quiet_sim_without_rescue_ships()
	var party := _party_where(sim, func(p: Party) -> bool: return _is_on_cycler(p))
	var cycler: Cycler = party.place
	var groups := Malfunctions.exit_groups(sim, cycler)
	assert_true(groups.size() >= 3, "the schedule has three flybys of the cycler to test with")
	_fill(_next_exit_group(sim, cycler))
	var first_flyby := _flyby_of(cycler, groups[0][0])
	var second_flyby := _flyby_of(cycler, groups[1][0])
	var third_flyby := _flyby_of(cycler, groups[2][0])
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	var full_at_first := "Tenders full at %s; staying aboard %s" % [Fleet.target_name(cycler.leg_at(first_flyby + 1.0).from), cycler.name]
	assert_true(party.state == Party.State.HELD and party.route.is_empty() and party.aboard == null, "with no room it stays aboard, with no route")
	assert_true(_entry_index(party, full_at_first) != -1, "the entry says the tenders are full")
	assert_near(party.exit_retry_at, second_flyby, 1e-6, "it tries again at the next flyby")
	sim.advance_to(second_flyby - 0.01)
	assert_true(_count_entries_starting(party, "Tenders full") == 1, "the entry is written once while waiting for the flyby")
	assert_true(party.state == Party.State.HELD and party.route.is_empty(), "and it stays aboard")
	_fill(_next_exit_group(sim, cycler))
	sim.advance_to(second_flyby + 0.01)
	assert_true(_count_entries_starting(party, "Tenders full") == 2, "the next flyby has no room either, and says so")
	assert_near(party.exit_retry_at, third_flyby, 1e-6, "it tries again at the flyby after")
	sim.advance_to(third_flyby + 0.01)
	assert_true(party.state == Party.State.TRAVELLING and not party.route.is_empty(), "the third has room and it leaves")
	assert_near(_flyby_of(cycler, party.route[0]), third_flyby, 1e-6, "by one of that flyby's tenders")
	assert_true(_count_entries_starting(party, "Tenders full") == 2, "with no more full entries")
	assert_true(_count_entries_starting(party, "Life-support fault on %s; leaving via " % cycler.name) == 1, "and one entry for leaving")


func test_ride_on_may_overfill_only_that_way() -> void:
	var sim := _quiet_sim()
	var party := _aboard_with_following_trip(sim)
	var trip := party.aboard
	var following := _following(sim, trip)
	Malfunctions.strike(sim, trip.ship, Malfunctions.DOCKING_FAILURE)
	following.booked = following.seats
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.aboard == following, "the party rides on")
	var riders := sim.parties.filter(func(p: Party) -> bool: return p.aboard == following)
	var rider_seats: int = riders.reduce(func(total: int, p: Party) -> int: return total + p.size(), 0)
	assert_true(following.booked == following.seats + rider_seats, "the ride-on takes its seats even when the trip is full")
	var overfilled := sim.schedule.trips.filter(func(t: Trip) -> bool: return t.booked > t.seats)
	assert_true(overfilled == [following], "no other trip is overbooked")
	var others_on_it := sim.parties.filter(func(p: Party) -> bool: return p.route.has(following) and p.aboard != following)
	assert_true(others_on_it.is_empty(), "and nobody else is booked on it")


func test_ship_under_malfunction_does_not_roll() -> void:
	var sim := _quiet_sim()
	Malfunctions.install(sim)
	var roll: Callable = sim.on_daily.back()
	var state_before := sim.rng.state
	roll.call(sim, 1)
	assert_true(sim.rng.state != state_before, "ships roll")
	for ship in sim.fleet.ships():
		sim.docking_failure_until[ship] = sim.day + 100.0
	state_before = sim.rng.state
	roll.call(sim, 2)
	assert_true(sim.rng.state == state_before, "ships under a malfunction do not")


func test_daily_roll_strikes_ships() -> void:
	var sim := Sim.new()
	var docking := 0
	var life_support := 0
	for party in sim.parties:
		docking += _count_entries_starting(party, "Docking failure on")
		life_support += _count_entries_starting(party, "Life-support fault on")
	assert_true(docking > 0, "the daily roll causes docking failures")
	assert_true(life_support > 0, "and life-support faults")


func test_ship_course_unchanged() -> void:
	var struck := _quiet_sim()
	var control := _quiet_sim()
	var kinds := [Malfunctions.DOCKING_FAILURE, Malfunctions.LIFE_SUPPORT_FAULT]
	var ships := struck.fleet.ships()
	for i in ships.size():
		Malfunctions.strike(struck, ships[i], kinds[i % 2])
	for sim in [struck, control]:
		sim.advance_to(60.0)
	for cycler in struck.fleet.cyclers:
		var control_cycler := control.fleet.cyclers[struck.fleet.cyclers.find(cycler)]
		assert_true(cycler.position(60.0) == control_cycler.position(60.0), "%s keeps its timetable" % cycler.name)
	for i in struck.fleet.transports.size():
		var ship := struck.fleet.transports[i]
		var control_ship := control.fleet.transports[i]
		# Standbys and spares are sent out on rescues by a life-support fault on a cycler.
		if ["standby", "spare"].has(struck.fleet.service_of[ship]):
			continue
		assert_true(ship.state == control_ship.state and ship.target == control_ship.target, "%s keeps its trips" % ship.name)
		assert_true(struck.fleet.position_of(ship, 60.0) == control.fleet.position_of(control_ship, 60.0), "%s is where it would be" % ship.name)
