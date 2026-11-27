class_name ShipView3D
extends SubViewportContainer
## The connected ship in 3D: each room a see-through box tinted by its status, each door and
## hatch a small panel on its face coloured by its state, and each room's name always facing the
## screen. Left-drag orbits the camera round the ship, the wheel zooms, and a click (press and
## release without dragging) on a room emits `room_clicked`. Built once for one ship; show_ship()
## recolours it in place.

signal room_clicked(room_id: String)

const DOOR_CLOSED := Color("c8ccd2")
const DOOR_OPEN := Color("4fa3ff")
const DOOR_MOVING := DashboardView.AMBER
const DOOR_UNPOWERED := Color("5a5d63")
const FILL_ALPHA := 0.1
const SELECTED_FILL_ALPHA := 0.3
const EDGE_ALPHA := 0.55
const SELECTED_EDGE_ALPHA := 1.0
const DOOR_THICKNESS_M := 0.15
## A name's font size on screen in control pixels; its capitals come out about 14-16 px tall.
const LABEL_EM_PX := 20.0
const LABEL_FONT_SIZE := 48
const LABEL_OUTLINE_SIZE := 12
const START_YAW_DEG := 45.0
const START_PITCH_DEG := 35.0
const PITCH_LIMIT_DEG := 85.0
## The share of the view's half-width and half-height the ship's farthest corner may reach.
const FRAME_FILL := 0.9
const ORBIT_RAD_PER_PX := 0.01
const ZOOM_STEP := 1.15
const MIN_ZOOM := 0.1
const MAX_ZOOM := 5.0
## A press that moves farther than this before release is a drag, not a click.
const CLICK_SLOP_PX := 4.0

var viewport: SubViewport
var camera: Camera3D
## Holds every room and door; the camera moves round it and it never moves.
var ship_root: Node3D
## The point the camera orbits and looks at: the centre of the ship's bounds.
var focus := Vector3.ZERO

## room id -> {box: MeshInstance3D, fill: StandardMaterial3D, edge: StandardMaterial3D, label: Label3D}
var _rooms := {}
## opening id -> {panel: MeshInstance3D, material: StandardMaterial3D}
var _doors := {}
var _room_list: Array[Room] = []
var _yaw := deg_to_rad(START_YAW_DEG)
var _pitch := deg_to_rad(START_PITCH_DEG)
var _framed_distance := 1.0
var _distance := 1.0
## Every room corner in ship space.
var _corners := PackedVector3Array()
## Once the user orbits or zooms, a resize no longer re-frames the ship.
var _user_moved := false
## The centre of the ship's bounds, from which the starting focus is nudged to centre the ship on screen.
var _bounds_center := Vector3.ZERO
var _press_at := Vector2.ZERO
var _pressed := false
var _dragged := false


func _init(ship: Ship) -> void:
	stretch = true
	focus_mode = Control.FOCUS_NONE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	add_child(viewport)
	ship_root = Node3D.new()
	viewport.add_child(ship_root)
	for room in ship.rooms:
		_room_list.append(room)
		_build_room(room)
	for opening in ship.openings:
		_build_door(ship, opening)
	camera = Camera3D.new()
	viewport.add_child(camera)
	_frame(ship)
	_size_labels()
	gui_input.connect(_on_gui_input)
	resized.connect(_on_resized)


## Recolours the rooms and doors for the ship's state now; `selected_room` is drawn brighter.
func show_ship(ship: Ship, selected_room: String) -> void:
	for room in _room_list:
		var color := DashboardView.status_color(DashboardModel.room_level(ship, room.id))
		var selected := room.id == selected_room
		var entry: Dictionary = _rooms[room.id]
		_set_color(entry.fill, Color(color, SELECTED_FILL_ALPHA if selected else FILL_ALPHA))
		_set_color(entry.edge, Color(color, SELECTED_EDGE_ALPHA if selected else EDGE_ALPHA))
		var label: Label3D = entry.label
		if label.modulate != color:
			label.modulate = color
	for opening in ship.openings:
		_set_color(_doors[opening.id].material, _door_color(opening, ship.power.is_powered(opening.id)))


func room_box(room_id: String) -> MeshInstance3D:
	return _rooms[room_id].box


## The room's name, drawn at its centre.
func room_name(room_id: String) -> Label3D:
	return _rooms[room_id].label


## The colour the room's box is filled with, alpha included.
func room_tint(room_id: String) -> Color:
	return _rooms[room_id].fill.albedo_color


func room_edge_color(room_id: String) -> Color:
	return _rooms[room_id].edge.albedo_color


func door_panel(opening_id: String) -> MeshInstance3D:
	return _doors[opening_id].panel


func door_color(opening_id: String) -> Color:
	return _doors[opening_id].material.albedo_color


## Where a ship-space point appears, in this control's own coordinates.
func screen_point(ship_point: Vector3) -> Vector2:
	return camera.unproject_position(ship_point) * _view_to_control()


