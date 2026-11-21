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
## Lane ends are spaced this far apart along each planet's edge, in phase order,
## so the six lanes fan into a planet at separate points instead of all meeting at
## the edge point facing the band. Spaced by arc length, so the smaller Mars fans
## through a wider angle and its lanes are no tighter than Earth's.
const LANE_END_SPACING := 11.2
## Body-to-body routes clear the band by this much, and each nested trip by a step
## more. Steep enough that their ends sit outside the lanes' fan at each planet.
const ROUTE_CLEARANCE := 680.0
const ROUTE_NEST_STEP := 36.0
## Earth-Moon routes bow off the Earth-Moon line by this much, plus a step per nested trip.
const MOON_ROUTE_BOW := 40.0
const MOON_ROUTE_NEST_STEP := 16.0
## A busy route's outermost arc keeps this far inside the design space (room
## for its triangle); past that, the route's nesting step shrinks to fit. Small
## enough that the Moon -> Mars route, which peaks about 22 below the top
## edge even when alone, has some room to nest.
const ROUTE_CANVAS_MARGIN := 16.0
const NEST_FIT_ITERATIONS := 20
## Trips from Mars to the Moon go around Earth's left side, below and then left
## of it, through these two cubic control points. The first keeps the departure
## from Mars steeper than the lanes' fan; nested trips push both outward.
const MARS_MOON_FIRST_CONTROL := Vector2(860, BAND_Y + 800)
const MARS_MOON_SECOND_CONTROL := Vector2(-200, 600)
## A trip turned back to its own origin flies a teardrop loop off the node's free
## side: it leaves and returns LOOP_SPREAD either side of that direction, and its
## control points reach out by the loop's reach, LOOP_FLARE either side of it.
const LOOP_SPREAD := 0.5
const LOOP_FLARE := 0.5
const BODY_LOOP_REACH := 64.0
## A cycler's loop hangs below its square (its docked row is above), starting a
## little off the square's center so its triangle never hides under the square.
const CYCLER_LOOP_ROOT := 9.0
const CYCLER_LOOP_REACH := 40.0
## Each body's free side: away from the lanes, its label and the Moon routes.
const LOOP_DIRECTIONS := {
	Orbits.Body.EARTH: 3.0 * PI / 4.0, # down and left
	Orbits.Body.MOON: -2.6, # up and left
	Orbits.Body.MARS: PI / 4.0, # down and right
}
const PARKED_RING_GAP := 16.8
const DOCKED_ROW_RISE := 18.0
const DOCKED_ROW_SPACING := 14.4
## A ship's icon (square or triangle, with its highlight outline) reaches this far
## from its position; its name label keeps clear of that, plus a gap.
const ICON_CLEARANCE := 14.4
const LABEL_GAP := 4.0
const LABEL_PAD := 3.0

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
	var outward := _nest_offsets(fleet)
	for t in fleet.transports:
		if t.state != Transport.State.IN_TRANSIT:
			continue
		var points := _trip_points(fleet, t, square_at, outward.get(t, 0.0))
		var marker := _marker_at(points, clampf(fleet.progress(t), 0.0, 1.0))
		trips.append({transport = t, points = _points_to_screen(points, to_screen), split = marker.split,
			tri_pos = to_screen.call(marker.pos), tri_angle = marker.angle})

	var parked := []
	var slot := _parked_positions(fleet, square_at)
	for t in fleet.transports:
		if slot.has(t):
			parked.append({transport = t, pos = to_screen.call(slot[t])})

	return {size = size, bodies = bodies, lanes = lanes, cyclers = cyclers, trips = trips, parked = parked}


## Lane `i` (in phase order) from Earth's edge to Mars's edge, top to bottom.
static func _lane_points(i: int) -> PackedVector2Array:
	var control := Vector2(
		(BODY_CENTERS[_EARTH].x + BODY_CENTERS[_MARS].x) / 2.0, BAND_Y + (i - 2.5) * LANE_SPACING)
	var earth_fan := (i - 2.5) * LANE_END_SPACING / BODY_RADII[_EARTH]
	var mars_fan := (i - 2.5) * LANE_END_SPACING / BODY_RADII[_MARS]
	var start: Vector2 = BODY_CENTERS[_EARTH] + Vector2.from_angle(earth_fan) * BODY_RADII[_EARTH]
	var end: Vector2 = BODY_CENTERS[_MARS] + Vector2.from_angle(PI - mars_fan) * BODY_RADII[_MARS]
	return _bezier(start, control, end)


