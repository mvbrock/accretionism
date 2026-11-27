class_name WheelShip
extends Ship
## Three rings (Ring0..Ring2) side by side along X, each with a small square zero-g hub room (Hub0..Hub2) on the spin axis.
## Neighbouring rooms share a bulkhead with a doorway at floor level, off the centre line; the two outer ends are solid.
## Each ring has one ladder pipe (Spoke<ring>) from the ring's bottom floor, up through the hub room's floor and ceiling,
## to the ring's top floor. The hub rooms do not rotate: up is +Y there, and only the floor is a floor. In the top
## half of the pipe up points at the axis, so a climber hangs upside down and the camera turns over to match the top
## ring. The hub rooms have no gravity; the rings have.

const RING_CENTERS := [-24.0, 0.0, 24.0]
## Each ring's ladder offset across, from the ring's center; it sits at z = 0.
const LADDER_X := 2.5
## Each hub room is this long along X, the ring spacing, so neighbours share a bulkhead.
const ROOM_LENGTH := 24.0
## Hub rooms span y and z from -HUB_HALF_SIZE to +HUB_HALF_SIZE.
const HUB_HALF_SIZE := 4.0
## Doorways between hub rooms span z across DOOR_Z, from the floor up DOOR_HEIGHT.
const DOOR_Z := Vector2(1.4, 3.6)
const DOOR_HEIGHT := 3.2
## The pipe's doorways, each filled by a hatch blocker.
const PIPE_DOOR_HEIGHT := 2.6
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
## The ring sections the ladder runs between: the bottom floor and the top floor.
const BOTTOM_SECTION := 0
const TOP_SECTION := 6
## Hub ceilings and side walls, bulkheads and end walls.
const WALL_LAYERS := WORLD_LAYER | OCCLUDER_LAYER

var _rings: Array[RingHull] = []


func _ready() -> void:
	_build_rings()
	for i in RING_CENTERS.size():
		_build_hub_room(i)
	_build_hub_ends()
	for i in range(1, RING_CENTERS.size()):
		_build_bulkhead(i)
	for ring in RING_CENTERS.size():
		_build_spoke(ring)


## The ladder of ring `ring`, from its bottom floor to its top floor.
func ring_ladder(ring: int) -> Ladder:
	return ladders[ring]


## +Y in a hub room's box, pipe included; toward the spin axis everywhere else.
func up_at(p: Vector3) -> Vector3:
	if _hub_index_at(p) != -1:
		return Vector3.UP
	return RingGeometry.up_at(p)


## 0 in the hub box and the bottom half of a ladder pipe; PI * t in the top half, where t runs from 0 one body
## height above the hub ceiling's outer face to 1 at the top ring's floor; the player's angle around the axis in the
## rings. A climber flipping at the hub ceiling moves its feet up by a body height, so the turn starts where its feet
## land and the camera doesn't jump at the flip.
func camera_roll_at(p: Vector3) -> float:
	if _hub_index_at(p) != -1:
		return 0.0
	if _spoke_at(p) != -1:
		var turn_start := HUB_HALF_SIZE + SLAB + Player.BODY_HEIGHT
		var turn_end := RingGeometry.floor_apothem() - FOOT_LIFT
		return PI * clampf((p.y - turn_start) / (turn_end - turn_start), 0.0, 1.0)
	return RingGeometry.angle_of(p)


## Everywhere but the hub rooms.
func has_gravity_at(p: Vector3) -> bool:
	return not room_at(p).begins_with("Hub")


## The middle ring's section 0 floor.
func spawn_point() -> Vector3:
	return RingGeometry.section_down(BOTTOM_SECTION) * (RingGeometry.floor_apothem() - 0.05)


## "Spoke<ring>" inside a ladder pipe, "Hub<i>" inside a hub room, else the ring room, or "".
func room_at(p: Vector3) -> String:
	var spoke := _spoke_at(p)
	if spoke != -1:
		return _spoke_name(spoke)
	var hub := _hub_index_at(p)
	if hub != -1:
		return _hub_name(hub)
	for hull in _rings:
		var room := hull.room_at(p)
		if room != "":
			return room
	return ""


## Everything in the ring slices on the camera's side (+X) of the player's slice: those rings with their ladder pipes
## and hub rooms, the bulkheads between them and the aft end wall. They would cover the view of the player. The
## player's own slice is never cut, so its ring, ladder and hub room stay wherever in the slice the player is.
func cutaway_nodes(p: Vector3) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var here := _slice_at(p)
	for i in range(here + 1, RING_CENTERS.size()):
		nodes.append(get_node("Ring%d" % i))
		nodes.append(get_node(_spoke_name(i)))
		nodes.append(get_node(_hub_name(i)))
	# Bulkhead j stands between hub rooms j - 1 and j; the one at the far side of the player's own room stays (it fades).
	for j in range(here + 2, RING_CENTERS.size()):
		nodes.append(get_node("Bulkhead%d" % j))
	if here < RING_CENTERS.size() - 1:
		nodes.append(get_node("HubEndAft"))
	return nodes


