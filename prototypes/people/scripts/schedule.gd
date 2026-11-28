class_name Schedule
extends RefCounted
## Every planned trip, sorted by departure day. Trips that depart on the same
## day keep the order they were added in. Trips are never dropped, so lookups
## start at the first trip they could match instead of at the first trip planned.

var trips: Array[Trip] = []
var _longest_trip_days := 0.0


func add(trip: Trip) -> void:
	var index := trips.bsearch_custom(trip, func(a: Trip, b: Trip) -> bool: return a.depart_day < b.depart_day, false)
	trips.insert(index, trip)
	_longest_trip_days = maxf(_longest_trip_days, trip.arrive_day - trip.depart_day)


func departing_after(day: float) -> Array[Trip]:
	return trips.slice(_first_departing_after(day))


## Trips that have not yet arrived at `day`, whether or not they have left.
func arriving_from(day: float) -> Array[Trip]:
	return trips.slice(_first_departing_from(day - _longest_trip_days)).filter(
			func(trip: Trip) -> bool: return trip.arrive_day >= day)


func next_trip_of(ship: Transport, after_day: float) -> Trip:
	return _first_trip_of(ship, _first_departing_after(after_day))


## A trip departing at this very day counts as yet to leave.
func has_departure_of(ship: Transport, from_day: float) -> bool:
	return _first_trip_of(ship, _first_departing_from(from_day)) != null


func _first_trip_of(ship: Transport, start: int) -> Trip:
	for i in range(start, trips.size()):
		if trips[i].ship == ship:
			return trips[i]
	return null


func _first_departing_after(day: float) -> int:
	return _first_index_where(func(trip: Trip) -> bool: return trip.depart_day > day)


func _first_departing_from(day: float) -> int:
	return _first_index_where(func(trip: Trip) -> bool: return trip.depart_day >= day)


## The trips are sorted by departure, so a test on departure day that is false
## and then true splits them at one index. The size when it is never true.
func _first_index_where(test: Callable) -> int:
	var low := 0
	var high := trips.size()
	while low < high:
		var middle := (low + high) >> 1
		if test.call(trips[middle]):
			high = middle
		else:
			low = middle + 1
	return low
