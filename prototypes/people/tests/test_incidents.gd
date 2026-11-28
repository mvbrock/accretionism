extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON
const MARS := Orbits.Body.MARS
const CONDITION := "Heart condition"


## A sim at day 0 with every party mid-journey and no random events, so a test
## starts the emergency it wants.
func _quiet_sim() -> Sim:
	return Sim.new(true, false)


func _party_where(sim: Sim, condition: Callable) -> Party:
	for party in sim.parties:
		if condition.call(party):
			return party
	return null


func _is_at_body(party: Party) -> bool:
	return party.aboard == null and not party.place is Cycler


func _is_aboard_transport_with_next_trip(sim: Sim, party: Party) -> bool:
	return party.aboard != null and sim.schedule.next_trip_of(party.aboard.ship, party.aboard.arrive_day) != null


func _history_texts(party: Party) -> Array[String]:
	var texts: Array[String] = []
	for entry in party.members[0].history:
		texts.append(entry.text)
	return texts


func _entry_index(party: Party, text: String, member := 0) -> int:
	return party.members[member].history.find_custom(func(entry: Dictionary) -> bool: return entry.text == text)


func _count_entries_with_cause(sim: Sim, cause: String) -> int:
	var count := 0
	for party in sim.parties:
		for entry in party.members[0].history:
			if entry.cause == cause:
				count += 1
	return count


func _is_event_entry(entry: Dictionary) -> bool:
	return entry.text.begins_with("Changed plans") or entry.text.contains("emergency;")


func _count_new_event_entries_of(party: Party, from: int) -> int:
	return party.members[0].history.slice(from).filter(_is_event_entry).size()


func _count_event_entries(sim: Sim) -> int:
	var count := 0
	for party in sim.parties:
		count += _count_new_event_entries_of(party, 0)
	return count


func _earliest_hospital_arrival(sim: Sim, party: Party) -> float:
	var earliest := INF
	for body in [EARTH, MOON, MARS]:
		var trips := Planner.plan(sim.schedule, party.place, sim.day, body, party.size(), party.aboard)
		if not trips.is_empty():
			earliest = minf(earliest, trips.back().arrive_day)
	return earliest


func test_change_of_mind_replans_and_writes() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.state == Party.State.TRAVELLING and not p.route.is_empty())
	var old_destination := party.destination
	var history_size := party.members[0].history.size()
	Incidents.change_mind(sim, party)
	assert_true(party.destination != old_destination, "the new destination is another body")
	var entry: Dictionary = party.members[0].history[history_size]
	assert_true(entry.text == "Changed plans: heading to %s instead" % Fleet.target_name(party.destination), "it writes the change")
	assert_true(entry.cause == "change of mind" and entry.day == sim.day, "with its cause and day")
	for member in party.members:
		assert_true(member.history.size() > history_size, "%s is told too" % member.id)
	var planned_to_destination := party.route.is_empty() or is_same(party.route.back().to, party.destination)
	assert_true(planned_to_destination, "the route was re-planned to the new destination")
	var woken_up := Sim.new()
	assert_true(_count_entries_with_cause(woken_up, "change of mind") > 0, "the daily roll changes some minds")


func test_no_change_of_mind_on_medical_route() -> void:
	var control := _quiet_sim()
	var marked := _quiet_sim()
	Incidents.install(control)
	Incidents.install(marked)
	for party in marked.parties:
		match party.id % 3:
			0:
				party.medical_return = MOON
			1:
				party.stable_until = marked.day + 100.0
				party.patient = party.members[0]
				party.patient_condition = CONDITION
			2:
				party.hospital_until = marked.day + 100.0
	var marked_events := 0
	for day in range(1, 31):
		var sizes := marked.parties.map(func(party: Party) -> int: return party.members[0].history.size())
		var was_on_route := marked.parties.map(func(party: Party) -> bool: return party.is_on_medical_route(marked.day))
		control.advance_to(day)
		marked.advance_to(day)
		for party in marked.parties:
			if was_on_route[party.id] and party.is_on_medical_route(marked.day):
				marked_events += _count_new_event_entries_of(party, sizes[party.id])
	assert_true(_count_event_entries(control) > 0, "an unmarked sim has changes of mind and emergencies in 30 days")
	assert_true(marked_events == 0, "no party on a medical route changes its mind or has a new emergency")


