class_name WheelShip
extends Ship
## Three rings (Ring0..Ring2) side by side along X, around a zero-g hub, joined by nine ladder spokes
## (Spoke<ring>_<section>) that drop from each ring's floor to the hub's. The hub has no gravity; the rings have.
## Each spoke is a ring segment through the ring's ceiling, a shaft, and a collar poking into the hub.

const RING_CENTERS := [-24.0, 0.0, 24.0]
## The ring and hub sections that spokes leave from.
const SPOKE_SECTIONS := [2, 6, 10]
## Spoke axis offset across, from each ring's center.
const SPOKE_X := 2.5
const HUB_CORNER_RADIUS := 10.0
const HUB_HALF_LENGTH := 30.0
const DOOR_HEIGHT := 2.6
## Collar length inside the hub, along the spoke.
const COLLAR := 3.0
const CRATES_PER_SECTION := 2
const SLAB := RingGeometry.SLAB_THICKNESS
## Hue shift between neighboring rings.
const RING_HUE_STEP := 0.03
const SPOKE_COLOR := Color(0.55, 0.57, 0.62)
const HUB_ROOM := "Hub"
## Each spoke has a light in the hub on its axis, this far past the collar's cap.
const HUB_LIGHT_BEYOND_COLLAR := 1.0
const HUB_LIGHT_RANGE := 16.0
## Where the end caps' wedges start, so they close the hub without a degenerate point on the axis.
const CAP_INNER_RADIUS := 0.01
## How far the ladder starts above the floor, and how far its exits stand off the pipe's wall.
const FOOT_LIFT := 0.05
const EXIT_GAP := 0.7

var _rings: Array[RingHull] = []
var _hub := RingHull.new()
## [room name, transform from the world into the spoke's frame], per spoke.
var _spoke_shafts := []


func _ready() -> void:
	_build_rings()
	_build_hub()
	_build_end_cap("HubCapFore", -HUB_HALF_LENGTH - SLAB, -HUB_HALF_LENGTH, Vector3.LEFT)
	_build_end_cap("HubCapAft", HUB_HALF_LENGTH, HUB_HALF_LENGTH + SLAB, Vector3.RIGHT)
	for ring in RING_CENTERS.size():
		for k: int in SPOKE_SECTIONS:
			_build_spoke(ring, k)


func up_at(p: Vector3) -> Vector3:
	return RingGeometry.up_at(p)


func camera_roll_at(p: Vector3) -> float:
	return RingGeometry.angle_of(p)


## Everywhere but the hub.
func has_gravity_at(p: Vector3) -> bool:
	return room_at(p) != HUB_ROOM


## The middle ring's section 0 floor.
func spawn_point() -> Vector3:
	return RingGeometry.section_down(0) * (RingGeometry.floor_apothem() - 0.05)


## A spoke's room inside its shaft, "Hub" inside the hub, else the ring room, or "".
func room_at(p: Vector3) -> String:
	for shaft in _spoke_shafts:
		var local: Vector3 = shaft[1] * p
		if absf(local.x) < PIPE_INNER and absf(local.z) < PIPE_INNER and local.y >= 0.0 and local.y <= spoke_length() + COLLAR:
			return shaft[0]
	if Vector2(p.y, p.z).length() < hub_floor_apothem() + SLAB and absf(p.x) <= HUB_HALF_LENGTH + SLAB:
		return HUB_ROOM
	for hull in _rings:
		var room := hull.room_at(p)
		if room != "":
			return room
	return ""


## Every ring wholly on the camera's side (+X) of `p`, with its spokes: they would cover the view of the player.
func cutaway_nodes(p: Vector3) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for ring in RING_CENTERS.size():
		if RING_CENTERS[ring] - RingGeometry.HALF_WIDTH - SLAB > p.x:
			nodes.append(get_node("Ring%d" % ring))
			for k: int in SPOKE_SECTIONS:
				nodes.append(get_node("Spoke%d_%d" % [ring, k]))
	return nodes


