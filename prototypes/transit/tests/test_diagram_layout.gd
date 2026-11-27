extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON
const MARS := Orbits.Body.MARS
const SIZE := Vector2(1600, 900)
const MIDPOINT := 16


## Six cyclers (Aldrin I..VI, phases 0..650 step 130, alternating UP/DOWN) and no transports.
## Sets the global orbit and timetable settings, which other tests may have changed.
func _fleet() -> Fleet:
	Orbits.configure({EARTH: 0.0, MOON: 0.0, MARS: 45.0})
	Cycler.cycle_days = 780.0
	Cycler.short_leg_days = 146.0
	var fleet := Fleet.new()
	var names := ["Aldrin I", "Aldrin II", "Aldrin III", "Aldrin IV", "Aldrin V", "Aldrin VI"]
	for i in names.size():
		var direction := Cycler.Direction.UP if i % 2 == 0 else Cycler.Direction.DOWN
		fleet.cyclers.append(Cycler.new(names[i], direction, 130.0 * i))
	return fleet


func _parked(fleet: Fleet, ship_name: String, body: Orbits.Body) -> Transport:
	var transport := Transport.parked_at(ship_name, body)
	fleet.transports.append(transport)
	return transport


func _entry_for(entries: Array, key: String, value: Object) -> Dictionary:
	for entry in entries:
		if entry[key] == value:
			return entry
	return {}


func _body_center(layout: Dictionary, body: Orbits.Body) -> Vector2:
	for entry in layout.bodies:
		if entry.body == body:
			return entry.center
	return Vector2.INF


func _arc_lengths(points: PackedVector2Array) -> PackedFloat64Array:
	var lengths := PackedFloat64Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[i - 1] + points[i - 1].distance_to(points[i]))
	return lengths


## The point `fraction` of the way along the polyline, by arc length.
func _point_at_fraction(points: PackedVector2Array, fraction: float) -> Vector2:
	var lengths := _arc_lengths(points)
	var wanted := fraction * lengths[lengths.size() - 1]
	for i in range(1, points.size()):
		if lengths[i] >= wanted:
			var segment := lengths[i] - lengths[i - 1]
			var along := 0.0 if segment == 0.0 else (wanted - lengths[i - 1]) / segment
			return points[i - 1].lerp(points[i], along)
	return points[points.size() - 1]


func _top_lane_midpoint(layout: Dictionary) -> Vector2:
	var top := Vector2(0, INF)
	for lane in layout.lanes:
		if lane.points[MIDPOINT].y < top.y:
			top = lane.points[MIDPOINT]
	return top


func _bottom_lane_midpoint(layout: Dictionary) -> Vector2:
	var bottom := Vector2(0, -INF)
	for lane in layout.lanes:
		if lane.points[MIDPOINT].y > bottom.y:
			bottom = lane.points[MIDPOINT]
	return bottom


func test_bodies_placed() -> void:
	var layout := DiagramLayout.build(_fleet(), SIZE)
	var earth := _body_center(layout, EARTH)
	var moon := _body_center(layout, MOON)
	var mars := _body_center(layout, MARS)
	assert_true(earth.x < SIZE.x / 2.0, "Earth is left of center, got %s" % earth)
	assert_true(mars.x > SIZE.x / 2.0, "Mars is right of center, got %s" % mars)
	assert_true(moon.x < earth.x and moon.y < earth.y, "the Moon is above and left of Earth, got %s" % moon)


func test_every_curve_has_33_points_and_six_lanes_never_meet() -> void:
	var fleet := _fleet()
	var layout := DiagramLayout.build(fleet, SIZE)
	assert_true(layout.lanes.size() == 6, "one lane per cycler, got %d" % layout.lanes.size())
	for lane in layout.lanes:
		assert_true(lane.points.size() == DiagramLayout.CURVE_POINTS, "33 points per lane")
	for i in layout.lanes.size():
		for j in range(i + 1, layout.lanes.size()):
			var closest := INF
			for p in layout.lanes[i].points:
				for q in layout.lanes[j].points:
					closest = minf(closest, p.distance_to(q))
			# Lanes are drawn 2 px wide. Their ends are spaced around each planet's edge,
			# which keeps them at least 11 px apart where they fan in.
			assert_true(closest > 11.0, "lanes %d and %d stay apart (closest %.1f px)" % [i, j, closest])


