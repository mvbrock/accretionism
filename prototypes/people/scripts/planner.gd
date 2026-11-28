class_name Planner
extends RefCounted
## Plans and books routes over the schedule. A place is an Orbits.Body or a
## Cycler; waiting at a cycler is riding it.


## The chain of trips that reaches `to` soonest for a party of `party_size`, or
## an empty array when there is none. A connection scan: trips are taken in
## departure order, and a trip is usable when the party can be at its origin
## CONNECTION_DAYS before it leaves. The first boarding from `from` needs no
## connection time. With `first_trip`, the route begins with that trip and
## planning resumes where it ends, with connection time.
static func plan(schedule: Schedule, from: Variant, ready_day: float, to: Variant, party_size: int,
		first_trip: Trip = null) -> Array[Trip]:
	var start: Variant = from
	var start_day := ready_day
	var start_needs_connection := false
	if first_trip != null:
		start = first_trip.to
		start_day = first_trip.arrive_day
		start_needs_connection = true
	var chain: Array[Trip] = []
	if first_trip != null:
		chain.append(first_trip)
	if is_same(start, to):
		return chain
	var earliest := {start: start_day}
	var arrived_by: Dictionary = {}
	for trip in schedule.departing_after(start_day):
		if trip.depart_day > earliest.get(to, INF):
			break
		if trip.kind != "service" or trip.blocked or trip.seats_left() < party_size or not earliest.has(trip.from):
			continue
		var needs_connection: bool = arrived_by.has(trip.from) or start_needs_connection
		var connection: float = Config.CONNECTION_DAYS if needs_connection else 0.0
		if earliest[trip.from] + connection > trip.depart_day:
			continue
		if trip.arrive_day < earliest.get(trip.to, INF):
			earliest[trip.to] = trip.arrive_day
			arrived_by[trip.to] = trip
	if not arrived_by.has(to):
		return []
	var path: Array[Trip] = []
	var place: Variant = to
	while arrived_by.has(place):
		var trip: Trip = arrived_by[place]
		path.push_front(trip)
		place = trip.from
	return chain + path


## The body of `bodies` reached soonest, or null when none is reachable.
static func soonest_body(schedule: Schedule, from: Variant, ready_day: float, party_size: int,
		first_trip: Trip, bodies: Array) -> Variant:
	var soonest: Variant = null
	var earliest := INF
	for body in bodies:
		var trips := plan(schedule, from, ready_day, body, party_size, first_trip)
		if not trips.is_empty() and trips.back().arrive_day < earliest:
			soonest = body
			earliest = trips.back().arrive_day
	return soonest


## Like `plan`, but the route stops at `via` on the way to `to`. When `to` can't be
## reached from `via`, the route ends at `via`.
static func plan_via(schedule: Schedule, from: Variant, ready_day: float, via: Variant, to: Variant,
		party_size: int, first_trip: Trip = null) -> Array[Trip]:
	var to_via := plan(schedule, from, ready_day, via, party_size, first_trip)
	if to_via.is_empty():
		return to_via
	var onward := plan(schedule, via, to_via.back().arrive_day, to, party_size, to_via.back())
	if onward.is_empty():
		return to_via
	return to_via.slice(0, -1) + onward


static func book(party: Party, trips: Array[Trip]) -> void:
	party.route = trips
	for trip in trips:
		trip.booked += party.size()


## Frees the seats of the trips the party has not boarded, and keeps the trip it is aboard.
static func cancel(party: Party) -> void:
	for trip in party.route:
		if trip != party.aboard:
			trip.booked = maxi(0, trip.booked - party.size())
	party.route = [] as Array[Trip]


## The party's journey as {ship_name, from_name, to_name, start, end, status} legs, with
## status "done", "current" or "next". The time between a trip that docks at a cycler and
## the trip that leaves it is a leg of the cycler.
static func legs(party: Party) -> Array[Dictionary]:
	var trips: Array[Trip] = party.done_trips.duplicate()
	if party.aboard != null and not party.route.has(party.aboard):
		trips.append(party.aboard) # a CRITICAL patient's party riding with no route
	for trip in party.route:
		if not trips.has(trip):
			trips.append(trip)
	var result: Array[Dictionary] = []
	for i in trips.size():
		var trip := trips[i]
		result.append(_leg(trip.ship.name, trip.from, trip.to, trip.depart_day, trip.arrive_day, _trip_status(party, trip)))
		if trip.to is Cycler and i + 1 < trips.size():
			var next := trips[i + 1]
			result.append(_leg(trip.to.name, trip.from, next.to, trip.arrive_day, next.depart_day, _ride_status(party, trip.to, next)))
	return result


static func _leg(ship_name: String, from: Variant, to: Variant, start: float, end: float, status: String) -> Dictionary:
	return {ship_name = ship_name, from_name = Fleet.target_name(from), to_name = Fleet.target_name(to),
		start = start, end = end, status = status}


static func _trip_status(party: Party, trip: Trip) -> String:
	if party.done_trips.has(trip):
		return "done"
	return "current" if trip == party.aboard else "next"


static func _ride_status(party: Party, cycler: Cycler, leaving_trip: Trip) -> String:
	if party.done_trips.has(leaving_trip) or leaving_trip == party.aboard:
		return "done"
	if party.aboard == null and party.place is Cycler and party.place == cycler:
		return "current"
	return "next"
