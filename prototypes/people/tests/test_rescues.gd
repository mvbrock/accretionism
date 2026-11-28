extends TestCase

const EARTH := Orbits.Body.EARTH
const MARS := Orbits.Body.MARS
const CONDITION := "Heart condition"


## A sim at day 30 with every party mid-journey and no random events, so a test
## decides what goes wrong. Each cycler has its standby docked, and Aldrin I,
## days from its last flyby, carries 75 people.
func _quiet_sim() -> Sim:
	var sim := Sim.new(true, false)
	sim.advance_to(30.0)
	return sim


func _is_on_cycler(party: Party) -> bool:
	return party.aboard == null and party.place is Cycler


func _parties_on(sim: Sim, cycler: Cycler) -> Array[Party]:
	var found: Array[Party] = []
	for party in sim.parties:
		if _is_on_cycler(party) and is_same(party.place, cycler):
			found.append(party)
	return found


func _aldrin_i(sim: Sim) -> Cycler:
	return sim.fleet.cyclers[0]


func _standby_of(sim: Sim, cycler: Cycler) -> Transport:
	for ship in sim.fleet.transports:
		if sim.fleet.service_of[ship] == "standby" and ship.state == Transport.State.DOCKED and is_same(ship.host, cycler):
			return ship
	return null


func _spares(sim: Sim) -> Array[Transport]:
	return sim.fleet.transports.filter(func(ship: Transport) -> bool: return sim.fleet.service_of[ship] == "spare")


## Lets the sim take the rescue queues, which it does at the current instant.
func _settle(sim: Sim) -> void:
	sim.advance_to(sim.day)


func _trips_of_kind(sim: Sim, kind: String) -> Array[Trip]:
	return sim.schedule.trips.filter(func(trip: Trip) -> bool: return trip.kind == kind)


## The first rescue trip `ship` flies.
func _rescue_by(sim: Sim, ship: Transport) -> Trip:
	return _trips_of_kind(sim, "rescue").filter(func(trip: Trip) -> bool: return trip.ship == ship)[0]


func _serious(sim: Sim, party: Party) -> void:
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.SERIOUS)


## The body reached soonest from the cycler today.
func _soonest_body(sim: Sim, cycler: Cycler) -> Orbits.Body:
	var best: Orbits.Body = EARTH
	var best_day := INF
	for body in Orbits.Body.values():
		var solution := sim.fleet.solve_trip(cycler, sim.day, body)
		if solution.ok and solution.t_arrive < best_day:
			best = body
			best_day = solution.t_arrive
	return best


func _entry_index(party: Party, text: String) -> int:
	return party.members[0].history.find_custom(func(entry: Dictionary) -> bool: return entry.text == text)


func test_medical_rescue_to_nearest_hospital() -> void:
	var sim := _quiet_sim()
	var party := _parties_on(sim, _aldrin_i(sim))[0]
	var cycler: Cycler = party.place
	var standby := _standby_of(sim, cycler)
	_serious(sim, party)
	assert_true(party.state == Party.State.HELD and party.route.is_empty(), "the party waits in the queue until the sim takes it")
	_settle(sim)
	assert_true(party.route.size() == 1, "the party is booked onto one trip")
	var trip := party.route[0]
	assert_true(trip.kind == "rescue" and trip.ship == standby and is_same(trip.from, cycler), "the standby flies the rescue off its cycler")
	assert_true(is_same(trip.to, _soonest_body(sim, cycler)), "to the hospital reached soonest")
	assert_near(trip.depart_day, sim.day, 1e-9, "it leaves at once")
	assert_true(is_same(party.destination, trip.to), "the hospital is the party's destination")
	sim.advance_to(sim.day + 0.001)
	assert_true(party.aboard == trip and standby.state == Transport.State.IN_TRANSIT, "it boards and the standby is under way")
	assert_true(_entry_index(party, "Evacuated from %s by %s" % [cycler.name, standby.name]) != -1, "the evacuation is written")
	assert_true(party.members[0].history.any(func(entry: Dictionary) -> bool: return entry.text.begins_with("Evacuated")), "to every member")
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(is_same(party.place, trip.to) and party.hospital_until > sim.day, "once it lands its hospital stay starts")
	assert_true(_entry_index(party, "Admitted to hospital at %s" % Fleet.target_name(trip.to)) != -1, "and says so")


