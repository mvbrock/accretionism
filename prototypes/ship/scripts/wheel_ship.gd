class_name WheelShip
extends Ship
## Three rings (Ring0..Ring2) side by side along X, each with a square zero-g hub room (Hub0..Hub2) on the spin axis.
## Neighbouring rooms share a bulkhead with a full-height doorway; the two outer ends are solid.
## Each ring has two ladder spokes (Spoke<ring>_<section>), straight down and straight up, that run from the ring's floor
## to the room's floor or ceiling and end flush with it. The hub rooms have no gravity; the rings have.

const RING_CENTERS := [-24.0, 0.0, 24.0]
## The ring sections that spokes leave from: straight down to the room's floor, straight up to its ceiling.
const SPOKE_SECTIONS := [0, 6]
## Spoke axis offset across, from each ring's center.
const SPOKE_X := 2.5
## Each hub room is this long along X, the ring spacing, so neighbours share a bulkhead.
const ROOM_LENGTH := 24.0
## Hub rooms span y and z from -HUB_HALF_SIZE to +HUB_HALF_SIZE.
const HUB_HALF_SIZE := 6.0
## Bulkhead doorways span z from -DOOR_HALF_WIDTH to +DOOR_HALF_WIDTH, full height.
const DOOR_HALF_WIDTH := 1.2
const DOOR_HEIGHT := 2.6
const CRATES_PER_SECTION := 2
const SLAB := RingGeometry.SLAB_THICKNESS
## Hue shift between neighboring rings.
const RING_HUE_STEP := 0.03
const SPOKE_COLOR := Color(0.55, 0.57, 0.62)
const BULKHEAD_COLOR := Color(0.5, 0.5, 0.52)
const HUB_LIGHT_RANGE := 16.0
## How far the ladder starts above the floor, and how far its exits stand off the pipe's wall.
const FOOT_LIFT := 0.05
const EXIT_GAP := 0.7
## A hub room's floor, ceiling and side walls: with "up" toward the axis, any of them can be the floor a floating player holds its height over.
const HUB_PANEL_LAYERS := WORLD_LAYER | FLOOR_LAYER | OCCLUDER_LAYER
## Bulkheads and end walls.
const WALL_LAYERS := WORLD_LAYER | OCCLUDER_LAYER

var _rings: Array[RingHull] = []
## [room name, transform from the world into the spoke's frame], per spoke.
var _spoke_shafts := []


func _ready() -> void:
	_build_rings()
	for i in RING_CENTERS.size():
		_build_hub_room(i)
	_build_hub_ends()
	for i in range(1, RING_CENTERS.size()):
		_build_bulkhead(i)
	for ring in RING_CENTERS.size():
		for k: int in SPOKE_SECTIONS:
			_build_spoke(ring, k)


## The ladder of the spoke on ring `ring` at section `k`, one of SPOKE_SECTIONS.
func spoke_ladder(ring: int, k: int) -> Ladder:
	return ladders[ring * SPOKE_SECTIONS.size() + SPOKE_SECTIONS.find(k)]


func up_at(p: Vector3) -> Vector3:
	return RingGeometry.up_at(p)


func camera_roll_at(p: Vector3) -> float:
	return RingGeometry.angle_of(p)


## Everywhere but the hub rooms.
func has_gravity_at(p: Vector3) -> bool:
	return not room_at(p).begins_with("Hub")


## The middle ring's section 0 floor.
func spawn_point() -> Vector3:
	return RingGeometry.section_down(0) * (RingGeometry.floor_apothem() - 0.05)


## A spoke's room inside its shaft, "Hub<i>" inside a hub room, else the ring room, or "".
func room_at(p: Vector3) -> String:
	for shaft in _spoke_shafts:
		var local: Vector3 = shaft[1] * p
		if absf(local.x) < PIPE_INNER and absf(local.z) < PIPE_INNER and local.y >= 0.0 and local.y <= spoke_length():
			return shaft[0]
	var hub := _hub_index_at(p)
	if hub != -1:
		return _hub_name(hub)
	for hull in _rings:
		var room := hull.room_at(p)
		if room != "":
			return room
	return ""