func test_serious_aboard_transport_gets_off_at_next_stop() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.aboard != null)
	var trip := party.aboard
	var old_destination := party.destination
	var earliest := _earliest_hospital_arrival(sim, party)
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.SERIOUS)
	assert_true(party.medical_return == old_destination, "it remembers where it was going")
	assert_true(party.route[0] == trip, "it rides on to the ship's next stop")
	assert_near(party.route.back().arrive_day, earliest, 1e-9, "the hospital is the soonest arrival")
	assert_true(is_same(party.destination, party.route.back().to), "the route ends at the hospital")
	assert_true(party.state == Party.State.TRAVELLING, "it is travelling")
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.done_trips.has(trip) and party.aboard != trip, "it gets off at that ship's stop")
	assert_true(sim.schedule.trips.all(func(t: Trip) -> bool: return t.booked <= t.seats), "no trip is overbooked")


func test_serious_at_body_starts_stay() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return _is_at_body(p) and p.state == Party.State.TRAVELLING and not p.route.is_empty())
	var trip := party.route[0]
	var booked := trip.booked
	var old_destination := party.destination
	var body: Orbits.Body = party.place
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.SERIOUS)
	assert_true(party.medical_return == old_destination, "it remembers where it was going")
	assert_true(is_same(party.destination, body) and party.route.is_empty(), "the body it is at is the hospital")
	assert_true(party.state == Party.State.HELD and sim.progress(party) == -1.0, "it is HELD for the stay")
	assert_true(party.hospital_until >= sim.day + 7.0 and party.hospital_until <= sim.day + 21.0, "the stay is 7 to 21 days")
	assert_true(party.stable_until == -INF, "there is no stable period at a body")
	assert_true(trip.booked == booked - party.size(), "its seats are freed")
	assert_true(_entry_index(party, "Admitted to hospital at %s" % Fleet.target_name(body)) != -1, "the admission is written")


func test_critical_rides_past_stops_then_reroutes() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return _is_aboard_transport_with_next_trip(sim, p))
	var trip := party.aboard
	var next := sim.schedule.next_trip_of(trip.ship, trip.arrive_day)
	var old_destination := party.destination
	next.booked = next.seats
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.CRITICAL)
	assert_true(party.state == Party.State.HELD and party.route.is_empty(), "it is HELD with no route")
	assert_true(sim.progress(party) == -1.0, "and shows no progress")
	assert_true(party.stable_until >= sim.day + 5.0 and party.stable_until <= sim.day + 20.0, "stable in 5 to 20 days")
	assert_true(party.medical_return == old_destination, "it remembers where it was going")
	var stable_until := party.stable_until
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.aboard == next, "it stays aboard and takes the ship's next trip")
	assert_true(next.booked == next.seats + party.size(), "even past the seats")
	assert_true(party.done_trips.has(trip) and party.route.is_empty(), "the stop it rode past is behind it")
	sim.advance_to(stable_until - 0.01)
	assert_true(party.stable_until == stable_until and party.state == Party.State.HELD, "still stabilizing just before")
	assert_true(party.aboard != null and is_same(party.destination, old_destination), "still aboard and not re-routed")
	sim.advance_to(stable_until + 0.01)
	assert_true(party.stable_until == -INF, "the stable period is over")
	assert_true(party.medical_return == old_destination or party.hospital_until > -INF, "it is on its way to a hospital")
	var rerouted := _history_texts(party).filter(func(text: String) -> bool: return text.contains("re-routed to"))
	assert_true(rerouted.size() == 1, "it is re-routed once, when stable")


func test_critical_stable_ending_while_docked_at_body_gets_off_there() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool:
		if p.aboard == null or p.aboard.to is Cycler:
			return false
		var next := sim.schedule.next_trip_of(p.aboard.ship, p.aboard.arrive_day)
		return next != null and next.depart_day > p.aboard.arrive_day + 0.01)
	var trip := party.aboard
	var next := sim.schedule.next_trip_of(trip.ship, trip.arrive_day)
	next.booked = next.seats
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.CRITICAL)
	party.stable_until = (trip.arrive_day + next.depart_day) / 2.0
	sim.advance_to(trip.arrive_day + 0.001)
	assert_true(party.aboard == next, "it is riding on, docked")
	sim.advance_to(party.stable_until + 0.001)
	assert_true(party.aboard == null and is_same(party.place, trip.to), "it gets off at the body the ship is docked at")
	assert_true(next.booked == next.seats, "its seats on the next trip are given back")
	assert_true(party.hospital_until > sim.day and party.state == Party.State.HELD, "the hospital stay starts there")
	assert_true(_entry_index(party, "Admitted to hospital at %s" % Fleet.target_name(trip.to)) != -1, "the admission is written")


