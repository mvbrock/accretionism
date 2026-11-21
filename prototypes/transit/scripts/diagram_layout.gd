class_name DiagramLayout
extends RefCounted
## Fleet -> the shapes of the schematic diagram, in screen space. A pure
## function of each ship's state, origin, destination and progress: it never
## reads an orbital position, and the same fleet state always gives the same
## layout.
##
## Every curve is CURVE_POINTS points running from where the ship came from to
## where it is headed. `split` is the first point ahead of the ship's marker:
## points[0, split) are behind it (drawn solid) and points[split, end] ahead
## of it (drawn dotted), with the marker on the segment between the two.

const CURVE_POINTS := 33

## Everything below is in a 1600 x 900 design space, scaled uniformly to fit.
const DESIGN_SIZE := Vector2(1600, 900)
const BAND_Y := 450.0
const BODY_CENTERS := {
	Orbits.Body.EARTH: Vector2(220, 450),
	Orbits.Body.MOON: Vector2(100, 190),
	Orbits.Body.MARS: Vector2(1380, 450),
}
const BODY_RADII := {Orbits.Body.EARTH: 40.0, Orbits.Body.MOON: 16.0, Orbits.Body.MARS: 36.0}

## Lane control points step down the band by this much, in phase order.
const LANE_SPACING := 64.0
## Lane ends step around each planet's edge by this angle (about 14 degrees), in
## phase order, so the six lanes fan into a planet at separate points instead of
## all meeting at the edge point facing the band.
const LANE_END_STEP := 0.24
## Body-to-body routes clear the band by this much, and each nested trip by a step
## more. Steep enough that their ends sit outside the lanes' fan at each planet.
const ROUTE_CLEARANCE := 480.0
const ROUTE_NEST_STEP := 36.0
## Earth-Moon routes bow off the Earth-Moon line by this much, plus a step per nested trip.
const MOON_ROUTE_BOW := 40.0
const MOON_ROUTE_NEST_STEP := 16.0
const PARKED_RING_GAP := 14.0
const DOCKED_ROW_RISE := 18.0
const DOCKED_ROW_SPACING := 12.0

const _EARTH := Orbits.Body.EARTH
const _MOON := Orbits.Body.MOON
const _MARS := Orbits.Body.MARS


## Returns {bodies, lanes, cyclers, trips, parked}; see the plan's Task 7 for
## each entry's fields. `parked` holds docked transports too.
static func build(fleet: Fleet, size: Vector2) -> Dictionary:
	var scale := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var offset := (size - DESIGN_SIZE * scale) / 2.0
	var to_screen := func(p: Vector2) -> Vector2: return offset + p * scale

	var bodies := []
	for body in [_EARTH, _MOON, _MARS]:
		bodies.append({body = body, center = to_screen.call(BODY_CENTERS[body]), radius = BODY_RADII[body] * scale})

	var lanes := []
	var cyclers := []
	var square_at := {} # Cycler -> design-space position
	var by_phase := fleet.cyclers.duplicate()
	by_phase.sort_custom(func(a: Cycler, b: Cycler) -> bool:
		return a.phase_day < b.phase_day or (a.phase_day == b.phase_day and a.name < b.name))
	for i in by_phase.size():
		var cycler: Cycler = by_phase[i]
		var points := _lane_points(i)
		if cycler.last_flyby(fleet.day) == _MARS:
			points.reverse()
		var marker := _marker_at(points, cycler.progress(fleet.day))
		square_at[cycler] = marker.pos
		lanes.append({cycler = cycler, points = _points_to_screen(points, to_screen), split = marker.split})
		cyclers.append({cycler = cycler, pos = to_screen.call(marker.pos)})

	var trips := []
	var nest_index := _nest_indices(fleet)
	for t in fleet.transports:
		if t.state != Transport.State.IN_TRANSIT:
			continue
		var points := _trip_points(fleet, t, square_at, nest_index.get(t, 0))
		var marker := _marker_at(points, clampf(fleet.progress(t), 0.0, 1.0))
		trips.append({transport = t, points = _points_to_screen(points, to_screen), split = marker.split,
			tri_pos = to_screen.call(marker.pos), tri_angle = marker.angle})

	var parked := []
	var slot := _parked_positions(fleet, square_at)
	for t in fleet.transports:
		if slot.has(t):
			parked.append({transport = t, pos = to_screen.call(slot[t])})

	return {bodies = bodies, lanes = lanes, cyclers = cyclers, trips = trips, parked = parked}


## Lane `i` (in phase order) from Earth's edge to Mars's edge, top to bottom.
static func _lane_points(i: int) -> PackedVector2Array:
	var control := Vector2(
		(BODY_CENTERS[_EARTH].x + BODY_CENTERS[_MARS].x) / 2.0, BAND_Y + (i - 2.5) * LANE_SPACING)
	var fan := (i - 2.5) * LANE_END_STEP
	var start: Vector2 = BODY_CENTERS[_EARTH] + Vector2.from_angle(fan) * BODY_RADII[_EARTH]
	var end: Vector2 = BODY_CENTERS[_MARS] + Vector2.from_angle(PI - fan) * BODY_RADII[_MARS]
	return _bezier(start, control, end)