## Every ring, with its spokes, every hub room, and every bulkhead and the aft end wall wholly on the camera's side (+X) of `p`:
## they would cover the view of the player. A player in a hub room keeps that room's own +X bulkhead, which fades as the room's bound.
func cutaway_nodes(p: Vector3) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var hub := _hub_index_at(p)
	var boundary := p.x if hub == -1 else _room_max_x(hub)
	for i in range(1, RING_CENTERS.size()):
		if _room_max_x(i - 1) > boundary:
			nodes.append(get_node("Bulkhead%d" % i))
	if _room_max_x(RING_CENTERS.size() - 1) > boundary:
		nodes.append(get_node("HubEndAft"))
	for ring in RING_CENTERS.size():
		if RING_CENTERS[ring] - RingGeometry.HALF_WIDTH - SLAB > p.x:
			nodes.append(get_node("Ring%d" % ring))
			for k: int in SPOKE_SECTIONS:
				nodes.append(get_node("Spoke%d_%d" % [ring, k]))
		if RING_CENTERS[ring] - ROOM_LENGTH / 2.0 > p.x:
			nodes.append(get_node(_hub_name(ring)))
	return nodes


## How far a spoke runs from a ring's floor to the hub room's floor or ceiling.
static func spoke_length() -> float:
	return RingGeometry.floor_apothem() - HUB_HALF_SIZE


## The frame of the spoke on ring `ring` at section `k`: origin on the ring's floor, +Y toward the axis, the doorway toward −Z.
static func spoke_frame(ring: int, k: int) -> Transform3D:
	var down := RingGeometry.section_down(k)
	var origin := Vector3(RING_CENTERS[ring] + SPOKE_X, 0, 0) + down * RingGeometry.floor_apothem()
	return Transform3D(Basis(Vector3.RIGHT, -down, Vector3.RIGHT.cross(-down)), origin)


static func _hub_name(i: int) -> String:
	return "Hub%d" % i


static func _room_max_x(i: int) -> float:
	return RING_CENTERS[i] + ROOM_LENGTH / 2.0


## The index of the hub room containing `p`, or -1.
func _hub_index_at(p: Vector3) -> int:
	if absf(p.y) > HUB_HALF_SIZE + SLAB or absf(p.z) > HUB_HALF_SIZE + SLAB:
		return -1
	for i in RING_CENTERS.size():
		if absf(p.x - RING_CENTERS[i]) <= ROOM_LENGTH / 2.0:
			return i
	return -1


func _build_rings() -> void:
	for i in RING_CENTERS.size():
		var hull := RingHull.new()
		hull.center_x = RING_CENTERS[i]
		hull.room_prefix = "Ring%d/" % i
		hull.crates_per_section = CRATES_PER_SECTION
		hull.hue_offset = i * RING_HUE_STEP
		for k: int in SPOKE_SECTIONS:
			hull.add_ceiling_hole(k, RING_CENTERS[i] + SPOKE_X, PIPE_OUTER)
		var node := Node3D.new()
		node.name = "Ring%d" % i
		add_child(node)
		hull.build(self, node)
		_rings.append(hull)


## Hub room `i`: a floor and a ceiling, each with a hole where its ring's spoke arrives, two side walls and a light.
## The panels bound the room "Hub<i>". The two ends are the bulkheads, or the end walls.
func _build_hub_room(i: int) -> void:
	var room := Node3D.new()
	room.name = _hub_name(i)
	add_child(room)
	var x0: float = RING_CENTERS[i] - ROOM_LENGTH / 2.0
	var x1: float = RING_CENTERS[i] + ROOM_LENGTH / 2.0
	var h := HUB_HALF_SIZE
	var spoke_hole := Vector2(RING_CENTERS[i] + SPOKE_X, 0)
	var fill := room_color(i, RING_CENTERS.size())
	var trim := trim_color(i, RING_CENTERS.size())
	# [panel name, lo, hi, outward, color]
	var slabs := [
		["Floor", Vector3(x0, -h - SLAB, -h - SLAB), Vector3(x1, -h, h + SLAB), Vector3.DOWN, fill],
		["Ceiling", Vector3(x0, h, -h - SLAB), Vector3(x1, h + SLAB, h + SLAB), Vector3.UP, trim],
	]
	for slab in slabs:
		for panel in add_holed_slab(room, slab[0], slab[1], slab[2], spoke_hole, PIPE_OUTER, slab[4], HUB_PANEL_LAYERS):
			add_room_bound(room.name, panel, slab[3])
	var walls := [
		["WallLeft", Vector3(x0, -h, -h - SLAB), Vector3(x1, h, -h), Vector3.FORWARD],
		["WallRight", Vector3(x0, -h, h), Vector3(x1, h, h + SLAB), Vector3.BACK],
	]
	for wall in walls:
		var panel := make_panel(wall[0], box_points(wall[1], wall[2]), trim, HUB_PANEL_LAYERS)
		room.add_child(panel)
		add_room_bound(room.name, panel, wall[3])
	room.add_child(make_light(Vector3(RING_CENTERS[i], 0, 0), HUB_LIGHT_RANGE))