## The id of the nearest room under `point` (this control's own coordinates), or "" if none.
func name_at(point: Vector2) -> String:
	var nearest := INF
	var found := ""
	var font := ThemeDB.fallback_font
	for room in _room_list:
		if camera.is_position_behind(room.position):
			continue
		var text: String = _rooms[room.id].label.text
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x * LABEL_EM_PX / LABEL_FONT_SIZE
		var rect := Rect2(Vector2.ZERO, Vector2(width, LABEL_EM_PX))
		rect.position = screen_point(room.position) - rect.size * 0.5
		var distance := camera.global_position.distance_to(room.position)
		if rect.has_point(point) and distance < nearest:
			nearest = distance
			found = room.id
	return found


func room_at(point: Vector2) -> String:
	var named := name_at(point)
	if named != "":
		return named
	var scale := _view_to_control()
	if scale.x == 0.0 or scale.y == 0.0:
		return ""
	var view_point := point / scale
	var origin := camera.project_ray_origin(view_point)
	var direction := camera.project_ray_normal(view_point)
	var nearest := INF
	var found := ""
	for room in _room_list:
		var distance := _ray_box_distance(room, origin, direction)
		if distance < nearest:
			nearest = distance
			found = room.id
	return found


func _build_room(room: Room) -> void:
	var holder := Node3D.new()
	holder.name = room.id
	holder.transform = Transform3D(room.orientation, room.position)
	ship_root.add_child(holder)
	var box := MeshInstance3D.new()
	box.name = "room " + room.id
	var mesh := BoxMesh.new()
	mesh.size = room.size
	box.mesh = mesh
	var fill := _material()
	box.material_override = fill
	holder.add_child(box)
	var edges := MeshInstance3D.new()
	edges.mesh = _edge_mesh(room.size)
	var edge := _material()
	edges.material_override = edge
	holder.add_child(edges)
	var label := Label3D.new()
	label.text = room.id.to_upper()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = LABEL_OUTLINE_SIZE
	label.outline_modulate = Color.BLACK
	label.render_priority = 1
	label.outline_render_priority = 0
	holder.add_child(label)
	_rooms[room.id] = {"box": box, "fill": fill, "edge": edge, "label": label}


## A thin panel the opening's size, centred on it and lying in the face of its first room. Width
## runs across the face and height up it; on a floor or ceiling, height runs along the room.
func _build_door(ship: Ship, opening: Opening) -> void:
	var host := ship.room(opening.room_a)
	var normal := host.face_normal(opening.face_a)
	var is_floor := opening.face_a == Room.Face.PLUS_Y or opening.face_a == Room.Face.MINUS_Y
	var up := host.orientation.z if is_floor else host.orientation.y
	var across := up.cross(normal).normalized()
	var panel := MeshInstance3D.new()
	panel.name = "door " + opening.id
	var mesh := BoxMesh.new()
	mesh.size = Vector3(opening.size.x, opening.size.y, DOOR_THICKNESS_M)
	panel.mesh = mesh
	panel.transform = Transform3D(Basis(across, normal.cross(across), normal), opening.position)
	var material := _material()
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	panel.material_override = material
	ship_root.add_child(panel)
	_doors[opening.id] = {"panel": panel, "material": material}


## The 12 edges of a box `size` centred on the origin, as lines.
func _edge_mesh(size: Vector3) -> ArrayMesh:
	var half := size * 0.5
	var lines := PackedVector3Array()
	for corner in 8:
		var start := Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y,
				half.z if corner & 4 else -half.z)
		for axis in 3:
			if not (corner & (1 << axis)):
				var end := start
				end[axis] = half[axis]
				lines.append(start)
				lines.append(end)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _set_color(material: StandardMaterial3D, color: Color) -> void:
	if material.albedo_color != color:
		material.albedo_color = color


## Without power a door holds where it is, so that is what it shows.
func _door_color(opening: Opening, powered: bool) -> Color:
	if not powered:
		return DOOR_UNPOWERED
	match opening.state:
		Opening.State.OPEN:
			return DOOR_OPEN
		Opening.State.CLOSED:
			return DOOR_CLOSED
	return DOOR_MOVING


## Aims at the middle of the ship as it appears from the start angle, from the nearest distance at which every room corner
## stays inside FRAME_FILL of both the horizontal and the vertical field of view.
func _frame(ship: Ship) -> void:
	_corners.clear()
	var bounds := AABB(ship.rooms[0].position, Vector3.ZERO)
	for room in ship.rooms:
		for corner in 8:
			var offset := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
			var point := room.position + room.orientation * (room.size * 0.5 * offset)
			_corners.append(point)
			bounds = bounds.expand(point)
	_bounds_center = bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 1.0)
	camera.near = radius * 0.01
	camera.far = radius * 4.0 * MAX_ZOOM
	_reframe()


