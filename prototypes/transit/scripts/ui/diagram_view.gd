class_name DiagramView
extends Control
## Draws the schematic from DiagramLayout every frame while visible. Clicking a
## shape selects that ship; clicking empty space clears the selection.

const PICK_RADIUS := 14.4
const SQUARE_SIZE := 14.4
const TRIANGLE_SIZE := 12.0
const LANE_WIDTH := 2.0
const TRIP_WIDTH := 1.5
const DASH := 4.0

const BODY_COLORS := {
	Orbits.Body.EARTH: Color(0.25, 0.5, 1.0),
	Orbits.Body.MOON: Color(0.95, 0.95, 0.95),
	Orbits.Body.MARS: Color(0.9, 0.3, 0.2),
}
const AMBER := Color(1.0, 0.72, 0.2)
const LIGHT_GRAY := Color(0.8, 0.82, 0.85)
const HIGHLIGHT := Color(1.0, 1.0, 1.0)
const LABEL_COLOR := Color(0.85, 0.88, 0.92)
## Keeps a ship name readable where lanes and trips run behind it.
const LABEL_BACKING := Color(0.05, 0.06, 0.09, 0.85)

## Set by Main.
var main: Main
## The last layout built, as DiagramLayout.build returns it.
var layout: Dictionary = {}

var _hovered: Variant = null


func attach(owner_main: Main) -> void:
	main = owner_main
	main.selection_changed.connect(func(_ship: Variant) -> void: queue_redraw())


func _process(_delta: float) -> void:
	if main != null and is_visible_in_tree():
		rebuild()


## Lays the fleet out for the current size and redraws.
func rebuild() -> void:
	layout = DiagramLayout.build(main.fleet, size)
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
		var hovered: Variant = ship_at(event.position)
		if hovered != _hovered:
			_hovered = hovered
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != null:
		_hovered = null
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
			_draw_split_curve(entry.points, entry.split, _cycler_pos(entry.cycler), AMBER, LANE_WIDTH)
	var selected_trip := {}
	for entry in layout.trips:
		if entry.transport == selected:
			selected_trip = entry
		else:
			_draw_split_curve(entry.points, entry.split, entry.tri_pos, LIGHT_GRAY, TRIP_WIDTH)
			_draw_triangle(entry.tri_pos, entry.tri_angle, false)
	for entry in layout.parked:
		_draw_triangle(entry.pos, _parked_angle(entry), entry.transport == selected)
	for entry in layout.cyclers:
		if entry.cycler != selected:
			_draw_square(entry.pos, false)

	# The selected ship goes on top of everything else.
	if not selected_lane.is_empty():
		var pos := _cycler_pos(selected_lane.cycler)
		_draw_split_curve(selected_lane.points, selected_lane.split, pos, AMBER, LANE_WIDTH + 1.0)
		_draw_square(pos, true)
	if not selected_trip.is_empty():
		_draw_split_curve(selected_trip.points, selected_trip.split, selected_trip.tri_pos, HIGHLIGHT, TRIP_WIDTH + 0.5)
		_draw_triangle(selected_trip.tri_pos, selected_trip.tri_angle, true)

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
	var from := joint
	for i in range(split, points.size()):
		draw_dashed_line(from, points[i], color, width, DASH)
		from = points[i]


func _draw_square(pos: Vector2, highlighted: bool) -> void:
	var rect := Rect2(pos - Vector2.ONE * SQUARE_SIZE / 2.0, Vector2.ONE * SQUARE_SIZE)
	draw_rect(rect, AMBER)
	if highlighted:
		draw_rect(rect.grow(2.0), HIGHLIGHT, false, 2.0)


func _draw_triangle(pos: Vector2, angle: float, highlighted: bool) -> void:
	var points := _triangle_points(pos, angle)
	draw_colored_polygon(points, LIGHT_GRAY)
	if highlighted:
		var outline := _triangle_points(pos, angle, TRIANGLE_SIZE + 5.0)
		outline.append(outline[0])
		draw_polyline(outline, HIGHLIGHT, 2.0, true)


## A triangle `length` px long, centered on `pos`, its tip pointing along `angle`.
func _triangle_points(pos: Vector2, angle: float, length := TRIANGLE_SIZE) -> PackedVector2Array:
	var ahead := Vector2.from_angle(angle)
	var side := ahead.orthogonal()
	var back := pos - ahead * length * 0.4
	return PackedVector2Array([pos + ahead * length * 0.6, back + side * length * 0.45, back - side * length * 0.45])


## Parked triangles point out from their body; docked ones point up.
func _parked_angle(entry: Dictionary) -> float:
	var transport: Transport = entry.transport
	if transport.state == Transport.State.AT_BODY:
		return (entry.pos - _body_entry(transport.body).center).angle()
	return -PI / 2.0


func _draw_hover_outline(ship: Variant) -> void:
	if ship is Cycler:
		var pos := _cycler_pos(ship)
		draw_rect(Rect2(pos - Vector2.ONE * (SQUARE_SIZE / 2.0 + 2.0), Vector2.ONE * (SQUARE_SIZE + 4.0)), HIGHLIGHT, false, 1.0)
		return
	var marker := _transport_marker(ship)
	var outline := _triangle_points(marker.pos, marker.angle, TRIANGLE_SIZE + 5.0)
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
