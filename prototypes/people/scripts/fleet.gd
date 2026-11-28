class_name Fleet
extends RefCounted
## All ships plus the dispatch rules. Arrival times are worked out exactly at
## departure, so advancing the clock by any amount can't skip an arrival.

const _BODIES := [Orbits.Body.EARTH, Orbits.Body.MOON, Orbits.Body.MARS]

var cyclers: Array[Cycler] = []
var transports: Array[Transport] = []
var day := 0.0
## Each transport's service: "shuttle", "tender", "express", "standby" or "spare".
var service_of: Dictionary[Transport, String] = {}
## Where each transport started: its body or the cycler it is docked to.
var home_of: Dictionary[Transport, Variant] = {}


## Cyclers then transports, in fleet order.
func ships() -> Array:
	return cyclers + transports


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
			var flown_point := t.depart_point.lerp(t.intercept_point, fraction_flown)
			if t.is_local_leg:
				return Orbits.body_position(Orbits.Body.EARTH, at_day) + flown_point
			return flown_point


## A ship in flight keeps its destination, so it has no valid targets.
func valid_targets(t: Transport) -> Array:
	var targets: Array = []
	if t.state == Transport.State.IN_TRANSIT:
		return targets
	for body in _BODIES:
		if not (t.state == Transport.State.AT_BODY and t.body == body):
			targets.append(body)
	for cycler in cyclers:
		if not (t.state == Transport.State.DOCKED and t.host == cycler):
			targets.append(cycler)
	return targets


func estimate_days(t: Transport, target: Variant) -> float:
	if not valid_targets(t).has(target):
		return -1.0
	var trip := solve_trip(_from_of(t), day, target)
	return trip.t_arrive - day if trip.ok else -1.0


## Where a trip from `from` (an Orbits.Body or a Cycler) to `target` that
## leaves on day `t0` would end. `ok` is false when the target can't be
## reached or `from` is the target.
func solve_trip(from: Variant, t0: float, target: Variant) -> Dictionary:
	if is_same(from, target):
		return {ok = false}
	var is_local := _is_local_leg(from, target)
	var duration := Intercept.solve(_leg_point(from, t0, is_local), t0, _leg_speed(is_local), _leg_target_path(target, is_local))
	if duration < 0.0:
		return {ok = false}
	var t_arrive := t0 + duration
	return {ok = true, t_arrive = t_arrive,
		intercept_point = _leg_target_path(target, is_local).call(t_arrive),
		leg_km = _leg_speed(is_local) * duration}


func depart(t: Transport, target: Variant) -> bool:
	if not valid_targets(t).has(target):
		return false
	var from: Variant = _from_of(t)
	var trip := solve_trip(from, day, target)
	if not trip.ok:
		return false
	var is_local := _is_local_leg(from, target)
	var departure_point := _leg_point(from, day, is_local)
	t.origin_name = t.host.name if t.state == Transport.State.DOCKED else Orbits.body_name(t.body)
	t.state = Transport.State.IN_TRANSIT
	t.target = target
	t.is_local_leg = is_local
	t.depart_point = departure_point
	t.t0 = day
	t.t_arrive = trip.t_arrive
	t.intercept_point = trip.intercept_point
	t.leg_km = trip.leg_km
	return true


## A trip is flown at a constant speed, so the share of time is also the share of distance.
func progress(t: Transport) -> float:
	if t.state != Transport.State.IN_TRANSIT:
		return -1.0
	return (day - t.t0) / (t.t_arrive - t.t0)


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


func _target_path(target: Variant) -> Callable:
	if target is Cycler:
		return func(at_day: float) -> Vector2: return target.position(at_day)
	return func(at_day: float) -> Vector2: return Orbits.body_position(target, at_day)


func _from_of(t: Transport) -> Variant:
	return t.host if t.state == Transport.State.DOCKED else t.body


func _from_position(from: Variant, at_day: float) -> Vector2:
	if from is Cycler:
		return from.position(at_day)
	return Orbits.body_position(from, at_day)


## Earth–Moon trips are slow and short, so they are flown in Earth's frame,
## where the Moon barely moves. Everything else is flown in the Sun's frame.
func _is_local_leg(from: Variant, target: Variant) -> bool:
	if target is Cycler or target == Orbits.Body.MARS:
		return false
	return not from is Cycler and from != Orbits.Body.MARS


func _leg_speed(is_local: bool) -> float:
	return Units.LOCAL_SPEED_KM_PER_DAY if is_local else Units.TRANSPORT_SPEED_KM_PER_DAY


func _leg_point(from: Variant, at_day: float, is_local: bool) -> Vector2:
	var point := _from_position(from, at_day)
	return point - Orbits.body_position(Orbits.Body.EARTH, at_day) if is_local else point


func _leg_target_path(target: Variant, is_local: bool) -> Callable:
	var sun_frame_path := _target_path(target)
	if not is_local:
		return sun_frame_path
	return func(at_day: float) -> Vector2:
		return sun_frame_path.call(at_day) - Orbits.body_position(Orbits.Body.EARTH, at_day)
