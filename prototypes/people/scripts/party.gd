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
var aboard: Trip
var medical_return: Variant
var patient: Passenger
var patient_condition := ""
var stable_until := -INF
var hospital_until := -INF
var arrived_until := -INF
## When a party kept aboard a cycler for lack of tender seats tries to leave again.
var exit_retry_at := -INF
## The cycler the party is ordered off, or null. Every route planned while it is
## still aboard leaves at the soonest flyby that has room.
var must_leave: Cycler
## Waiting in a cycler's rescue queue. It keeps no route until a transport takes it.
var awaiting_rescue := false


func size() -> int:
	return members.size()


func is_on_medical_route(now: float) -> bool:
	return medical_return != null or stable_until > now or hospital_until > now


func write(day: float, text: String, cause: String) -> void:
	for member in members:
		member.add_history(day, text, cause)
