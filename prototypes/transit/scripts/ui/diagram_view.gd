class_name DiagramView
extends Control
## Draws the schematic from DiagramLayout every frame while visible. Clicking a
## shape selects that ship; clicking empty space clears the selection.

const PICK_RADIUS := 14.4
const LANE_WIDTH := 2.0
const TRIP_WIDTH := 1.5
## Screen px, the same on every line whatever its length or how finely it is sampled.
const DASH_LENGTH := 8.0
const DASH_GAP := 6.0

const BODY_COLORS := {
	Orbits.Body.EARTH: Color(0.25, 0.5, 1.0),
	Orbits.Body.MOON: Color(0.95, 0.95, 0.95),
	Orbits.Body.MARS: Color(0.9, 0.3, 0.2),
}
## Each ship's icon has its own color, from ShipIcons; these are for the lines.
const LANE_COLOR := Color(1.0, 0.72, 0.2)
const TRIP_COLOR := Color(0.8, 0.82, 0.85)
const HIGHLIGHT := Color(1.0, 1.0, 1.0)
const LABEL_COLOR := Color(0.85, 0.88, 0.92)
## Keeps a ship name readable where lanes and trips run behind it.
const LABEL_BACKING := Color(0.05, 0.06, 0.09, 0.85)

## Set by Main.
var main: Main
## The last layout built, as DiagramLayout.build returns it.
var layout: Dictionary = {}

var _hovered: Variant = null
## Where the mouse last was inside the view; null once it leaves.
var _mouse_position: Variant = null


func attach(owner_main: Main) -> void:
	main = owner_main
	main.selection_changed.connect(func(_ship: Variant) -> void: queue_redraw())


func _process(_delta: float) -> void:
	if main != null and is_visible_in_tree():
		rebuild()


## Lays the fleet out for the current size and redraws.
func rebuild() -> void:
	layout = DiagramLayout.build(main.fleet, size)
	_update_hover()
	queue_redraw()


## The nearest ship drawn within PICK_RADIUS of `point`, or null.
func ship_at(point: Vector2) -> Variant:
	if layout.is_empty():
		return null
	var nearest: Variant = null
	var nearest_distance := PICK_RADIUS
	for entry in layout.cyclers:
		var d: float = point.distance_to(entry.pos)
		if d <= nearest_distance:
			nearest = entry.cycler
			nearest_distance = d
	for entry in layout.trips:
		var d: float = point.distance_to(entry.tri_pos)
		if d <= nearest_distance:
			nearest = entry.transport
			nearest_distance = d
	for entry in layout.parked:
		var d: float = point.distance_to(entry.pos)
		if d <= nearest_distance:
			nearest = entry.transport
			nearest_distance = d
	return nearest


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		main.select(ship_at(event.position))
		accept_event()
	elif event is InputEventMouseMotion:
		_mouse_position = event.position
		_update_hover()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse_position = null
		_update_hover()


## Ships move under a mouse that holds still, so hover is recomputed whenever
## the layout changes as well as when the mouse moves.
func _update_hover() -> void:
	var hovered: Variant = null
	if _mouse_position != null:
		hovered = ship_at(_mouse_position)
	if hovered != _hovered:
		_hovered = hovered
		queue_redraw()


func _draw() -> void:
	if layout.is_empty():
		return
	var selected: Variant = main.selected
	for entry in layout.bodies:
		draw_circle(entry.center, entry.radius, BODY_COLORS[entry.body])

	var selected_lane := {}
	for entry in layout.lanes:
		if entry.cycler == selected:
			selected_lane = entry
		else:
			_draw_split_curve(entry.points, entry.split, _cycler_pos(entry.cycler), LANE_COLOR, LANE_WIDTH)
	var selected_trip := {}
	for entry in layout.trips:
		if entry.transport == selected:
			selected_trip = entry
		else:
			_draw_split_curve(entry.points, entry.split, entry.tri_pos, TRIP_COLOR, TRIP_WIDTH)
			_draw_triangle(entry.transport, entry.tri_pos, entry.tri_angle, false)
	for entry in layout.parked:
		_draw_triangle(entry.transport, entry.pos, _parked_angle(entry), entry.transport == selected)
	for entry in layout.cyclers:
		if entry.cycler != selected:
			_draw_square(entry.cycler, entry.pos, false)

	# The selected ship goes on top of everything else.
	if not selected_lane.is_empty():
		var pos := _cycler_pos(selected_lane.cycler)
		_draw_split_curve(selected_lane.points, selected_lane.split, pos, LANE_COLOR, LANE_WIDTH + 1.0)
		_draw_square(selected_lane.cycler, pos, true)
	if not selected_trip.is_empty():
		_draw_split_curve(selected_trip.points, selected_trip.split, selected_trip.tri_pos, HIGHLIGHT, TRIP_WIDTH + 0.5)
		_draw_triangle(selected_trip.transport, selected_trip.tri_pos, selected_trip.tri_angle, true)

	for entry in layout.bodies:
		_draw_body_label(entry)
	for ship in [_hovered, selected]:
		if ship != null:
			_draw_ship_label(ship)
	if _hovered != null and _hovered != selected:
		_draw_hover_outline(_hovered)