static func hub_floor_apothem() -> float:
	return HUB_CORNER_RADIUS * cos(RingGeometry.HALF_ANGLE)


## How far a spoke runs from a ring's floor to the hub's.
static func spoke_length() -> float:
	return RingGeometry.floor_apothem() - hub_floor_apothem()


## The frame of the spoke on ring `ring` at section `k`: origin on the ring's floor, +Y toward the axis, the doorway toward −Z.
static func spoke_frame(ring: int, k: int) -> Transform3D:
	var down := RingGeometry.section_down(k)
	var origin := Vector3(RING_CENTERS[ring] + SPOKE_X, 0, 0) + down * RingGeometry.floor_apothem()
	return Transform3D(Basis(Vector3.RIGHT, -down, Vector3.RIGHT.cross(-down)), origin)


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


## The hub: a ceilingless hull whose floors, which face the axis, fade like walls. Its floor panels bound the room "Hub".
func _build_hub() -> void:
	_hub.floor_corner_radius = HUB_CORNER_RADIUS
	_hub.half_width = HUB_HALF_LENGTH
	_hub.ceiling_height = 0.0
	_hub.walls = false
	_hub.lights = false
	_hub.room_prefix = "HubPanels/"
	_hub.floor_layers = WORLD_LAYER | FLOOR_LAYER | OCCLUDER_LAYER
	for k: int in SPOKE_SECTIONS:
		for center: float in RING_CENTERS:
			_hub.add_floor_hole(k, center + SPOKE_X, PIPE_OUTER)
	var node := Node3D.new()
	node.name = "Hub"
	add_child(node)
	_hub.build(self, node)
	for k in RingGeometry.SECTIONS:
		var section := node.get_node("Section%d" % k)
		for panel in section.get_children():
			if panel.name.begins_with("Floor"):
				add_room_bound(HUB_ROOM, panel, RingGeometry.section_down(k))


## One wedge per section closing the hub from x0 to x1, a bound of "Hub" facing `outward`.
func _build_end_cap(cap_name: String, x0: float, x1: float, outward: Vector3) -> void:
	var cap := Node3D.new()
	cap.name = cap_name
	add_child(cap)
	for k in RingGeometry.SECTIONS:
		var points := _hub.slab_points(k, x0, x1, CAP_INNER_RADIUS, _hub.floor_apothem())
		var panel := make_panel("Cap%d" % k, points, trim_color(k, RingGeometry.SECTIONS), WORLD_LAYER | OCCLUDER_LAYER)
		cap.add_child(panel)
		add_room_bound(HUB_ROOM, panel, outward)


func _build_spoke(ring: int, k: int) -> void:
	var spoke := Node3D.new()
	spoke.name = "Spoke%d_%d" % [ring, k]
	add_child(spoke)
	var frame := spoke_frame(ring, k)
	var length := spoke_length()
	var ring_top := _rings[ring].ceiling_height + SLAB
	var segments := [
		["RingSeg", 0.0, ring_top, DOOR_HEIGHT, false],
		["Shaft", ring_top, length, 0.0, false],
		["Collar", length, length + COLLAR, DOOR_HEIGHT, true],
	]
	for segment in segments:
		var node := Node3D.new()
		node.name = segment[0]
		spoke.add_child(node)
		add_pipe_segment(node, frame, segment[1], segment[2], segment[3], segment[4], SPOKE_COLOR, spoke.name)
	add_rungs(frame, FOOT_LIFT, length + FOOT_LIFT, func(_s: float) -> Node3D: return spoke)
	var light := make_light(frame * Vector3(0, length + COLLAR + HUB_LIGHT_BEYOND_COLLAR, 0), HUB_LIGHT_RANGE)
	light.name = "SpokeLight%d_%d" % [ring, k]
	light.shadow_enabled = false
	get_node("Hub").add_child(light)
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