func test_cycler_moves_across_lane() -> void:
	var fleet := _fleet()
	var up := fleet.cyclers[0] # UP, short leg Earth -> Mars over [0, 146]
	fleet.advance_to(36.5) # progress 0.25
	var layout := DiagramLayout.build(fleet, SIZE)
	var lane: Dictionary = _entry_for(layout.lanes, "cycler", up)
	var square: Vector2 = _entry_for(layout.cyclers, "cycler", up).pos
	var earth := _body_center(layout, EARTH)
	assert_true(lane.points[0].distance_to(earth) < lane.points[32].distance_to(earth),
		"the lane runs from the planet last passed, Earth")
	assert_true(square.distance_to(_point_at_fraction(lane.points, 0.25)) < 2.0,
		"a quarter of the way from Earth along the lane, got %s" % square)
	assert_near(lane.split, 8.0, 1.0, "solid ends about a quarter of the way along")

	var down := fleet.cyclers[1] # DOWN, short leg Mars -> Earth over [130, 276]
	fleet.advance_to(150.0)
	var earlier: Vector2 = _entry_for(DiagramLayout.build(fleet, SIZE).cyclers, "cycler", down).pos
	fleet.advance_to(200.0)
	var later: Vector2 = _entry_for(DiagramLayout.build(fleet, SIZE).cyclers, "cycler", down).pos
	assert_true(later.x < earlier.x, "a DOWN cycler on its short leg moves right to left (%s -> %s)" % [earlier, later])


func test_lane_position_is_fixed_by_phase() -> void:
	var fleet := _fleet()
	var first := DiagramLayout.build(fleet, SIZE)
	fleet.advance_to(400.0)
	var second := DiagramLayout.build(fleet, SIZE)
	for cycler in fleet.cyclers:
		var a: Vector2 = _entry_for(first.lanes, "cycler", cycler).points[MIDPOINT]
		var b: Vector2 = _entry_for(second.lanes, "cycler", cycler).points[MIDPOINT]
		assert_true(a.distance_to(b) < 0.01, "%s's lane stays put" % cycler.name)


func test_toward_mars_above_band() -> void:
	var fleet := _fleet()
	var outbound := _parked(fleet, "Kestrel", EARTH)
	var inbound := _parked(fleet, "Heron", MARS)
	fleet.depart(outbound, MARS)
	fleet.depart(inbound, EARTH)
	fleet.advance_to(5.0)
	var layout := DiagramLayout.build(fleet, SIZE)
	var out_mid: Vector2 = _entry_for(layout.trips, "transport", outbound).points[MIDPOINT]
	var in_mid: Vector2 = _entry_for(layout.trips, "transport", inbound).points[MIDPOINT]
	assert_true(out_mid.y < _top_lane_midpoint(layout).y, "Earth -> Mars arcs above the band, got %s" % out_mid)
	assert_true(in_mid.y > _bottom_lane_midpoint(layout).y, "Mars -> Earth arcs below the band, got %s" % in_mid)


func test_same_route_nests() -> void:
	var fleet := _fleet()
	var trips: Array[Transport] = []
	for ship_name in ["Kestrel", "Heron", "Osprey"]:
		var transport := _parked(fleet, ship_name, EARTH)
		fleet.depart(transport, MARS)
		trips.append(transport)
		fleet.advance_to(fleet.day + 1.0)
	# Build from a fleet listing them out of departure order, so order must come from t0.
	fleet.transports.reverse()
	var layout := DiagramLayout.build(fleet, SIZE)
	var heights := trips.map(func(t: Transport) -> float:
		return _entry_for(layout.trips, "transport", t).points[MIDPOINT].y)
	assert_true(heights[0] > heights[1] and heights[1] > heights[2],
		"each later trip arcs further from the band, got %s" % [heights])
	assert_true(heights[0] - heights[1] > 4.0 and heights[1] - heights[2] > 4.0, "nested arcs never coincide")