func test_life_support_rescue_lands_and_replans() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var party := _parties_on(sim, cycler)[0]
	party.must_leave = cycler
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	_settle(sim)
	var trip := party.route[0]
	assert_true(trip.kind == "rescue" and is_same(trip.to, _soonest_body(sim, cycler)), "it is rescued to the body reached soonest")
	sim.advance_to(sim.day + 0.001)
	assert_true(party.must_leave == null, "boarding the rescue ends the order to leave")
	var destination := party.destination
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(is_same(party.place, trip.to), "it lands at the rescue's stop")
	assert_true(is_same(party.place, destination) == (party.state == Party.State.ARRIVED), "and arrives if it was going there, else plans on")
	if not is_same(party.place, destination):
		assert_true(not party.route.is_empty() and party.state == Party.State.TRAVELLING, "it replans toward its destination")


func test_life_support_rescue_overflow_waits() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var standby := _standby_of(sim, cycler)
	var riders := _parties_on(sim, cycler)
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	_settle(sim)
	var first := _rescue_by(sim, standby)
	assert_true(first.booked > 0 and first.booked <= first.seats, "the standby takes what fits")
	var waiting := riders.filter(func(p: Party) -> bool: return p.route.is_empty())
	assert_true(not waiting.is_empty(), "the rest wait for the next trip")
	assert_true(waiting.all(func(p: Party) -> bool: return p.state == Party.State.HELD and p.aboard == null and is_same(p.place, cycler)),
			"on the cycler")
	sim.advance_to(first.arrive_day + 60.0)
	assert_true(riders.all(func(p: Party) -> bool: return p.members[0].history.any(
			func(entry: Dictionary) -> bool: return entry.text.begins_with("Evacuated from %s by" % cycler.name))),
			"every rider is evacuated in the end")


func test_party_never_split() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var standby := _standby_of(sim, cycler)
	var seats := Config.SEATS["standby"]
	var line: Array[Party] = []
	var used := 0
	for party in _parties_on(sim, cycler):
		if used + party.size() <= seats - 3:
			used += party.size()
			line.append(party)
	var blocker: Party = null
	var filler: Party = null
	for party in _parties_on(sim, cycler):
		if line.has(party):
			continue
		if blocker == null and used + party.size() > seats:
			blocker = party
		elif filler == null and used + party.size() <= seats:
			filler = party
	assert_true(blocker != null and filler != null, "the cycler has a party that doesn't fit and a smaller one after it")
	line.append(blocker)
	line.append(filler)
	for party in line:
		Rescues.request(sim, party, "life_support")
	_settle(sim)
	var first := _rescue_by(sim, standby)
	assert_true(blocker.route.is_empty() and blocker.state == Party.State.HELD, "the party that doesn't fit is skipped")
	assert_true(filler.route.size() == 1 and filler.route[0] == first, "a later party that fits boards")
	var aboard_size := 0
	for party in sim.parties:
		if party.route.has(first):
			aboard_size += party.size()
	assert_true(first.booked == aboard_size, "seats booked are whole parties")
	assert_true(first.booked <= seats, "within the seats")
	sim.advance_to(first.arrive_day + Config.RESCUE_TURNAROUND_DAYS + 60.0)
	var evacuated_at: Array = blocker.members[0].history.filter(
			func(entry: Dictionary) -> bool: return entry.text.begins_with("Evacuated")).map(
			func(entry: Dictionary) -> float: return entry.day)
	assert_true(evacuated_at.size() == 1 and evacuated_at[0] > first.depart_day,
			"the skipped party is first in line for a later trip, and is evacuated once")


func test_spare_sent_when_no_standby() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var standby := _standby_of(sim, cycler)
	var riders := _parties_on(sim, cycler)
	_serious(sim, riders[0])
	_settle(sim)
	assert_true(standby.state == Transport.State.IN_TRANSIT, "the standby is under way")
	var second := riders[1]
	_serious(sim, second)
	_settle(sim)
	var sent := _trips_of_kind(sim, "rescue").filter(func(trip: Trip) -> bool: return sim.fleet.service_of[trip.ship] == "spare")
	assert_true(sent.size() == 1, "one spare is sent")
	var trip: Trip = sent[0]
	assert_true(is_same(trip.to, cycler) and trip.booked == 0, "to the cycler, with no passengers")
	var nearest: Transport = null
	var nearest_day := INF
	for spare in _spares(sim):
		var arrival: float = sim.fleet.solve_trip(spare.body, sim.day, cycler).t_arrive
		if arrival < nearest_day:
			nearest = spare
			nearest_day = arrival
	assert_true(trip.ship == nearest, "it is the spare that arrives soonest")
	assert_true(second.route.is_empty() and second.state == Party.State.HELD, "the party waits for it")
	_settle(sim)
	assert_true(_trips_of_kind(sim, "rescue").filter(func(t: Trip) -> bool: return sim.fleet.service_of[t.ship] == "spare").size() == 1,
			"no second spare is sent")
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(second.route.size() == 1 and second.route[0].ship == nearest and second.route[0].kind == "rescue", "once docked the spare takes the party")
	assert_true(is_same(second.route[0].from, cycler), "off the cycler")


