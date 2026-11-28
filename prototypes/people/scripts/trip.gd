class_name Trip
extends RefCounted

enum Kind { SERVICE, RESCUE, RETURN }

var ship: Transport
## An Orbits.Body or a Cycler.
var from: Variant
var to: Variant
var depart_day: float
var arrive_day: float
var seats: int
var booked := 0
var blocked := false
## The ship whose docking failure stops anyone getting off at this trip's arrival, or null.
var docking_failure_on: Variant = null
## A routine service trip, a rescue of a stranded party, or a standby's return home.
var kind: Kind


func _init(trip_ship: Transport, trip_from: Variant, trip_to: Variant, depart: float, arrive: float,
		trip_seats: int, trip_kind: Kind) -> void:
	ship = trip_ship
	from = trip_from
	to = trip_to
	depart_day = depart
	arrive_day = arrive
	seats = trip_seats
	kind = trip_kind


func seats_left() -> int:
	return seats - booked