func test_earth_moon_trips_bow_to_opposite_sides() -> void:
	var fleet := _fleet()
	var out := _parked(fleet, "Kestrel", EARTH)
	var back := _parked(fleet, "Heron", MOON)
	fleet.depart(out, MOON)
	fleet.depart(back, EARTH)
	var layout := DiagramLayout.build(fleet, SIZE)
	var earth := _body_center(layout, EARTH)
	var moon := _body_center(layout, MOON)
	var axis := (moon - earth).normalized()
	var side := func(t: Transport) -> float:
		return axis.cross(_entry_for(layout.trips, "transport", t).points[MIDPOINT] - earth)
	assert_true(side.call(out) * side.call(back) < 0.0, "toward the Moon and back to Earth bow to opposite sides")


## How far the curve's midpoint sits off the straight line between its ends, per unit of that line's length.
func _sag_ratio(points: PackedVector2Array) -> float:
	var chord := points[points.size() - 1] - points[0]
	return absf(chord.normalized().cross(points[MIDPOINT] - points[0])) / chord.length()


func test_cycler_trips_curve_more_than_the_lanes() -> void:
	var fleet := _fleet()
	fleet.advance_to(50.0)
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, fleet.cyclers[0])
	var layout := DiagramLayout.build(fleet, SIZE)
	var trip: PackedVector2Array = layout.trips[0].points
	var most_bent_lane := 0.0
	for lane in layout.lanes:
		most_bent_lane = maxf(most_bent_lane, _sag_ratio(lane.points))
	assert_true(_sag_ratio(trip) > most_bent_lane * 1.2,
		"the trip bends more than any lane (trip %.3f, lane %.3f)" % [_sag_ratio(trip), most_bent_lane])
	var chord := trip[trip.size() - 1] - trip[0]
	assert_true(chord.x > 0.0 and chord.cross(trip[MIDPOINT] - trip[0]) < 0.0, "heading toward Mars, it bows up, as body routes to Mars do")


func test_triangle_at_progress() -> void:
	var fleet := _fleet()
	var transport := _parked(fleet, "Kestrel", EARTH)
	fleet.depart(transport, MARS)
	fleet.advance_to(transport.t0 + 0.37 * (transport.t_arrive - transport.t0))
	var trip: Dictionary = DiagramLayout.build(fleet, SIZE).trips[0]
	var points: PackedVector2Array = trip.points
	assert_true(points.size() == DiagramLayout.CURVE_POINTS, "33 points per trip")
	var expected := _point_at_fraction(points, fleet.progress(transport))
	assert_true(trip.tri_pos.distance_to(expected) < 2.0, "triangle at 37%% by arc length (%s vs %s)" % [trip.tri_pos, expected])

	var lengths := _arc_lengths(points)
	var tri_along := lengths[trip.split - 1] + points[trip.split - 1].distance_to(trip.tri_pos)
	assert_true(trip.split >= 1 and trip.split < points.size(), "split is inside the curve")
	assert_true(tri_along <= lengths[trip.split] + 0.01, "the split falls at the triangle: it sits between points[split - 1] and points[split]")

	var tangent: Vector2 = points[trip.split] - points[trip.split - 1]
	assert_near(angle_difference(trip.tri_angle, tangent.angle()), 0.0, 0.01, "the triangle points along the curve")


func test_no_lines_for_parked_and_docked() -> void:
	var fleet := _fleet()
	var parked := _parked(fleet, "Kestrel", EARTH)
	var docked := Transport.docked_to("Wren", fleet.cyclers[2])
	fleet.transports.append(docked)
	var layout := DiagramLayout.build(fleet, SIZE)
	assert_true(layout.trips.is_empty(), "no trip lines")
	assert_true(layout.parked.size() == 2, "both in parked, got %d" % layout.parked.size())
	var earth := _body_center(layout, EARTH)
	var square: Vector2 = _entry_for(layout.cyclers, "cycler", fleet.cyclers[2]).pos
	var parked_pos: Vector2 = _entry_for(layout.parked, "transport", parked).pos
	var docked_pos: Vector2 = _entry_for(layout.parked, "transport", docked).pos
	assert_near(parked_pos.distance_to(earth), 40.0 + 16.8, 0.01, "parked in a ring just outside Earth")
	assert_true(docked_pos.distance_to(square + Vector2(0, -18)) < 0.01, "docked just above its cycler's square")


