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
## Whose emergency the party is dealing with, and the condition behind it.
var patient: Passenger
var patient_condition := ""
var stable_until := -INF
var hospital_until := -INF
var arrived_until := -INF


func size() -> int:
	return members.size()


## Whether a medical emergency has the party on a stable period, a hospital stay or the way to either.
func is_on_medical_route(now: float) -> bool:
	return medical_return != null or stable_until > now or hospital_until > now


func write(day: float, text: String, cause: String) -> void:
	for member in members:
		member.add_history(day, text, cause)
