class_name Sim
extends RefCounted
## Replays the dispatcher's trips on the fleet and moves travel parties along
## their booked routes. Everything that happens is a timed point, processed in
## time order, so the same run comes out of one big step or many small ones.

## What kind of point it is. At one instant, a lower value goes first.
enum Order { ARRIVAL, DEPARTURE, TIMER, DAILY, RESCUE }

## The parties' own timers, each a field of Party holding the day it fires.
## A fired timer is reset to -INF, so a timer still set is a hold on its party.
const _PARTY_TIMERS: Array[String] = ["arrived_until", "stable_until", "hospital_until", "exit_retry_at"]
const _SHIP_TIMER := "docking_failure_until"
## Ship timers sort after every party timer at the same instant.
const _SHIP_TIMER_SEQ := 100000
const _JOURNEY_START := "journey_start"

var day := Config.WARMUP_START
var fleet: Fleet
var schedule: Schedule
var parties: Array[Party] = []
var passengers_by_id: Dictionary[String, Passenger] = {}
var rng := RandomNumberGenerator.new()
## Called with `(sim, int_day)` once for each whole day crossed, after held
## parties retry their routes.
var on_daily: Array[Callable] = []
var docking_failure_until := {}
## Each cycler's FIFO queue of parties waiting for a rescue transport, and the
## simulated days it has had no standby or spare docked. Rescues owns both.
var rescue_queues: Dictionary[Cycler, Array] = {}
var standby_gap: Dictionary[Cycler, float] = {}
## Cyclers whose rescue queue is looked at before time moves on, so every request
## made at one instant is served together.
var rescues_due: Array[Cycler] = []
## Adds trips the dispatcher was not asked for at set-up, such as rescues.
var dispatcher: Dispatcher

## Schedule trips before this index have already departed.
var _next_departure := 0
var _in_flight: Array[Trip] = []
var _not_started: Array[Party] = []
var _next_whole_day := floori(Config.WARMUP_START) + 1


func _init(warmup := true, incidents := true) -> void:
	fleet = World.build()
	schedule = Schedule.new()
	dispatcher = Dispatcher.new(fleet, schedule)
	dispatcher.extend_to(Config.WARMUP_START + Config.WINDOW_DAYS)
	rng.seed = Config.SEED
	parties = CastLoader.load()
	for party in parties:
		party.state = Party.State.TRAVELLING
		_not_started.append(party)
		for member in party.members:
			passengers_by_id[member.id] = member
	if incidents:
		Incidents.install(self)
		Malfunctions.install(self)
		Rescues.install(self)
	if warmup:
		advance_to(0.0)


func advance_to(new_day: float) -> void:
	assert(new_day >= day, "the sim only runs forward")
	var point := _next_point(new_day)
	while not point.is_empty():
		fleet.advance_to(point.t)
		day = point.t
		_process(point)
		point = _next_point(new_day)
	fleet.advance_to(new_day)
	day = new_day


func replan(party: Party, to: Variant, ready_day: float, cause: String, via: Variant = null) -> void:
	party.destination = to
	if _book_route(party, ready_day, via):
		party.state = Party.State.TRAVELLING
	else:
		party.state = Party.State.HELD
		party.write(day, "No route available; waiting", cause)


## Measured against the expected arrival, when the last booked trip ends. -1 when the
## party has no route and has not arrived.
func progress(party: Party) -> float:
	if party.state == Party.State.ARRIVED:
		return 1.0
	if party.route.is_empty():
		return -1.0
	var expected_arrival: float = party.route.back().arrive_day
	return clampf((day - party.journey_start) / (expected_arrival - party.journey_start), 0.0, 1.0)


func location_name(passenger: Passenger) -> String:
	var party := parties[passenger.party_id]
	if party.aboard != null:
		return party.aboard.ship.name
	return Fleet.target_name(party.place)


func trip_in_flight(ship: Transport) -> Trip:
	for trip in _in_flight:
		if trip.ship == ship:
			return trip
	return null


func _book_route(party: Party, ready_day: float, via: Variant = null) -> bool:
	var current := party.aboard
	Planner.cancel(party)
	party.exit_retry_at = -INF
	if via == null and _is_ordered_off(party):
		via = Planner.soonest_body(schedule, party.place, ready_day, party.size(), null, Orbits.Body.values())
	var trips: Array[Trip]
	if via == null:
		trips = Planner.plan(schedule, party.place, ready_day, party.destination, party.size(), current)
	else:
		trips = Planner.plan_via(schedule, party.place, ready_day, via, party.destination, party.size(), current)
	if trips.is_empty():
		return false
	if current != null:
		# cancel() left the party's seats on the trip it is aboard, and book() takes them again.
		current.booked -= party.size()
	Planner.book(party, trips)
	return true


func _is_ordered_off(party: Party) -> bool:
	return party.must_leave != null and party.aboard == null and is_same(party.place, party.must_leave)