func _parked_pos(layout: Dictionary, ship_name: String) -> Vector2:
	for entry in layout.parked:
		if entry.transport.name == ship_name:
			return entry.pos
	return Vector2.INF


func test_parked_ships_stack_in_a_column_beside_their_body() -> void:
	for body in [EARTH, MOON, MARS]:
		var fleet := _fleet()
		for ship_name in ["Wren", "Heron", "Kestrel"]:
			_parked(fleet, ship_name, body)
		var layout := DiagramLayout.build(fleet, SIZE)
		var center := _body_center(layout, body)
		var heron := _parked_pos(layout, "Heron")
		var kestrel := _parked_pos(layout, "Kestrel")
		var wren := _parked_pos(layout, "Wren")
		var name := Orbits.body_name(body)
		var side := 1.0 if body == MARS else -1.0
		for p in [heron, kestrel, wren]:
			assert_true((p.x - center.x) * side > DiagramLayout.BODY_RADII[body], "%s: on its %s, clear of it" % [name, "right" if side > 0 else "left"])
			assert_near(p.x, heron.x, 0.001, "%s: one column" % name)
		assert_true(heron.y < kestrel.y and kestrel.y < wren.y, "%s: top to bottom in name order" % name)
		assert_near(kestrel.y - heron.y, DiagramLayout.PARKED_SPACING, 0.001, "%s: evenly spaced" % name)
		assert_near(kestrel.y, center.y, 0.001, "%s: centered on the body's height" % name)


func test_a_full_column_starts_another_further_out() -> void:
	var fleet := _fleet()
	var count := DiagramLayout.PARKED_PER_COLUMN + 1
	for i in count:
		_parked(fleet, "Ship %02d" % i, MOON)
	var layout := DiagramLayout.build(fleet, SIZE)
	var first := _parked_pos(layout, "Ship 00")
	var overflow := _parked_pos(layout, "Ship %02d" % (count - 1))
	assert_near(first.x - overflow.x, DiagramLayout.PARKED_SPACING, 0.001, "the next column sits one step further left")
	for entry in layout.parked:
		assert_true(Rect2(Vector2.ZERO, SIZE).has_point(entry.pos), "%s stays on the canvas" % entry.transport.name)

func test_docked_row_spacing() -> void:
	var fleet := _fleet()
	var host := fleet.cyclers[0]
	for ship_name in ["Wren", "Heron"]:
		fleet.transports.append(Transport.docked_to(ship_name, host))
	var layout := DiagramLayout.build(fleet, SIZE)
	var square: Vector2 = _entry_for(layout.cyclers, "cycler", host).pos
	var positions: Array = layout.parked.map(func(entry: Dictionary) -> Vector2: return entry.pos)
	assert_true(positions.all(func(p: Vector2) -> bool: return absf(p.y - (square.y - 18.0)) < 0.01), "row 18 px above")
	assert_near(absf(positions[0].x - positions[1].x), 14.4, 0.01, "14.4 px apart")
	assert_near((positions[0].x + positions[1].x) / 2.0, square.x, 0.01, "centered on the square")


func test_scales_uniformly_to_size() -> void:
	var fleet := _fleet()
	var full := DiagramLayout.build(fleet, SIZE)
	var half := DiagramLayout.build(fleet, SIZE / 2.0)
	assert_true(_body_center(half, EARTH).distance_to(_body_center(full, EARTH) / 2.0) < 0.01, "positions halve")
	assert_near(half.bodies[0].radius, full.bodies[0].radius / 2.0, 0.001, "radii halve")


func test_deterministic() -> void:
	var fleet := _fleet()
	fleet.advance_to(40.0)
	_parked(fleet, "Kestrel", EARTH)
	var flying := _parked(fleet, "Heron", MARS)
	fleet.depart(flying, fleet.cyclers[3])
	fleet.advance_to(42.0)
	assert_true(DiagramLayout.build(fleet, SIZE) == DiagramLayout.build(fleet, SIZE), "same fleet, same layout")


