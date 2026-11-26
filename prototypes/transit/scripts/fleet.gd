class_name Fleet
extends RefCounted
## All ships plus the dispatch rules. Arrival times are worked out exactly at
## departure, so advancing the clock by any amount can't skip an arrival.

const _BODIES := [Orbits.Body.EARTH, Orbits.Body.MOON, Orbits.Body.MARS]

var cyclers: Array[Cycler] = []
var transports: Array[Transport] = []
var day := 0.0


## Cyclers then transports, each in fleet order: the order of the table's rows
## and of the ships' icon colors.
func ships() -> Array:
	return cyclers + transports


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
			var flown_point := t.depart_point.lerp(t.intercept_point, fraction_flown)
			if t.is_local_leg:
				return Orbits.body_position(Orbits.Body.EARTH, at_day) + flown_point
			return flown_point


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
	var is_local := _is_local_leg(t, target)
	return Intercept.solve(_leg_point(t, is_local), day, _leg_speed(is_local), _leg_target_path(target, is_local))


## Sends `t` to `target` from where it is now. An in-flight ship is redirected:
## it keeps its origin and counts the distance already flown.
func depart(t: Transport, target: Variant) -> bool:
	var duration := estimate_days(t, target)
	if duration < 0.0:
		return false
	var is_local := _is_local_leg(t, target)
	var departure_point := _leg_point(t, is_local)
	if t.state == Transport.State.IN_TRANSIT:
		t.flown_before_km += _leg_point(t, t.is_local_leg).distance_to(t.depart_point)
	else:
		t.origin_name = t.host.name if t.state == Transport.State.DOCKED else Orbits.body_name(t.body)
		t.flown_before_km = 0.0
	t.state = Transport.State.IN_TRANSIT
	t.target = target
	t.is_local_leg = is_local
	t.depart_point = departure_point
	t.t0 = day
	t.t_arrive = day + duration
	t.intercept_point = _leg_target_path(target, is_local).call(t.t_arrive)
	t.leg_km = _leg_speed(is_local) * duration
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


## Earth–Moon trips (and redirects between them) are slow and short, so they are
## flown in Earth's frame, where the Moon barely moves. Everything else is
## flown in the Sun's frame.
func _is_local_leg(t: Transport, target: Variant) -> bool:
	if target is Cycler or target == Orbits.Body.MARS:
		return false
	match t.state:
		Transport.State.AT_BODY:
			return t.body != Orbits.Body.MARS
		Transport.State.IN_TRANSIT:
			return t.is_local_leg
		_:
			return false


func _leg_speed(is_local: bool) -> float:
	return Units.LOCAL_SPEED_KM_PER_DAY if is_local else Units.TRANSPORT_SPEED_KM_PER_DAY


## `t`'s position now, in the frame the new leg is flown in.
func _leg_point(t: Transport, is_local: bool) -> Vector2:
	var point := position_of(t, day)
	return point - Orbits.body_position(Orbits.Body.EARTH, day) if is_local else point


## The target's path in the frame the leg is flown in.
func _leg_target_path(target: Variant, is_local: bool) -> Callable:
	var sun_frame_path := _target_path(target)
	if not is_local:
		return sun_frame_path
	return func(at_day: float) -> Vector2:
		return sun_frame_path.call(at_day) - Orbits.body_position(Orbits.Body.EARTH, at_day)