func test_critical_on_cycler_is_stabilized_in_infirmary() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.aboard == null and p.place is Cycler)
	Incidents.start_emergency(sim, party, party.members[0], CONDITION, Incidents.Severity.CRITICAL)
	assert_true(party.members[0].history.back().text == "%s emergency; stabilized in the infirmary" % CONDITION, "the entry says so")
	assert_true(party.state == Party.State.HELD and party.place is Cycler, "it stays on the cycler")
	sim.advance_to(party.stable_until + 0.01)
	assert_true(party.stable_until == -INF and party.state == Party.State.TRAVELLING and not party.route.is_empty(), "when stable it is on its way off")
	assert_true(party.route[0].kind == "rescue", "by a rescue transport, since the cycler has a standby docked")


func test_hospital_then_back_to_previous_destination() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.aboard != null)
	var old_destination := party.destination
	var member := party.members[0]
	Incidents.start_emergency(sim, party, member, CONDITION, Incidents.Severity.SERIOUS)
	var hospital: Orbits.Body = party.destination
	sim.advance_to(party.route.back().arrive_day + 0.001)
	assert_true(party.hospital_until > sim.day and party.state == Party.State.HELD, "arriving starts the hospital stay")
	assert_true(is_same(party.place, hospital), "at the hospital")
	var admitted := _entry_index(party, "Admitted to hospital at %s" % Fleet.target_name(hospital))
	assert_true(admitted != -1, "the admission is written")
	var stay := party.hospital_until - sim.day
	assert_true(stay >= 6.99 and stay <= 21.0, "the stay is 7 to 21 days")
	sim.advance_to(party.hospital_until + 0.001)
	assert_true(party.medical_return == null and party.hospital_until == -INF, "the stay is over")
	assert_true(is_same(party.destination, old_destination), "it is heading for its previous destination again")
	assert_true(_entry_index(party, "Discharged from hospital; heading to %s" % Fleet.target_name(old_destination)) != -1
			or _entry_index(party, "Discharged from hospital") != -1, "the discharge is written")
	sim.advance_to(sim.day + 400.0)
	var arrived := _entry_index(party, "Arrived at %s" % Fleet.target_name(old_destination))
	assert_true(arrived > admitted, "it gets there after the hospital")


func test_party_entries_name_patient() -> void:
	var sim := _quiet_sim()
	var party := _party_where(sim, func(p: Party) -> bool: return p.size() >= 2 and _is_at_body(p) and p.state == Party.State.TRAVELLING)
	var patient := party.members[1]
	Incidents.start_emergency(sim, party, patient, CONDITION, Incidents.Severity.SERIOUS)
	var body := Fleet.target_name(party.destination)
	for member in party.members:
		var entry: Dictionary = member.history[member.history.size() - 2]
		var expected := "%s emergency; re-routed to %s for treatment" % [CONDITION, body] if member == patient \
				else "Re-routed to %s: %s's heart condition emergency" % [body, patient.full_name]
		assert_true(entry.text == expected, "%s's entry reads '%s' (got '%s')" % [member.id, expected, entry.text])
		assert_true(entry.cause == "medical emergency", "with the cause")


func test_only_serious_or_critical() -> void:
	var sim := _quiet_sim()
	var young := Passenger.new()
	young.age = 25
	var old := Passenger.new()
	old.age = 85
	var young_critical := 0
	var old_critical := 0
	for i in 2000:
		var severity := Incidents.roll_severity(sim.rng, young)
		assert_true(severity == Incidents.Severity.SERIOUS or severity == Incidents.Severity.CRITICAL, "only SERIOUS or CRITICAL")
		young_critical += 1 if severity == Incidents.Severity.CRITICAL else 0
		old_critical += 1 if Incidents.roll_severity(sim.rng, old) == Incidents.Severity.CRITICAL else 0
	assert_true(old_critical > young_critical, "CRITICAL is more likely at higher ages")
	assert_true(Incidents.Severity.size() == 2, "there are no other severities")
	var woken_up := Sim.new()
	assert_true(_count_entries_with_cause(woken_up, "medical emergency") > 0, "the daily roll starts emergencies")