## In design space, from the trip's origin node to its destination node. A
## body-to-body route sits `outward` further from the band than its first trip.
static func _trip_points(fleet: Fleet, t: Transport, square_at: Dictionary, outward: float) -> PackedVector2Array:
	var origin: Variant = _origin_node(fleet, t)
	var destination: Variant = t.target
	var is_turned_back := t.origin_name == Fleet.target_name(destination)
	if is_turned_back and origin is Cycler:
		return _loop(square_at[origin], CYCLER_LOOP_ROOT, PI / 2.0, CYCLER_LOOP_REACH)
	if origin is Cycler or destination is Cycler:
		var start: Vector2 = square_at[origin] if origin is Cycler else BODY_CENTERS[origin]
		var end: Vector2 = square_at[destination] if destination is Cycler else BODY_CENTERS[destination]
		if not origin is Cycler:
			start = _edge_facing(origin, end)
		if not destination is Cycler:
			end = _edge_facing(destination, start)
		return _line(start, end)
	return _route_points(origin, destination, outward)


## A route between bodies, or a loop back to the same body, `outward` further
## out than the route's first trip.
static func _route_points(origin: Orbits.Body, destination: Orbits.Body, outward: float) -> PackedVector2Array:
	var from_center: Vector2 = BODY_CENTERS[origin]
	var to_center: Vector2 = BODY_CENTERS[destination]
	var middle := (from_center + to_center) / 2.0
	if origin == destination:
		return _loop(from_center, BODY_RADII[origin], LOOP_DIRECTIONS[origin], BODY_LOOP_REACH + outward)
	if _is_earth_moon(origin, destination):
		# The + side, taken toward the Moon, is the one facing up and right.
		var away_from_screen_edge := -(BODY_CENTERS[_MOON] - BODY_CENTERS[_EARTH]).normalized().orthogonal()
		var side := 1.0 if destination == _MOON else -1.0
		var bow_control := middle + away_from_screen_edge * side * (MOON_ROUTE_BOW + outward)
		return _bezier(_edge_facing(origin, bow_control), bow_control, _edge_facing(destination, bow_control))
	if origin == _MARS and destination == _MOON:
		var first := MARS_MOON_FIRST_CONTROL + Vector2(0, outward)
		var second := MARS_MOON_SECOND_CONTROL + Vector2(-outward / 4.0, outward / 2.0)
		return _cubic(_edge_facing(_MARS, first), first, second, _edge_facing(_MOON, second))
	var away_from_band := -1.0 if destination == _MARS else 1.0
	var control := Vector2(middle.x, BAND_Y + away_from_band * (ROUTE_CLEARANCE + outward))
	return _bezier(_edge_facing(origin, control), control, _edge_facing(destination, control))


static func _is_earth_moon(origin: Orbits.Body, destination: Orbits.Body) -> bool:
	return [origin, destination].has(_EARTH) and [origin, destination].has(_MOON)


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


## Transport -> how much further out than its route's first trip it arcs, for
## every in-flight trip between bodies. Trips nest by departure time a step
## apart; a route too busy to fit on the canvas at the full step gets a smaller one.
static func _nest_offsets(fleet: Fleet) -> Dictionary:
	var routes := {} # [origin, destination] -> its trips
	for t in fleet.transports:
		if t.state != Transport.State.IN_TRANSIT or t.target is Cycler:
			continue
		var origin: Variant = _origin_node(fleet, t)
		if origin is Cycler:
			continue
		var route := [origin, t.target]
		if not routes.has(route):
			routes[route] = []
		routes[route].append(t)
	var offsets := {}
	for route in routes:
		var trips: Array = routes[route]
		trips.sort_custom(func(a: Transport, b: Transport) -> bool:
			return a.t0 < b.t0 or (a.t0 == b.t0 and a.name < b.name))
		var step := _fitted_nest_step(route[0], route[1], trips.size())
		for i in trips.size():
			offsets[trips[i]] = i * step
	return offsets


## The route's full nesting step, or the largest smaller one (found by bisection)
## that keeps all `count` of its trips inside the canvas.
static func _fitted_nest_step(origin: Orbits.Body, destination: Orbits.Body, count: int) -> float:
	var is_short_route := origin == destination or _is_earth_moon(origin, destination)
	var full_step := MOON_ROUTE_NEST_STEP if is_short_route else ROUTE_NEST_STEP
	var outermost := count - 1
	var fits := func(step: float) -> bool:
		return _inside_canvas(_route_points(origin, destination, step * outermost))
	if outermost == 0 or fits.call(full_step):
		return full_step
	var fitting := 0.0
	var too_far := full_step
	for i in NEST_FIT_ITERATIONS:
		var step := (fitting + too_far) / 2.0
		if fits.call(step):
			fitting = step
		else:
			too_far = step
	return fitting