func test_standby_returns_to_its_cycler() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var standby := _standby_of(sim, cycler)
	var party := _parties_on(sim, cycler)[0]
	_serious(sim, party)
	_settle(sim)
	var rescue := party.route[0]
	var back := sim.schedule.next_trip_of(standby, rescue.depart_day)
	assert_true(back != null and back.kind == "return", "a return trip is scheduled")
	assert_true(is_same(back.from, rescue.to) and is_same(back.to, cycler), "from the stop back to the cycler")
	assert_near(back.depart_day, rescue.arrive_day + Config.RESCUE_TURNAROUND_DAYS, 1e-9, "after the turnaround")
	sim.advance_to(back.arrive_day + 0.001)
	assert_true(standby.state == Transport.State.DOCKED and is_same(standby.host, cycler), "the standby is docked again")


func test_change_of_mind_never_rescues() -> void:
	var sim := _quiet_sim()
	var party := _parties_on(sim, _aldrin_i(sim))[0]
	for attempt in 5:
		Incidents.change_mind(sim, party)
	_settle(sim)
	assert_true(_trips_of_kind(sim, "rescue").is_empty(), "no rescue is flown")
	assert_true(party.route.is_empty() or party.route[0].kind == "service", "the party waits for a flyby")
	assert_true(not party.awaiting_rescue, "and is not in a queue")


func test_rescue_trips_never_blocked() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var standby := _standby_of(sim, cycler)
	var party := _parties_on(sim, cycler)[0]
	_serious(sim, party)
	_settle(sim)
	var rescue := party.route[0]
	var back := sim.schedule.next_trip_of(standby, rescue.depart_day)
	Malfunctions.strike(sim, cycler, Malfunctions.DOCKING_FAILURE)
	Malfunctions.strike(sim, standby, Malfunctions.DOCKING_FAILURE)
	assert_true(not rescue.blocked and not back.blocked, "a docking failure leaves rescue and return trips open")
	assert_true(rescue.docking_failure_on == null and back.docking_failure_on == null, "and nobody rides past their stops")
	assert_true(not sim.docking_failure_until.has(standby), "a rescue ship is not put under a docking failure")
	sim.advance_to(rescue.arrive_day + 0.001)
	assert_true(is_same(party.place, rescue.to) and party.aboard == null, "the party is landed")


func test_life_support_cancels_planned_tender_exit() -> void:
	var sim := _quiet_sim()
	var cycler := _aldrin_i(sim)
	var party: Party = _parties_on(sim, cycler).filter(func(p: Party) -> bool: return not p.route.is_empty())[0]
	var planned := party.route[0]
	var booked_before := planned.booked
	Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	assert_true(not party.route.has(planned) and planned.booked <= booked_before - party.size(), "the seats on the tender are freed")
	_settle(sim)
	assert_true(party.awaiting_rescue or (not party.route.is_empty() and party.route[0].kind == "rescue"), "the party is rescued instead")


func test_rescue_departs_the_same_in_big_and_small_steps() -> void:
	var big := _quiet_sim()
	var small := _quiet_sim()
	for sim in [big, small]:
		var cycler := _aldrin_i(sim)
		Malfunctions.strike(sim, cycler, Malfunctions.LIFE_SUPPORT_FAULT)
	var end := big.day + 60.0
	big.advance_to(end)
	var t := small.day
	while t < end:
		t += 0.37
		small.advance_to(minf(t, end))
	for i in big.parties.size():
		var a := big.parties[i]
		var b := small.parties[i]
		assert_true(a.members[0].history.size() == b.members[0].history.size() and is_same(a.place, b.place) and a.state == b.state,
				"party %d ends up the same" % i)
	for i in big.fleet.transports.size():
		var a := big.fleet.transports[i]
		var b := small.fleet.transports[i]
		assert_true(a.state == b.state, "%s ends in the same state" % a.name)


func test_standby_gap_small() -> void:
	var sim := Sim.new()
	var before := Rescues.standby_gap_days(sim)
	sim.advance_to(800.0)
	var after := Rescues.standby_gap_days(sim)
	for cycler in sim.fleet.cyclers:
		var share: float = (after[cycler] - before[cycler]) / 800.0
		assert_true(share < 0.25, "%s has a standby or spare docked for most of 800 days (gap %.2f)" % [cycler.name, share])