func _icon_rect(center: Vector2) -> Rect2:
	var reach := DiagramLayout.ICON_CLEARANCE
	return Rect2(center - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)


func test_ship_labels_stay_clear_of_docked_row_and_own_icon() -> void:
	var fleet := _fleet()
	var host := fleet.cyclers[0]
	for ship_name in ["Wren", "Heron", "Kestrel"]:
		fleet.transports.append(Transport.docked_to(ship_name, host))
	var layout := DiagramLayout.build(fleet, SIZE)
	var label_size := Vector2(60, 20)
	var square: Vector2 = _entry_for(layout.cyclers, "cycler", host).pos
	var icons := [_icon_rect(square)]
	for entry in layout.parked:
		icons.append(_icon_rect(entry.pos))
	var ships: Array = [host]
	ships.append_array(fleet.transports)
	for ship in ships:
		var label := DiagramLayout.ship_label_rect(layout, ship, label_size)
		assert_near(label.size.x, label_size.x + 2.0 * DiagramLayout.LABEL_PAD, 0.01, "%s label is padded text" % ship.name)
		for icon in icons:
			assert_true(not label.intersects(icon), "%s label %s clear of icon %s" % [ship.name, label, icon])


func test_parked_ship_label_sits_on_the_far_side_of_its_column() -> void:
	for body in [EARTH, MARS]:
		var fleet := _fleet()
		var transport := _parked(fleet, "Wren", body)
		var layout := DiagramLayout.build(fleet, SIZE)
		var pos: Vector2 = _entry_for(layout.parked, "transport", transport).pos
		var label := DiagramLayout.ship_label_rect(layout, transport, Vector2(60, 20))
		var side := 1.0 if body == MARS else -1.0
		assert_true((label.get_center().x - pos.x) * side > 0.0, "%s: label beyond its icon, away from the body" % Orbits.body_name(body))
		assert_true(not label.intersects(_icon_rect(pos)), "%s: label clear of its own icon" % Orbits.body_name(body))


## The smallest gap between neighboring lanes' ends at `body`.
func _smallest_lane_end_gap(layout: Dictionary, body: Orbits.Body) -> float:
	var center := _body_center(layout, body)
	var ends := []
	for lane in layout.lanes:
		var first: Vector2 = lane.points[0]
		var last: Vector2 = lane.points[lane.points.size() - 1]
		ends.append(first if first.distance_to(center) < last.distance_to(center) else last)
	ends.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var smallest := INF
	for i in range(1, ends.size()):
		smallest = minf(smallest, ends[i - 1].distance_to(ends[i]))
	return smallest


func test_lane_ends_are_as_far_apart_at_mars_as_at_earth() -> void:
	var layout := DiagramLayout.build(_fleet(), SIZE)
	var at_earth := _smallest_lane_end_gap(layout, EARTH)
	var at_mars := _smallest_lane_end_gap(layout, MARS)
	assert_near(at_earth, at_mars, 1.0, "Earth gap %.2f px vs Mars gap %.2f px" % [at_earth, at_mars])
	assert_true(at_mars >= 11.0, "Mars lane ends at least 11 px apart, got %.2f" % at_mars)


## `count` transports flying `origin` -> `destination`, departing a hundredth of
## a day apart (so all are still in flight), in departure order.
func _depart_many(fleet: Fleet, origin: Orbits.Body, destination: Orbits.Body, count: int) -> Array[Transport]:
	var trips: Array[Transport] = []
	for i in count:
		var ship_name := "%s-%s %d" % [Orbits.body_name(origin), Orbits.body_name(destination), i]
		var transport := _parked(fleet, ship_name, origin)
		assert_true(fleet.depart(transport, destination), "%s departs" % ship_name)
		trips.append(transport)
		fleet.advance_to(fleet.day + 0.01)
	return trips


const BODY_ROUTES := [[EARTH, MARS], [MARS, EARTH], [MOON, MARS], [MARS, MOON], [EARTH, MOON], [MOON, EARTH]]


