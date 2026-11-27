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
	for i in ROOMS.size() - 1:
		_bound_rooms_by_bulkhead(get_node("Bulkhead%d" % (i + 1)), ROOMS[i][0], ROOMS[i + 1][0])
	add_child(_build_crates())


func has_gravity() -> bool:
	return false


## The middle of the Cabin floor.
func spawn_point() -> Vector3:
	return Vector3(0, 0.05, -1.0)


## The name of the room whose z range holds `p.z`, or "".
func room_at(p: Vector3) -> String:
	for room in ROOMS:
		if p.z >= room[1] and p.z <= room[2]:
			return room[0]
	return ""


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
	add_room_bound(room.name, room.get_node("Ceiling"), Vector3.UP)
	add_room_bound(room.name, room.get_node("WallLeft"), Vector3.LEFT)
	add_room_bound(room.name, room.get_node("WallRight"), Vector3.RIGHT)
	if i == 0:
		room.add_child(make_panel("WallFore", box_points(Vector3(-w, 0, z0 - SLAB), Vector3(w, h, z0)),
				trim_color(i), WALL))
		add_room_bound(room.name, room.get_node("WallFore"), Vector3.FORWARD)
	if i == ROOMS.size() - 1:
		room.add_child(make_panel("WallAft", box_points(Vector3(-w, 0, z1), Vector3(w, h, z1 + SLAB)),
				trim_color(i), WALL))
		add_room_bound(room.name, room.get_node("WallAft"), Vector3.BACK)

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


## Registers each piece of `bulkhead` as bounding the room in front of it (lower z) and the room behind it.
func _bound_rooms_by_bulkhead(bulkhead: Node, front_room: String, back_room: String) -> void:
	for piece in bulkhead.get_children():
		add_room_bound(front_room, piece, Vector3.BACK)
		add_room_bound(back_room, piece, Vector3.FORWARD)


## Two 1 m crates on the Hold floor.
func _build_crates() -> Node3D:
	var crates := Node3D.new()
	crates.name = "Crates"
	for x in [-2.5, 2.5]:
		var at := Transform3D(Basis.IDENTITY, Vector3(x, 0.5, 9))
		crates.add_child(make_crate("Crate%d" % crates.get_child_count(), 1.0, at))
	return crates