## In design space, from the trip's origin node to its destination node.
static func _trip_points(fleet: Fleet, t: Transport, square_at: Dictionary, nest: int) -> PackedVector2Array:
	var origin: Variant = _origin_node(fleet, t)
	var destination: Variant = t.target
	if origin is Cycler or destination is Cycler:
		var start: Vector2 = square_at[origin] if origin is Cycler else BODY_CENTERS[origin]
		var end: Vector2 = square_at[destination] if destination is Cycler else BODY_CENTERS[destination]
		if not origin is Cycler:
			start = _edge_facing(origin, end)
		if not destination is Cycler:
			end = _edge_facing(destination, start)
		return _line(start, end)
	var control := _route_control(origin, destination, nest)
	return _bezier(_edge_facing(origin, control), control, _edge_facing(destination, control))


## The control point of a body-to-body route, `nest` steps out from the band.
static func _route_control(origin: Orbits.Body, destination: Orbits.Body, nest: int) -> Vector2:
	var from_center: Vector2 = BODY_CENTERS[origin]
	var to_center: Vector2 = BODY_CENTERS[destination]
	var middle := (from_center + to_center) / 2.0
	if origin != destination and [origin, destination].has(_EARTH) and [origin, destination].has(_MOON):
		# The + side, taken toward the Moon, is the one facing up and right.
		var away_from_screen_edge := -(BODY_CENTERS[_MOON] - BODY_CENTERS[_EARTH]).normalized().orthogonal()
		var side := 1.0 if destination == _MOON else -1.0
		return middle + away_from_screen_edge * side * (MOON_ROUTE_BOW + nest * MOON_ROUTE_NEST_STEP)
	if destination == _MARS:
		return Vector2(middle.x, BAND_Y - ROUTE_CLEARANCE - nest * ROUTE_NEST_STEP)
	return Vector2(middle.x, BAND_Y + ROUTE_CLEARANCE + nest * ROUTE_NEST_STEP)


## An Orbits.Body or a Cycler, found from the trip's origin name.
static func _origin_node(fleet: Fleet, t: Transport) -> Variant:
	for body in BODY_CENTERS:
		if Orbits.body_name(body) == t.origin_name:
			return body
	for cycler in fleet.cyclers:
		if cycler.name == t.origin_name:
			return cycler
	assert(false, "trip origin '%s' is neither a body nor a cycler" % t.origin_name)
	return _EARTH


## Transport -> its index among in-flight trips on the same route, by departure time.
static func _nest_indices(fleet: Fleet) -> Dictionary:
	var routes := {}
	for t in fleet.transports:
		if t.state == Transport.State.IN_TRANSIT:
			var route := "%s>%s" % [t.origin_name, Fleet.target_name(t.target)]
			if not routes.has(route):
				routes[route] = []
			routes[route].append(t)
	var indices := {}
	for route in routes:
		var trips: Array = routes[route]
		trips.sort_custom(func(a: Transport, b: Transport) -> bool:
			return a.t0 < b.t0 or (a.t0 == b.t0 and a.name < b.name))
		for i in trips.size():
			indices[trips[i]] = i
	return indices


## Transport -> design-space position, for every parked or docked transport.
static func _parked_positions(fleet: Fleet, square_at: Dictionary) -> Dictionary:
	var groups := {} # Orbits.Body or Cycler -> transports there
	for t in fleet.transports:
		var place: Variant = null
		if t.state == Transport.State.AT_BODY:
			place = t.body
		elif t.state == Transport.State.DOCKED:
			place = t.host
		else:
			continue
		if not groups.has(place):
			groups[place] = []
		groups[place].append(t)
	var positions := {}
	for place in groups:
		var group: Array = groups[place]
		group.sort_custom(func(a: Transport, b: Transport) -> bool: return a.name < b.name)
		for i in group.size():
			if place is Cycler:
				var along := (i - (group.size() - 1) / 2.0) * DOCKED_ROW_SPACING
				positions[group[i]] = square_at[place] + Vector2(along, -DOCKED_ROW_RISE)
			else:
				var angle := -PI / 2.0 + TAU * i / group.size()
				positions[group[i]] = BODY_CENTERS[place] \
					+ Vector2.from_angle(angle) * (BODY_RADII[place] + PARKED_RING_GAP)
	return positions


## {pos, split, angle} for a marker `fraction` of the way along `points` by arc length.
static func _marker_at(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var wanted := fraction * total
	var walked := 0.0
	var split := points.size() - 1
	var pos := points[split]
	for i in range(1, points.size()):
		var segment := points[i - 1].distance_to(points[i])
		if walked + segment >= wanted:
			split = i
			pos = points[i - 1].lerp(points[i], 0.0 if segment == 0.0 else (wanted - walked) / segment)
			break
		walked += segment
	return {pos = pos, split = split, angle = _tangent_near(points, split).angle()}


## Direction of the segment ending at points[split], or the nearest segment with a direction.
static func _tangent_near(points: PackedVector2Array, split: int) -> Vector2:
	for reach in points.size():
		for i in [split + reach, split - reach]:
			if i >= 1 and i < points.size() and points[i] != points[i - 1]:
				return points[i] - points[i - 1]
	return Vector2.RIGHT


static func _edge_facing(body: Orbits.Body, toward: Vector2) -> Vector2:
	var center: Vector2 = BODY_CENTERS[body]
	return center + (toward - center).normalized() * BODY_RADII[body]


static func _bezier(start: Vector2, control: Vector2, end: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CURVE_POINTS:
		var u := float(i) / (CURVE_POINTS - 1)
		points.append(start.lerp(control, u).lerp(control.lerp(end, u), u))
	return points


static func _line(start: Vector2, end: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CURVE_POINTS:
		points.append(start.lerp(end, float(i) / (CURVE_POINTS - 1)))
	return points


static func _points_to_screen(points: PackedVector2Array, to_screen: Callable) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(to_screen.call(p))
	return result