func _reframe() -> void:
	var basis := Basis.from_euler(Vector3(-_pitch, _yaw, 0.0))
	var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
	var aspect := size.x / size.y if size.x > 0.0 and size.y > 0.0 else 2.0
	var tans := Vector2(tan_v * aspect, tan_v)
	focus = _bounds_center
	# A distance at which every corner is inside the fill however the perspective falls.
	var safe := 1.0
	for point in _corners:
		var local := basis.inverse() * (point - focus)
		safe = maxf(safe, local.z + absf(local.x) / (tans.x * FRAME_FILL))
		safe = maxf(safe, local.z + absf(local.y) / (tans.y * FRAME_FILL))
	_framed_distance = safe
	# Perspective makes the near corners reach farther than the far ones, so centre the corners'
	# projection and pull the camera in until the farthest reaches FRAME_FILL, a few times over.
	for pass_index in 4:
		var rect := _projected_corners(basis, _framed_distance, tans)
		var shift := rect.get_center() * tans * _framed_distance
		focus += basis * Vector3(shift.x, shift.y, 0.0)
		var low := 0.0
		var high := safe
		for step in 24:
			var middle := (low + high) * 0.5
			var reach := _projected_corners(basis, middle, tans)
			var fits := middle > 0.0 and maxf(maxf(-reach.position.x, reach.end.x), maxf(-reach.position.y, reach.end.y)) <= FRAME_FILL
			if fits:
				high = middle
			else:
				low = middle
		_framed_distance = high
	_distance = _framed_distance
	_place_camera()


## The corners' bounds on the screen from `distance` away at the current focus, with the view's
## edges at -1 and 1 on each axis; a corner behind the camera counts as far off screen.
func _projected_corners(basis: Basis, distance: float, tans: Vector2) -> Rect2:
	var inverse := basis.inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in _corners:
		var local := inverse * (point - focus)
		var depth := distance - local.z
		var ndc := Vector2(local.x, local.y) / (maxf(depth, 1e-4) * tans)
		low = low.min(ndc)
		high = high.max(ndc)
	return Rect2(low, high - low)


func _on_resized() -> void:
	_size_labels()
	if not _user_moved:
		_reframe()


## Sets each name's world size so it is LABEL_EM_PX tall on screen: with fixed_size a label spans
## font size x pixel size / (2 tan(fov / 2)) of the view's height.
func _size_labels() -> void:
	if size.y <= 0.0:
		return
	var pixel_size := LABEL_EM_PX * 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / (LABEL_FONT_SIZE * size.y)
	for entry in _rooms.values():
		entry.label.pixel_size = pixel_size


func _place_camera() -> void:
	var offset := Basis.from_euler(Vector3(-_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, _distance)
	camera.transform = Transform3D(Basis.IDENTITY, focus + offset).looking_at(focus, Vector3.UP)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_pressed = true
					_dragged = false
					_press_at = button.position
				elif _pressed:
					_pressed = false
					if not _dragged:
						var room_id := room_at(button.position)
						if room_id != "":
							room_clicked.emit(room_id)
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom(1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(ZOOM_STEP)
	elif event is InputEventMouseMotion and _pressed:
		var motion := event as InputEventMouseMotion
		if not _dragged and motion.position.distance_to(_press_at) > CLICK_SLOP_PX:
			_dragged = true
		if _dragged:
			_user_moved = true
			_yaw -= motion.relative.x * ORBIT_RAD_PER_PX
			var limit := deg_to_rad(PITCH_LIMIT_DEG)
			_pitch = clampf(_pitch + motion.relative.y * ORBIT_RAD_PER_PX, -limit, limit)
			_place_camera()


func _zoom(factor: float) -> void:
	_user_moved = true
	_distance = clampf(_distance * factor, _framed_distance * MIN_ZOOM, _framed_distance * MAX_ZOOM)
	_place_camera()


## How many control pixels one viewport pixel spans; zero before layout.
func _view_to_control() -> Vector2:
	var view_size := Vector2(viewport.size)
	if view_size.x == 0.0 or view_size.y == 0.0:
		return Vector2.ZERO
	return size / view_size


## How far along the ray (unit `direction`) it first meets the room's box, or INF if it misses.
func _ray_box_distance(room: Room, origin: Vector3, direction: Vector3) -> float:
	var inverse := room.orientation.inverse()
	var local_origin := inverse * (origin - room.position)
	var local_direction := inverse * direction
	var half := room.size * 0.5
	var near := -INF
	var far := INF
	for axis in 3:
		if absf(local_direction[axis]) < 1e-9:
			if absf(local_origin[axis]) > half[axis]:
				return INF
			continue
		var t1 := (-half[axis] - local_origin[axis]) / local_direction[axis]
		var t2 := (half[axis] - local_origin[axis]) / local_direction[axis]
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
	if near > far or far < 0.0:
		return INF
	if near < 0.0:
		return INF
	return near