## `seq` orders points that share a time and an order.
func _next_point(limit: float) -> Dictionary:
	var best := {}
	for candidate in _candidate_points(limit):
		if best.is_empty() or _is_earlier(candidate, best):
			best = candidate
	return best


func _candidate_points(limit: float) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for i in _in_flight.size():
		var trip := _in_flight[i]
		if trip.arrive_day <= limit:
			points.append({t = trip.arrive_day, order = Order.ARRIVAL, seq = i, kind = "arrival", trip = trip})
	if _next_departure < schedule.trips.size() and schedule.trips[_next_departure].depart_day <= limit:
		var trip := schedule.trips[_next_departure]
		points.append({t = trip.depart_day, order = Order.DEPARTURE, seq = 0, kind = "departure", trip = trip})
	points.append_array(_timer_points(limit))
	if _next_whole_day <= limit:
		points.append({t = float(_next_whole_day), order = Order.DAILY, seq = 0, kind = "daily"})
	if not rescues_due.is_empty():
		points.append({t = day, order = Order.RESCUE, seq = 0, kind = "rescue"})
	return points


## A timer set for a day already past fires now.
func _timer_points(limit: float) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for party in _not_started:
		if party.journey_start <= limit:
			points.append(_timer_point(party, _JOURNEY_START, party.journey_start, party.id * 10))
	for party in parties:
		for i in _PARTY_TIMERS.size():
			var fires_on: float = party.get(_PARTY_TIMERS[i])
			if fires_on <= limit and fires_on > -INF:
				points.append(_timer_point(party, _PARTY_TIMERS[i], fires_on, party.id * 10 + i + 1))
	for ship in docking_failure_until:
		if docking_failure_until[ship] <= limit:
			points.append(_timer_point(ship, _SHIP_TIMER, docking_failure_until[ship], _SHIP_TIMER_SEQ + fleet.ships().find(ship)))
	return points


func _timer_point(subject: Variant, kind: String, fires_on: float, seq: int) -> Dictionary:
	return {t = maxf(fires_on, day), order = Order.TIMER, seq = seq, kind = kind, subject = subject}


func _is_earlier(a: Dictionary, b: Dictionary) -> bool:
	if a.t != b.t:
		return a.t < b.t
	if a.order != b.order:
		return a.order < b.order
	return a.seq < b.seq


func _process(point: Dictionary) -> void:
	match point.order:
		Order.ARRIVAL:
			_arrive(point.trip, point.t)
		Order.DEPARTURE:
			_depart(point.trip, point.t)
		Order.TIMER:
			_fire_timer(point.subject, point.kind, point.t)
		Order.DAILY:
			_new_day(point.t)
		Order.RESCUE:
			Rescues.serve_due(self)


func _depart(trip: Trip, t: float) -> void:
	_next_departure += 1
	if not fleet.depart(trip.ship, trip.to):
		push_error("%s could not depart for %s on day %.2f" % [trip.ship.name, Fleet.target_name(trip.to), t])
	elif absf(trip.ship.t_arrive - trip.arrive_day) > 1e-6:
		push_error("%s arrives on day %.4f, but its trip was planned for day %.4f" % [trip.ship.name, trip.ship.t_arrive, trip.arrive_day])
	_in_flight.append(trip)
	for party in parties:
		if party.aboard == null and not party.route.is_empty() and party.route[0] == trip:
			_board(party, trip, t)


func _board(party: Party, trip: Trip, t: float) -> void:
	if party.place != trip.from:
		push_error("Party %d is at %s, not at %s where %s leaves" % [
			party.id, Fleet.target_name(party.place), Fleet.target_name(trip.from), trip.ship.name])
	party.aboard = trip
	if is_same(trip.from, party.must_leave):
		party.must_leave = null
	if trip.kind == Trip.Kind.RESCUE:
		party.write(t, "Evacuated from %s by %s" % [Fleet.target_name(party.place), trip.ship.name], "rescue")
	else:
		party.write(t, "Boarded %s at %s" % [trip.ship.name, Fleet.target_name(party.place)], "booked trip")


func _arrive(trip: Trip, t: float) -> void:
	_in_flight.erase(trip)
	var next := schedule.next_trip_of(trip.ship, t)
	for party in parties:
		if party.aboard != trip:
			continue
		# A tie counts as still stable: the stable_until timer fires right after and the party steps off.
		if next != null and party.stable_until >= t:
			_ride_on(party, trip, next, t, "Staying aboard %s past %s: %s's %s emergency" % [
				trip.ship.name, Fleet.target_name(trip.to), party.patient.full_name, Incidents.in_sentence(party.patient_condition)],
				"medical emergency")
		elif next != null and trip.docking_failure_on != null:
			Planner.cancel(party)
			_ride_on(party, trip, next, t, Malfunctions.ride_on_text(trip), Malfunctions.CAUSE)
			party.route = [next] as Array[Trip]
			party.state = Party.State.TRAVELLING
		else:
			_disembark(party, trip, t)
	Rescues.on_arrival(self, trip)


