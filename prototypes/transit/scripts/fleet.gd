class_name Fleet
extends RefCounted
## All ships plus the dispatch rules. Arrival times are worked out exactly at
## departure, so advancing the clock by any amount can't skip an arrival.

const _BODIES := [Orbits.Body.EARTH, Orbits.Body.MOON, Orbits.Body.MARS]

var cyclers: Array[Cycler] = []
var transports: Array[Transport] = []
var day := 0.0


## Name of a target, which is either an Orbits.Body or a Cycler.
static func target_name(target: Variant) -> String:
	if target is Cycler:
		return target.name
	return Orbits.body_name(target)


func position_of(t: Transport, at_day: float) -> Vector2:
	match t.state:
		Transport.State.AT_BODY:
			return Orbits.body_position(t.body, at_day)
		Transport.State.DOCKED:
			return t.host.position(at_day)
		_:
			var fraction_flown := (at_day - t.t0) / (t.t_arrive - t.t0)
			return t.depart_point.lerp(t.intercept_point, fraction_flown)


## Bodies in Earth, Moon, Mars order, then cyclers in fleet order. A ship in
## flight is at no place, so nothing is excluded for it.
func valid_targets(t: Transport) -> Array:
	var targets: Array = []
	for body in _BODIES:
		if not (t.state == Transport.State.AT_BODY and t.body == body):
			targets.append(body)
	for cycler in cyclers:
		if not (t.state == Transport.State.DOCKED and t.host == cycler):
			targets.append(cycler)
	return targets


## Trip duration if `t` left now, or -1 if the target is invalid or unreachable.
func estimate_days(t: Transport, target: Variant) -> float:
	if not valid_targets(t).has(target):
		return -1.0
	return Intercept.solve(position_of(t, day), day, Units.TRANSPORT_SPEED_KM_PER_DAY, _target_path(target))


## Sends `t` to `target` from where it is now. An in-flight ship is redirected:
## it keeps its origin and counts the distance already flown.
func depart(t: Transport, target: Variant) -> bool:
	var duration := estimate_days(t, target)
	if duration < 0.0:
		return false
	var departure_point := position_of(t, day)
	if t.state == Transport.State.IN_TRANSIT:
		t.flown_before_km += departure_point.distance_to(t.depart_point)
	else:
		t.origin_name = t.host.name if t.state == Transport.State.DOCKED else Orbits.body_name(t.body)
		t.flown_before_km = 0.0
	t.state = Transport.State.IN_TRANSIT
	t.target = target
	t.depart_point = departure_point
	t.t0 = day
	t.t_arrive = day + duration
	t.intercept_point = _target_path(target).call(t.t_arrive)
	t.leg_km = Units.TRANSPORT_SPEED_KM_PER_DAY * duration
	return true


## Share of the whole trip flown, 0 to 1, or -1 when `t` isn't in flight.
func progress(t: Transport) -> float:
	if t.state != Transport.State.IN_TRANSIT:
		return -1.0
	var flown_on_leg_km := t.leg_km * (day - t.t0) / (t.t_arrive - t.t0)
	return (t.flown_before_km + flown_on_leg_km) / (t.flown_before_km + t.leg_km)


func advance_to(new_day: float) -> void:
	day = new_day
	for t in transports:
		if t.state == Transport.State.IN_TRANSIT and t.t_arrive <= new_day:
			_arrive(t)


func _arrive(t: Transport) -> void:
	if t.target is Cycler:
		t.state = Transport.State.DOCKED
		t.host = t.target
	else:
		t.state = Transport.State.AT_BODY
		t.body = t.target


## `func(day: float) -> Vector2` giving the target's position on any day.
func _target_path(target: Variant) -> Callable:
	if target is Cycler:
		return func(at_day: float) -> Vector2: return target.position(at_day)
	return func(at_day: float) -> Vector2: return Orbits.body_position(target, at_day)
