class_name Schedule
extends RefCounted
## Every planned trip, sorted by departure day. Trips that depart on the same
## day keep the order they were added in.

var trips: Array[Trip] = []


func add(trip: Trip) -> void:
	var index := trips.bsearch_custom(trip, func(a: Trip, b: Trip) -> bool: return a.depart_day < b.depart_day, false)
	trips.insert(index, trip)


func departing_after(day: float) -> Array[Trip]:
	return trips.filter(func(trip: Trip) -> bool: return trip.depart_day > day)


func trips_of(ship: Transport) -> Array[Trip]:
	return trips.filter(func(trip: Trip) -> bool: return trip.ship == ship)


## The ship's first trip departing after `after_day`, or null.
func next_trip_of(ship: Transport, after_day: float) -> Trip:
	for trip in trips:
		if trip.ship == ship and trip.depart_day > after_day:
			return trip
	return null