## Which ring's slice of the ship `p` is in: the span of that ring's hub room along X, clamped to the ship.
static func _slice_at(p: Vector3) -> int:
	var first_edge: float = RING_CENTERS[0] - ROOM_LENGTH / 2.0
	return clampi(floori((p.x - first_edge) / ROOM_LENGTH), 0, RING_CENTERS.size() - 1)


## The frame of ring `ring`'s ladder pipe from the bottom: origin on the ring's floor, +Y up the pipe, the doorway toward −Z.
static func ladder_frame(ring: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(RING_CENTERS[ring] + LADDER_X, -RingGeometry.floor_apothem(), 0))


## The frame of the pipe's top end: origin on the top ring's floor, +Y down the pipe, the doorway toward −Z.
static func top_frame(ring: int) -> Transform3D:
	var basis := Basis(Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1))
	return Transform3D(basis, Vector3(RING_CENTERS[ring] + LADDER_X, RingGeometry.floor_apothem(), 0))


## How far a ladder runs: from 5 cm above the bottom floor to where an inverted climber's feet reach 5 cm off the top
## floor, which puts its head BODY_HEIGHT short of that.
static func ladder_length() -> float:
	return 2.0 * RingGeometry.floor_apothem() - 2.0 * FOOT_LIFT - Player.BODY_HEIGHT


static func _hub_name(i: int) -> String:
	return "Hub%d" % i


static func _spoke_name(ring: int) -> String:
	return "Spoke%d" % ring


## The index of the hub room box containing `p` (the room and its slabs), or -1.
func _hub_index_at(p: Vector3) -> int:
	if absf(p.y) > HUB_HALF_SIZE + SLAB or absf(p.z) > HUB_HALF_SIZE + SLAB:
		return -1
	for i in RING_CENTERS.size():
		if absf(p.x - RING_CENTERS[i]) <= ROOM_LENGTH / 2.0:
			return i
	return -1


## The ring whose ladder pipe's inside contains `p`, from ring floor to ring floor, or -1.
func _spoke_at(p: Vector3) -> int:
	if absf(p.z) >= PIPE_INNER or absf(p.y) > RingGeometry.floor_apothem():
		return -1
	for i in RING_CENTERS.size():
		if absf(p.x - RING_CENTERS[i] - LADDER_X) < PIPE_INNER:
			return i
	return -1


func _build_rings() -> void:
	for i in RING_CENTERS.size():
		var hull := RingHull.new()
		hull.center_x = RING_CENTERS[i]
		hull.room_prefix = "Ring%d/" % i
		hull.crates_per_section = CRATES_PER_SECTION
		hull.hue_offset = i * RING_HUE_STEP
		for k in [BOTTOM_SECTION, TOP_SECTION]:
			hull.add_ceiling_hole(k, RING_CENTERS[i] + LADDER_X, PIPE_OUTER)
		var node := Node3D.new()
		node.name = "Ring%d" % i
		add_child(node)
		hull.build(self, node)
		_rings.append(hull)


## Hub room `i`: a holed floor and ceiling where its ring's ladder passes, two side walls and a light.
## The ceiling and the walls bound the room "Hub<i>"; the floor does not, as it is what a floating player holds its height
## over. The two ends are the bulkheads, or the end walls.
func _build_hub_room(i: int) -> void:
	var room := Node3D.new()
	room.name = _hub_name(i)
	add_child(room)
	var x0: float = RING_CENTERS[i] - ROOM_LENGTH / 2.0
	var x1: float = RING_CENTERS[i] + ROOM_LENGTH / 2.0
	var h := HUB_HALF_SIZE
	var hole := Vector2(RING_CENTERS[i] + LADDER_X, 0)
	var fill := room_color(i, RING_CENTERS.size())
	var trim := trim_color(i, RING_CENTERS.size())
	# The floor is an occluder too, so it fades for a climber below it in the bottom spoke.
	add_holed_slab(room, "Floor", Vector3(x0, -h - SLAB, -h - SLAB), Vector3(x1, -h, h + SLAB), hole, PIPE_OUTER, fill,
			WORLD_LAYER | FLOOR_LAYER | OCCLUDER_LAYER)
	for panel in add_holed_slab(room, "Ceiling", Vector3(x0, h, -h - SLAB), Vector3(x1, h + SLAB, h + SLAB), hole, PIPE_OUTER,
			trim, WALL_LAYERS):
		add_room_bound(room.name, panel, Vector3.UP)
	var walls := [
		["WallLeft", Vector3(x0, -h, -h - SLAB), Vector3(x1, h, -h), Vector3.FORWARD],
		["WallRight", Vector3(x0, -h, h), Vector3(x1, h, h + SLAB), Vector3.BACK],
	]
	for wall in walls:
		var panel := make_panel(wall[0], box_points(wall[1], wall[2]), trim, WALL_LAYERS)
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


