class_name Transport
extends RefCounted
## A dispatchable ship. Its location is one of three states; the leg fields
## are meaningful only while IN_TRANSIT.

enum State { AT_BODY, DOCKED, IN_TRANSIT }

var name: String
var state: State

## Where it is parked (AT_BODY).
var body: Orbits.Body
## The cycler it is docked to (DOCKED).
var host: Cycler

## Name of the place the whole trip started from; a redirect keeps it.
var origin_name: String
## Where it is headed: an Orbits.Body or a Cycler.
var target: Variant
var depart_point: Vector2
var t0: float
var t_arrive: float
var intercept_point: Vector2
## Length of the current straight-line leg.
var leg_km: float
## Distance flown on earlier legs of a redirected trip.
var flown_before_km: float


static func parked_at(transport_name: String, parked_body: Orbits.Body) -> Transport:
	var transport := Transport.new()
	transport.name = transport_name
	transport.state = State.AT_BODY
	transport.body = parked_body
	return transport


static func docked_to(transport_name: String, docked_host: Cycler) -> Transport:
	var transport := Transport.new()
	transport.name = transport_name
	transport.state = State.DOCKED
	transport.host = docked_host
	return transport