func test_busy_routes_stay_on_canvas_and_nest_outward_by_departure() -> void:
	var fleet := _fleet()
	var by_route := {}
	for route in BODY_ROUTES:
		by_route[route] = _depart_many(fleet, route[0], route[1], 15)
	fleet.transports.reverse() # order must come from t0, not from the fleet's list
	for size in [SIZE, Vector2(800, 400), Vector2(1264, 790)]:
		var layout := DiagramLayout.build(fleet, size)
		var canvas := Rect2(Vector2.ZERO, size)
		for route in BODY_ROUTES:
			var middle := (_body_center(layout, route[0]) + _body_center(layout, route[1])) / 2.0
			var previous_reach := -INF
			for t in by_route[route]:
				var trip: Dictionary = _entry_for(layout.trips, "transport", t)
				assert_true(not trip.is_empty(), "%s is in flight" % t.name)
				var off_canvas: Array = Array(trip.points).filter(func(p: Vector2) -> bool: return not canvas.has_point(p))
				assert_true(off_canvas.is_empty(), "%s at %s: points off the canvas %s" % [t.name, size, off_canvas])
				assert_true(canvas.has_point(trip.tri_pos), "%s at %s: triangle %s on the canvas" % [t.name, size, trip.tri_pos])
				var label := DiagramLayout.ship_label_rect(layout, t, Vector2(60, 20))
				assert_true(label.position.y >= 0.0 and label.end.y <= size.y,
					"%s at %s: label %s inside the canvas vertically" % [t.name, size, label])
				assert_true(not label.intersects(_icon_rect(trip.tri_pos)), "%s label clear of its triangle" % t.name)
				var reach: float = trip.points[MIDPOINT].distance_to(middle)
				assert_true(reach > previous_reach, "%s at %s: arcs further out than the trip before it" % [t.name, size])
				previous_reach = reach


func test_body_routes_never_cross_lanes() -> void:
	var fleet := _fleet()
	var trips: Array[Transport] = []
	for route in BODY_ROUTES:
		trips.append_array(_depart_many(fleet, route[0], route[1], 3))
	_assert_no_lane_crossings(fleet, trips)


func _assert_no_lane_crossings(fleet: Fleet, trips: Array[Transport]) -> void:
	var layout := DiagramLayout.build(fleet, SIZE)
	for t in trips:
		var trip: Dictionary = _entry_for(layout.trips, "transport", t)
		assert_true(not trip.is_empty(), "%s is in flight" % t.name)
		if trip.is_empty():
			continue
		for lane in layout.lanes:
			for i in range(1, trip.points.size()):
				for j in range(1, lane.points.size()):
					var hit: Variant = Geometry2D.segment_intersects_segment(
						trip.points[i - 1], trip.points[i], lane.points[j - 1], lane.points[j])
					if hit != null and not _on_a_planet_edge(layout, hit):
						assert_true(false, "%s (to %s) crosses %s's lane at %s"
							% [t.name, Fleet.target_name(t.target), lane.cycler.name, hit])


## Whether `point` is on (or inside) a body's circle, where lines share endpoints.
func _on_a_planet_edge(layout: Dictionary, point: Vector2) -> bool:
	for body in layout.bodies:
		if point.distance_to(body.center) <= body.radius + 1.0:
			return true
	return false


func test_docked_row_clears_the_planet_at_a_flyby() -> void:
	var fleet := _fleet()
	var host := fleet.cyclers[0] # UP, on Earth's edge on day 0
	for ship_name in ["Wren", "Heron", "Kestrel", "Osprey"]:
		fleet.transports.append(Transport.docked_to(ship_name, host))
	var layout := DiagramLayout.build(fleet, SIZE)
	var earth := _body_center(layout, EARTH)
	var clearance: float = DiagramLayout.BODY_RADII[EARTH] + DiagramLayout.DOCKED_ROW_SPACING / 2.0
	var row_y: float = layout.parked[0].pos.y
	for entry in layout.parked:
		assert_true(entry.pos.distance_to(earth) >= clearance - 0.01,
			"%s at %s is clear of Earth (%.1f px from its center)" % [entry.transport.name, entry.pos, entry.pos.distance_to(earth)])
		assert_near(entry.pos.y, row_y, 0.01, "the row stays level")
