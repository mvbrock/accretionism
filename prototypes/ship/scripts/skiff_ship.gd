class_name SkiffShip
extends Ship
## A three-room zero-g skiff (Cockpit, Cabin, Hold) in a row along Z, joined by doorways.
## Floors sit under y = 0 and ceilings over y = HEIGHT; "across" is world X.

const HALF_WIDTH := 4.0
const HEIGHT := 4.0
const DOOR_HALF_WIDTH := 1.0
const DOOR_HEIGHT := 3.2
const SLAB := 0.4
## [name, z_min, z_max]
const ROOMS := [["Cockpit", -12.0, -6.0], ["Cabin", -6.0, 4.0], ["Hold", 4.0, 12.0]]
const BULKHEAD_COLOR := Color(0.5, 0.5, 0.52)
const WALL := WORLD_LAYER | OCCLUDER_LAYER


static func room_color(i: int) -> Color:
	return Color.from_hsv(float(i) / ROOMS.size(), 0.65, 0.85)


static func trim_color(i: int) -> Color:
	return Color.from_hsv(float(i) / ROOMS.size(), 0.25, 0.75)


func _ready() -> void:
	for i in ROOMS.size():
		add_child(_build_room(i))
	add_child(_build_bulkhead("Bulkhead1", ROOMS[0][2]))
	add_child(_build_bulkhead("Bulkhead2", ROOMS[1][2]))
	add_child(_build_crates())


func has_gravity() -> bool:
	return false


## The middle of the Cabin floor.
func spawn_point() -> Vector3:
	return Vector3(0, 0.05, -1.0)


## The room's ceiling, plus every wall piece bounding it on the camera's side (its outward normal points against the view).
func room_fade_meshes(p: Vector3, view: Vector3) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var index := _room_at(p.z)
	if index == -1:
		return meshes
	var room := get_node(NodePath(ROOMS[index][0]))
	meshes.append(room.get_node("Ceiling/Mesh"))
	if view.x > 0.0:
		meshes.append(room.get_node("WallLeft/Mesh"))
	elif view.x < 0.0:
		meshes.append(room.get_node("WallRight/Mesh"))
	if view.z > 0.0:
		_append_end(meshes, room, "WallFore", "Bulkhead%d" % index, index > 0)
	elif view.z < 0.0:
		_append_end(meshes, room, "WallAft", "Bulkhead%d" % (index + 1), index < ROOMS.size() - 1)
	return meshes


## The index of the room whose z range holds `z`, or -1.
func _room_at(z: float) -> int:
	for i in ROOMS.size():
		if z >= ROOMS[i][1] and z <= ROOMS[i][2]:
			return i
	return -1


## Adds the pieces closing one end of `room`: a bulkhead's three panels, or the end wall.
func _append_end(meshes: Array[MeshInstance3D], room: Node, end_wall: String,
		bulkhead: String, has_bulkhead: bool) -> void:
	if has_bulkhead:
		for piece in ["Left", "Right", "Lintel"]:
			meshes.append(get_node("%s/%s/Mesh" % [bulkhead, piece]))
	else:
		meshes.append(room.get_node(end_wall + "/Mesh"))


func _build_room(i: int) -> Node3D:
	var room := Node3D.new()
	room.name = ROOMS[i][0]
	var z0: float = ROOMS[i][1]
	var z1: float = ROOMS[i][2]
	var w := HALF_WIDTH
	var h := HEIGHT
	room.add_child(make_panel("Floor", box_points(Vector3(-w - SLAB, -SLAB, z0), Vector3(w + SLAB, 0, z1)),
			room_color(i), WORLD_LAYER | FLOOR_LAYER))
	room.add_child(make_panel("Ceiling", box_points(Vector3(-w - SLAB, h, z0), Vector3(w + SLAB, h + SLAB, z1)),
			trim_color(i), WALL))
	room.add_child(make_panel("WallLeft", box_points(Vector3(-w - SLAB, 0, z0), Vector3(-w, h, z1)),
			trim_color(i), WALL))
	room.add_child(make_panel("WallRight", box_points(Vector3(w, 0, z0), Vector3(w + SLAB, h, z1)),
			trim_color(i), WALL))
	if i == 0:
		room.add_child(make_panel("WallFore", box_points(Vector3(-w, 0, z0 - SLAB), Vector3(w, h, z0)),
				trim_color(i), WALL))
	if i == ROOMS.size() - 1:
		room.add_child(make_panel("WallAft", box_points(Vector3(-w, 0, z1), Vector3(w, h, z1 + SLAB)),
				trim_color(i), WALL))

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, h - 0.6, (z0 + z1) / 2.0)
	light.omni_range = 12.0
	light.light_energy = 1.6
	light.shadow_enabled = true
	room.add_child(light)
	return room


## A bulkhead at `z` with a doorway: two side panels and a lintel.
func _build_bulkhead(bulkhead_name: String, z: float) -> Node3D:
	var bulkhead := Node3D.new()
	bulkhead.name = bulkhead_name
	var half := SLAB / 2.0
	var d := DOOR_HALF_WIDTH
	bulkhead.add_child(make_panel("Left", box_points(Vector3(-HALF_WIDTH, 0, z - half), Vector3(-d, HEIGHT, z + half)),
			BULKHEAD_COLOR, WALL))
	bulkhead.add_child(make_panel("Right", box_points(Vector3(d, 0, z - half), Vector3(HALF_WIDTH, HEIGHT, z + half)),
			BULKHEAD_COLOR, WALL))
	bulkhead.add_child(make_panel("Lintel", box_points(Vector3(-d, DOOR_HEIGHT, z - half), Vector3(d, HEIGHT, z + half)),
			BULKHEAD_COLOR, WALL))
	return bulkhead


## Two 1 m crates on the Hold floor.
func _build_crates() -> Node3D:
	var crates := Node3D.new()
	crates.name = "Crates"
	for x in [-2.5, 2.5]:
		var at := Transform3D(Basis.IDENTITY, Vector3(x, 0.5, 9))
		crates.add_child(make_crate("Crate%d" % crates.get_child_count(), 1.0, at))
	return crates
