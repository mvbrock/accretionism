class_name Party
extends RefCounted
## People who travel together. Planned, booked, moved and re-routed as one.

enum State { TRAVELLING, HELD, ARRIVED }

## Its index in Cast.PARTIES.
var id: int
var members: Array[Passenger] = []
var origin: Orbits.Body
var destination: Orbits.Body
var journey_start: float
var route: Array[Trip] = []
var done_trips: Array[Trip] = []
var state := State.HELD
## The Orbits.Body or Cycler the party is at while not aboard a transport.
var place: Variant
## The transport trip the party is on now, or null.
var aboard: Trip
## Where a medical emergency sends the party back to, or null.
var medical_return: Variant
var stable_until := -INF
var hospital_until := -INF
var arrived_until := -INF


func size() -> int:
	return members.size()


func write(day: float, text: String, cause: String) -> void:
	for member in members:
		member.add_history(day, text, cause)