static func _inside_canvas(points: PackedVector2Array) -> bool:
	var margin := Vector2.ONE * ROUTE_CANVAS_MARGIN
	var inside := Rect2(margin, DESIGN_SIZE - margin * 2.0)
	for p in points:
		if not inside.has_point(p):
			return false
	return true


## Screen-space rect (padded around the text) for the name label of `ship`, or an
## empty Rect2 if it is not in `layout`. It never covers the ship's own icon or
## the docked row: a cycler's label hangs below its square, a docked transport's
## sits above the row, a transport parked at a body's is out past the ring, and
## an in-flight transport's is above its triangle, or below it where the canvas
## has no room above.
static func ship_label_rect(layout: Dictionary, ship: Variant, text_size: Vector2) -> Rect2:
	var size := text_size + Vector2.ONE * LABEL_PAD * 2.0
	var distance := ICON_CLEARANCE + LABEL_GAP
	for entry in layout.cyclers:
		if entry.cycler == ship:
			return Rect2(entry.pos + Vector2(-size.x / 2.0, distance), size)
	for entry in layout.trips:
		if entry.transport == ship:
			var above := Rect2(entry.tri_pos + Vector2(-size.x / 2.0, -distance - size.y), size)
			if above.position.y >= 0.0:
				return above
			return Rect2(entry.tri_pos + Vector2(-size.x / 2.0, distance), size)
	for entry in layout.parked:
		if entry.transport != ship:
			continue
		var outward := Vector2.UP
		if ship.state == Transport.State.AT_BODY:
			for body in layout.bodies:
				if body.body == ship.body:
					outward = (entry.pos - body.center).normalized()
		# Slide the rect out along `outward` until its near corner is `distance` from the icon.
		var half_extent_along_outward := absf(outward.x) * size.x / 2.0 + absf(outward.y) * size.y / 2.0
		var center: Vector2 = entry.pos + outward * (distance + half_extent_along_outward)
		return Rect2(center - size / 2.0, size)
	return Rect2()


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
		var slots := _docked_row(square_at[place], group.size()) if place is Cycler \
			else _parked_ring(place, group.size())
		for i in group.size():
			positions[group[i]] = slots[i]
	return positions


## `count` slots spaced evenly in a ring just outside `body`, from the top.
static func _parked_ring(body: Orbits.Body, count: int) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for i in count:
		var angle := -PI / 2.0 + TAU * i / count
		ring.append(BODY_CENTERS[body] + Vector2.from_angle(angle) * (BODY_RADII[body] + PARKED_RING_GAP))
	return ring


## `count` slots in a level row centered just above `square`. At a flyby, where
## the row would sit on a planet, the whole row lifts until it clears the
## planet's circle by half a slot.
static func _docked_row(square: Vector2, count: int) -> PackedVector2Array:
	var row := PackedVector2Array()
	for i in count:
		row.append(square + Vector2((i - (count - 1) / 2.0) * DOCKED_ROW_SPACING, -DOCKED_ROW_RISE))
	for body in BODY_CENTERS:
		var center: Vector2 = BODY_CENTERS[body]
		var clearance: float = BODY_RADII[body] + DOCKED_ROW_SPACING / 2.0
		if not Array(row).any(func(slot: Vector2) -> bool: return slot.distance_to(center) < clearance):
			continue
		var lifted_y := row[0].y
		for slot in row:
			var dx := absf(slot.x - center.x)
			if dx < clearance:
				lifted_y = minf(lifted_y, center.y - sqrt(clearance * clearance - dx * dx))
		for i in count:
			row[i].y = lifted_y
	return row


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


static func _cubic(start: Vector2, first: Vector2, second: Vector2, end: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CURVE_POINTS:
		var u := float(i) / (CURVE_POINTS - 1)
		var v := 1.0 - u
		points.append(start * v * v * v + first * 3.0 * v * v * u + second * 3.0 * v * u * u + end * u * u * u)
	return points


## A teardrop leaving `root` out from `center`, LOOP_SPREAD to one side of
## `direction`, and coming back the same distance out on the other side.
static func _loop(center: Vector2, root: float, direction: float, reach: float) -> PackedVector2Array:
	var leave := center + Vector2.from_angle(direction - LOOP_SPREAD) * root
	var come_back := center + Vector2.from_angle(direction + LOOP_SPREAD) * root
	return _cubic(leave, leave + Vector2.from_angle(direction - LOOP_FLARE) * reach,
		come_back + Vector2.from_angle(direction + LOOP_FLARE) * reach, come_back)


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