## The solid walls closing the row of rooms at both ends.
func _build_hub_ends() -> void:
	var h := HUB_HALF_SIZE + SLAB
	var fore_x: float = RING_CENTERS[0] - ROOM_LENGTH / 2.0
	var aft_x: float = RING_CENTERS[-1] + ROOM_LENGTH / 2.0
	# [panel name, x0, x1, room, outward]
	var ends := [
		["HubEndFore", fore_x - SLAB, fore_x, _hub_name(0), Vector3.LEFT],
		["HubEndAft", aft_x, aft_x + SLAB, _hub_name(RING_CENTERS.size() - 1), Vector3.RIGHT],
	]
	for end in ends:
		var panel := make_panel(end[0], box_points(Vector3(end[1], -h, -h), Vector3(end[2], h, h)), BULKHEAD_COLOR, WALL_LAYERS)
		add_child(panel)
		add_room_bound(end[3], panel, end[4])


## The bulkhead between hub rooms `i - 1` and `i`: a left and a right piece around a full-height doorway, each bounding both rooms.
func _build_bulkhead(i: int) -> void:
	var bulkhead := Node3D.new()
	bulkhead.name = "Bulkhead%d" % i
	add_child(bulkhead)
	var x: float = (RING_CENTERS[i - 1] + RING_CENTERS[i]) / 2.0
	var h := HUB_HALF_SIZE
	var d := DOOR_HALF_WIDTH
	var half := SLAB / 2.0
	# [panel name, z0, z1]
	var pieces := [["Left", -h, -d], ["Right", d, h]]
	for piece in pieces:
		var panel := make_panel(piece[0], box_points(Vector3(x - half, -h, piece[1]), Vector3(x + half, h, piece[2])),
				BULKHEAD_COLOR, WALL_LAYERS)
		bulkhead.add_child(panel)
		add_room_bound(_hub_name(i - 1), panel, Vector3.RIGHT)
		add_room_bound(_hub_name(i), panel, Vector3.LEFT)


## A spoke: a ring segment with a doorway, then a shaft up to the hub room's floor or ceiling.
func _build_spoke(ring: int, k: int) -> void:
	var spoke := Node3D.new()
	spoke.name = "Spoke%d_%d" % [ring, k]
	add_child(spoke)
	var frame := spoke_frame(ring, k)
	var length := spoke_length()
	var ring_top := RingGeometry.CEILING_HEIGHT + SLAB
	var segments := [
		["RingSeg", 0.0, ring_top, DOOR_HEIGHT],
		["Shaft", ring_top, length, 0.0],
	]
	for segment in segments:
		var node := Node3D.new()
		node.name = segment[0]
		spoke.add_child(node)
		add_pipe_segment(node, frame, segment[1], segment[2], segment[3], false, SPOKE_COLOR, spoke.name)
	add_rungs(frame, FOOT_LIFT, length + FOOT_LIFT, func(_s: float) -> Node3D: return spoke)
	_spoke_shafts.append([spoke.name, frame.affine_inverse()])
	ladders.append(_build_ladder(frame, length))


## The ladder up a spoke, with a landing at each end standing off the doorway side.
func _build_ladder(frame: Transform3D, length: float) -> Ladder:
	var up := frame.basis.y
	var ladder := Ladder.new(frame.origin + up * FOOT_LIFT, up, length)
	var stand_off := frame.basis * Vector3(0, 0, -(PIPE_OUTER + EXIT_GAP))
	for s in [0.0, length]:
		ladder.add_landing(s, ladder.point_at(s) + stand_off, frame.basis.z)
	return ladder