## The bulkhead between hub rooms `i - 1` and `i`: a left and a right piece around a doorway at floor level, and a lintel
## over it, each bounding both rooms.
func _build_bulkhead(i: int) -> void:
	var bulkhead := Node3D.new()
	bulkhead.name = "Bulkhead%d" % i
	add_child(bulkhead)
	var x: float = (RING_CENTERS[i - 1] + RING_CENTERS[i]) / 2.0
	var h := HUB_HALF_SIZE
	var half := SLAB / 2.0
	var door_top := -h + DOOR_HEIGHT
	# [panel name, lo (y, z), hi (y, z)]
	var pieces := [
		["Left", Vector2(-h, -h), Vector2(h, DOOR_Z.x)],
		["Right", Vector2(-h, DOOR_Z.y), Vector2(h, h)],
		["Lintel", Vector2(door_top, DOOR_Z.x), Vector2(h, DOOR_Z.y)],
	]
	for piece in pieces:
		var lo := Vector3(x - half, piece[1].x, piece[1].y)
		var hi := Vector3(x + half, piece[2].x, piece[2].y)
		var panel := make_panel(piece[0], box_points(lo, hi), BULKHEAD_COLOR, WALL_LAYERS)
		bulkhead.add_child(panel)
		add_room_bound(_hub_name(i - 1), panel, Vector3.RIGHT)
		add_room_bound(_hub_name(i), panel, Vector3.LEFT)


## Ring `ring`'s ladder pipe, in five segments: the bottom ring's (doorway at the floor, through the ceiling slab), the
## shaft up to the hub floor, the hub's (doorway at the hub floor, through the hub's ceiling slab), the shaft on to the top
## ring, and the top ring's (doorway at the top floor). The rungs run the whole ladder on the +Z wall.
func _build_spoke(ring: int) -> void:
	var spoke := Node3D.new()
	spoke.name = _spoke_name(ring)
	add_child(spoke)
	var frame := ladder_frame(ring)
	var apothem := RingGeometry.floor_apothem()
	var ring_top := RingGeometry.CEILING_HEIGHT + SLAB
	var hub_floor := apothem - HUB_HALF_SIZE
	var hub_top := apothem + HUB_HALF_SIZE + SLAB
	var top_ring_bottom := 2.0 * apothem - ring_top
	var segments := [
		["BottomRingSeg", frame, 0.0, ring_top, PIPE_DOOR_HEIGHT],
		["BottomShaft", frame, ring_top, hub_floor, 0.0],
		["HubSeg", frame, hub_floor, hub_top, PIPE_DOOR_HEIGHT],
		["TopShaft", frame, hub_top, top_ring_bottom, 0.0],
		["TopRingSeg", top_frame(ring), 0.0, ring_top, PIPE_DOOR_HEIGHT],
	]
	for segment in segments:
		var node := Node3D.new()
		node.name = segment[0]
		spoke.add_child(node)
		add_pipe_segment(node, segment[1], segment[2], segment[3], segment[4], false, SPOKE_COLOR, spoke.name)
	var length := ladder_length()
	add_rungs(frame, FOOT_LIFT, length + FOOT_LIFT, func(_s: float) -> Node3D: return spoke)
	ladders.append(_build_ladder(frame, length, hub_floor))


## The ladder up a pipe, with a landing at the bottom ring, the hub floor and the top ring, each standing off the doorway
## side. The top landing's exit is where an inverted climber's feet stand on the top ring's floor.
func _build_ladder(frame: Transform3D, length: float, hub_floor: float) -> Ladder:
	var ladder := Ladder.new(frame.origin + Vector3.UP * FOOT_LIFT, Vector3.UP, length)
	var stand_off := Vector3(0, 0, -(PIPE_OUTER + EXIT_GAP))
	ladder.add_landing(0.0, ladder.point_at(0.0) + stand_off, Vector3.BACK)
	ladder.add_landing(hub_floor, ladder.point_at(hub_floor) + stand_off, Vector3.BACK)
	ladder.add_landing(length, ladder.point_at(length) + Vector3.UP * Player.BODY_HEIGHT + stand_off, Vector3.BACK)
	return ladder
