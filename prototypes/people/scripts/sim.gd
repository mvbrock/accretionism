class_name Sim
extends RefCounted
## Replays the dispatcher's trips on the fleet and moves travel parties along
## their booked routes. Everything that happens is a timed point, processed in
## time order, so the same run comes out of one big step or many small ones.

## What kind of point it is. At one instant, a lower value goes first.
enum Order { ARRIVAL, DEPARTURE, TIMER, DAILY }

## The parties' own timers, each a field of Party holding the day it fires.
## A fired timer is reset to -INF, so a timer still set is a hold on its party.
const _PARTY_TIMERS: Array[String] = ["arrived_until", "stable_until", "hospital_until"]
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

var _dispatcher: Dispatcher
## Schedule trips before this index have already departed.
var _next_departure := 0
var _in_flight: Array[Trip] = []
## Parties waiting at their starting body for their first journey.
var _not_started: Array[Party] = []
var _next_whole_day := floori(Config.WARMUP_START) + 1


## With `warmup`, runs from the warm-up's first day to day 0. Without it the sim
## stays at that first day with the parties loaded and nothing planned.
## `incidents` turns on the daily event rolls.
func _init(warmup := true, incidents := true) -> void:
	fleet = World.build()
	schedule = Schedule.new()
	_dispatcher = Dispatcher.new(fleet, schedule)
	_dispatcher.extend_to(Config.WARMUP_START + Config.WINDOW_DAYS)
	rng.seed = Config.SEED
	parties = CastLoader.load()
	for party in parties:
		party.state = Party.State.TRAVELLING
		_not_started.append(party)
		for member in party.members:
			passengers_by_id[member.id] = member
	if incidents:
		pass # each incident module's install(self) goes here
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


## Plans the party's route from where it is to `to`, ready to leave on `ready_day`,
## and books it. With no route the party is HELD at its place.
func replan(party: Party, to: Variant, ready_day: float, cause: String) -> void:
	party.destination = to
	if _book_route(party, ready_day):
		party.state = Party.State.TRAVELLING
	else:
		party.state = Party.State.HELD
		party.write(ready_day, "No route available; waiting", cause)


## How far through the journey the party is, 0 to 1. The share is of the time
## from the journey's start to the expected arrival, which is when the last booked
## trip ends. -1 when the party has no route and has not arrived.
func progress(party: Party) -> float:
	if party.state == Party.State.ARRIVED:
		return 1.0
	if party.route.is_empty():
		return -1.0
	var expected_arrival: float = party.route.back().arrive_day
	return clampf((day - party.journey_start) / (expected_arrival - party.journey_start), 0.0, 1.0)


## The ship the passenger is aboard, or the body or cycler they are at.
func location_name(passenger: Passenger) -> String:
	var party := parties[passenger.party_id]
	if party.aboard != null:
		return party.aboard.ship.name
	return Fleet.target_name(party.place)


func _book_route(party: Party, ready_day: float) -> bool:
	var current := party.aboard
	Planner.cancel(party)
	var trips := Planner.plan(schedule, party.place, ready_day, party.destination, party.size(), current)
	if trips.is_empty():
		return false
	if current != null:
		# cancel() left the party's seats on the trip it is aboard, and book() takes them again.
		current.booked -= party.size()
	Planner.book(party, trips)
	return true


## The earliest point not yet processed that falls on or before `limit`, or an
## empty dictionary. Each is {t, order, seq, kind, ...}: `seq` orders points
## that share a time and an order.
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
	return points


## Timers that fire on or before `limit`. A timer set for a day already past fires now.
func _timer_points(limit: float) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for party in _not_started:
		if party.journey_start <= limit:
			points.append(_timer_point(party, _JOURNEY_START, party.journey_start, 0))
	for party in parties:
		for i in _PARTY_TIMERS.size():
			var fires_on: float = party.get(_PARTY_TIMERS[i])
			if fires_on <= limit and fires_on > -INF:
				points.append(_timer_point(party, _PARTY_TIMERS[i], fires_on, i + 1))
	return points


func _timer_point(party: Party, kind: String, fires_on: float, kind_index: int) -> Dictionary:
	return {t = maxf(fires_on, day), order = Order.TIMER, seq = party.id * 10 + kind_index, kind = kind, party = party}


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
			_fire_timer(point.party, point.kind, point.t)
		Order.DAILY:
			_new_day(point.t)


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
	party.write(t, "Boarded %s at %s" % [trip.ship.name, Fleet.target_name(party.place)], "booked trip")


func _arrive(trip: Trip, t: float) -> void:
	_in_flight.erase(trip)
	for party in parties:
		if party.aboard == trip:
			_disembark(party, trip, t)


func _disembark(party: Party, trip: Trip, t: float) -> void:
	party.aboard = null
	party.route.erase(trip)
	party.done_trips.append(trip)
	party.place = trip.to
	if trip.to is Cycler:
		party.write(t, "Boarded %s" % trip.to.name, "booked trip")
	elif party.route.is_empty() and party.place == party.destination:
		party.state = Party.State.ARRIVED
		party.arrived_until = t + Config.ARRIVED_LINGER_DAYS
		party.write(t, "Arrived at %s" % Fleet.target_name(party.place), "journey complete")


func _fire_timer(party: Party, kind: String, t: float) -> void:
	if kind == _JOURNEY_START:
		_not_started.erase(party)
		_set_off(party, party.destination, t, "first journey")
		return
	party.set(kind, -INF)
	match kind:
		"arrived_until":
			_set_off(party, _other_body(party.place), t, "new journey")
		_:
			push_error("Nothing handles the %s timer" % kind)


func _set_off(party: Party, to: Orbits.Body, t: float, cause: String) -> void:
	party.origin = party.place
	party.journey_start = t
	party.done_trips = [] as Array[Trip]
	party.write(t, "Set off for %s" % Fleet.target_name(to), cause)
	replan(party, to, t, cause)


## One of the bodies other than `place`, picked with the sim's rng.
func _other_body(place: Orbits.Body) -> Orbits.Body:
	var others: Array = Orbits.Body.values().filter(func(body: Orbits.Body) -> bool: return body != place)
	return others[rng.randi_range(0, others.size() - 1)]


func _new_day(t: float) -> void:
	var whole_day := _next_whole_day
	_next_whole_day += 1
	_dispatcher.extend_to(t + Config.WINDOW_DAYS)
	for party in parties:
		if party.state == Party.State.HELD and not _is_on_hold(party, t):
			_retry_route(party, t)
	for roll in on_daily:
		roll.call(self, whole_day)


## Whether the party is waiting on a timer that must run out before it retries a route.
func _is_on_hold(party: Party, t: float) -> bool:
	return party.stable_until > t or party.hospital_until > t


func _retry_route(party: Party, t: float) -> void:
	if _book_route(party, t):
		party.state = Party.State.TRAVELLING
		party.write(t, "Found a route to %s" % Fleet.target_name(party.destination), "route retry")
