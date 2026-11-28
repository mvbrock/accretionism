class_name Trip
extends RefCounted
## One planned transport flight, with its seats.

var ship: Transport
## An Orbits.Body or a Cycler.
var from: Variant
var to: Variant
var depart_day: float
var arrive_day: float
var seats: int
var booked := 0
## Closed to planning.
var blocked := false
## The ship whose docking failure stops anyone getting off at this trip's arrival, or null.
var docking_failure_on: Variant = null
## "service", "rescue" or "return".
var kind: String


func _init(trip_ship: Transport, trip_from: Variant, trip_to: Variant, depart: float, arrive: float,
		trip_seats: int, trip_kind: String) -> void:
	ship = trip_ship
	from = trip_from
	to = trip_to
	depart_day = depart
	arrive_day = arrive
	seats = trip_seats
	kind = trip_kind


func seats_left() -> int:
	return seats - booked