## The party stays aboard and takes the ship's `next` trip, which it books even
## when the trip has no seats left.
func _ride_on(party: Party, trip: Trip, next: Trip, t: float, text: String, cause: String) -> void:
	party.done_trips.append(trip)
	party.place = trip.to
	party.aboard = next
	next.booked += party.size()
	party.write(t, text, cause)


func _disembark(party: Party, trip: Trip, t: float) -> void:
	party.aboard = null
	party.route.erase(trip)
	party.done_trips.append(trip)
	party.place = trip.to
	if trip.to is Cycler:
		party.write(t, "Boarded %s" % trip.to.name, "booked trip")
	if not party.route.is_empty():
		return
	if is_same(party.place, party.destination):
		if party.medical_return != null:
			begin_hospital_stay(party)
		else:
			_mark_arrived(party, t)
	elif party.state == Party.State.TRAVELLING:
		# A forced exit ended the route short of the destination. A HELD party retries each day instead.
		party.write(t, "Re-planned from %s to %s" % [Fleet.target_name(party.place), Fleet.target_name(party.destination)], "forced exit")
		replan(party, party.destination, t, "forced exit")


func _mark_arrived(party: Party, t: float) -> void:
	party.state = Party.State.ARRIVED
	party.arrived_until = t + Config.ARRIVED_LINGER_DAYS
	party.write(t, "Arrived at %s" % Fleet.target_name(party.place), "journey complete")


func begin_hospital_stay(party: Party) -> void:
	Planner.cancel(party)
	party.destination = party.place
	party.state = Party.State.HELD
	party.hospital_until = day + rng.randi_range(Config.HOSPITAL_STAY_DAYS[0], Config.HOSPITAL_STAY_DAYS[1])
	party.write(day, "Admitted to hospital at %s" % Fleet.target_name(party.place), "medical emergency")


## A riding party whose ship has not left its stop gets off there, where its place already is.
func _step_off_if_docked(party: Party) -> void:
	if party.aboard != null and not _in_flight.has(party.aboard):
		party.aboard.booked -= party.size()
		party.aboard = null


func _discharge(party: Party, t: float) -> void:
	var back_to: Orbits.Body = party.medical_return
	if is_same(party.place, back_to):
		party.write(t, "Discharged from hospital", "hospital stay over")
		_mark_arrived(party, t)
	else:
		party.write(t, "Discharged from hospital; heading to %s" % Fleet.target_name(back_to), "hospital stay over")
		replan(party, back_to, t, "hospital stay over")
	party.medical_return = null
	party.patient = null
	party.patient_condition = ""


func _fire_timer(subject: Variant, kind: String, t: float) -> void:
	if kind == _SHIP_TIMER:
		docking_failure_until.erase(subject)
		return
	var party: Party = subject
	if kind == _JOURNEY_START:
		_not_started.erase(party)
		_set_off(party, party.destination, t, "first journey")
		return
	party.set(kind, -INF)
	match kind:
		"exit_retry_at":
			Malfunctions.resume_exit(self, party)
		"arrived_until":
			_set_off(party, _other_body(party.place), t, "new journey")
		"stable_until":
			_step_off_if_docked(party)
			Incidents.send_to_hospital(self, party)
		"hospital_until":
			_discharge(party, t)
		_:
			push_error("Nothing handles the %s timer" % kind)


func _set_off(party: Party, to: Orbits.Body, t: float, cause: String) -> void:
	party.origin = party.place
	party.journey_start = t
	party.done_trips = [] as Array[Trip]
	party.write(t, "Set off for %s" % Fleet.target_name(to), cause)
	replan(party, to, t, cause)


func _other_body(place: Orbits.Body) -> Orbits.Body:
	var others: Array = Orbits.Body.values().filter(func(body: Orbits.Body) -> bool: return body != place)
	return others[rng.randi_range(0, others.size() - 1)]


func _new_day(t: float) -> void:
	var whole_day := _next_whole_day
	_next_whole_day += 1
	dispatcher.extend_to(t + Config.WINDOW_DAYS)
	for party in parties:
		if party.state == Party.State.HELD and not _is_on_hold(party, t):
			_retry_route(party, t)
	for roll in on_daily:
		roll.call(self, whole_day)


func _is_on_hold(party: Party, t: float) -> bool:
	return party.stable_until > t or party.hospital_until > t or party.exit_retry_at > t or party.awaiting_rescue


func _retry_route(party: Party, t: float) -> void:
	if _book_route(party, t):
		party.state = Party.State.TRAVELLING
		party.write(t, "Found a route to %s" % Fleet.target_name(party.destination), "route retry")