## Solid from the start to `joint` (the marker on segment split-1 .. split), dotted after it.
func _draw_split_curve(points: PackedVector2Array, split: int, joint: Vector2, color: Color, width: float) -> void:
	var solid := points.slice(0, split)
	solid.append(joint)
	draw_polyline(solid, color, width, true)
	var dotted := PackedVector2Array([joint])
	dotted.append_array(points.slice(split))
	var pieces := PackedVector2Array()
	for dash in dashes(dotted):
		for i in range(1, dash.size()):
			pieces.append_array([dash[i - 1], dash[i]])
	if not pieces.is_empty():
		draw_multiline(pieces, color, width, true)


## `polyline` cut into DASH_LENGTH dashes DASH_GAP apart, in order from its
## start. The pattern is laid from the end, so the dashes ahead of a moving
## ship stay put and only the one nearest the start is cut short.
static func dashes(polyline: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var dash := PackedVector2Array()
	var in_dash := true
	var left := DASH_LENGTH # of the current dash or gap
	var from := polyline[polyline.size() - 1]
	dash.append(from)
	for i in range(polyline.size() - 2, -1, -1):
		var to := polyline[i]
		var segment_left := from.distance_to(to)
		while segment_left > left:
			from = from.move_toward(to, left)
			segment_left -= left
			if in_dash:
				dash.append(from)
				result.append(dash)
				dash = PackedVector2Array()
			else:
				dash = PackedVector2Array([from])
			in_dash = not in_dash
			left = DASH_LENGTH if in_dash else DASH_GAP
		left -= segment_left
		from = to
		if in_dash:
			dash.append(from)
	if in_dash and dash.size() > 1:
		result.append(dash)
	result.reverse()
	for d in result:
		d.reverse()
	return result


func _draw_square(cycler: Cycler, pos: Vector2, highlighted: bool) -> void:
	var rect := ShipIcons.square_rect(pos)
	draw_rect(rect, main.icons.color_of(cycler))
	if highlighted:
		draw_rect(rect.grow(2.0), HIGHLIGHT, false, 2.0)


func _draw_triangle(transport: Transport, pos: Vector2, angle: float, highlighted: bool) -> void:
	var points := ShipIcons.triangle_points(pos, angle)
	draw_colored_polygon(points, main.icons.color_of(transport))
	if highlighted:
		var outline := ShipIcons.triangle_points(pos, angle, ShipIcons.TRIANGLE_SIZE + 5.0)
		outline.append(outline[0])
		draw_polyline(outline, HIGHLIGHT, 2.0, true)


## Parked triangles point out from their body; docked ones point up.
func _parked_angle(entry: Dictionary) -> float:
	var transport: Transport = entry.transport
	if transport.state == Transport.State.AT_BODY:
		return (entry.pos - _body_entry(transport.body).center).angle()
	return -PI / 2.0


func _draw_hover_outline(ship: Variant) -> void:
	if ship is Cycler:
		var pos := _cycler_pos(ship)
		draw_rect(ShipIcons.square_rect(pos, ShipIcons.SQUARE_SIZE + 4.0), HIGHLIGHT, false, 1.0)
		return
	var marker := _transport_marker(ship)
	var outline := ShipIcons.triangle_points(marker.pos, marker.angle, ShipIcons.TRIANGLE_SIZE + 5.0)
	outline.append(outline[0])
	draw_polyline(outline, HIGHLIGHT, 1.0, true)


func _draw_body_label(entry: Dictionary) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text := Orbits.body_name(entry.body)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# Clear of the parked ring: Earth's label to its left, Mars's to its right, the Moon's above it.
	var reach: float = entry.radius + 26.0
	var anchor: Vector2 = entry.center
	match entry.body:
		Orbits.Body.EARTH:
			anchor += Vector2(-reach - text_size.x, text_size.y / 4.0)
		Orbits.Body.MARS:
			anchor += Vector2(reach, text_size.y / 4.0)
		_:
			anchor += Vector2(-text_size.x / 2.0, -reach)
	draw_string(font, anchor, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _draw_ship_label(ship: Variant) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var text_size := font.get_string_size(ship.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var rect := DiagramLayout.ship_label_rect(layout, ship, text_size)
	if rect == Rect2():
		return
	draw_rect(rect, LABEL_BACKING)
	var text_origin := rect.position + Vector2(DiagramLayout.LABEL_PAD, DiagramLayout.LABEL_PAD + font.get_ascent(font_size))
	draw_string(font, text_origin, ship.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HIGHLIGHT)


func _cycler_pos(cycler: Cycler) -> Vector2:
	for entry in layout.cyclers:
		if entry.cycler == cycler:
			return entry.pos
	return Vector2.INF


## {pos, angle} of a transport's triangle, wherever it is drawn.
func _transport_marker(transport: Transport) -> Dictionary:
	for entry in layout.trips:
		if entry.transport == transport:
			return {pos = entry.tri_pos, angle = entry.tri_angle}
	for entry in layout.parked:
		if entry.transport == transport:
			return {pos = entry.pos, angle = _parked_angle(entry)}
	return {pos = Vector2.INF, angle = 0.0}


func _body_entry(body: Orbits.Body) -> Dictionary:
	for entry in layout.bodies:
		if entry.body == body:
			return entry
	return {}
