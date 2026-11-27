class_name DeckShip
extends Ship
## Square decks stacked along +Y under thrust, joined by one ladder pipe in the corner.
## Deck i's floor top is at y = i * PITCH; "across" is world X.

@export var deck_count := 2

const HALF := 6.0
const HEIGHT := 4.0
const SLAB := 0.4
const PITCH := HEIGHT + SLAB
## (x, z) of the pipe's axis.
const PIPE_CENTER := Vector2(3.5, 3.5)
const PIPE_INNER := 0.7
const PIPE_WALL := 0.15
## The pipe's outer half-width.
const PIPE_OUTER := PIPE_INNER + PIPE_WALL
const DOOR_HEIGHT := 2.6
const RUNG_SPACING := 0.35
const RUNG_COLOR := Color(0.55, 0.55, 0.58)
const WALL := WORLD_LAYER | OCCLUDER_LAYER
const SOLID_FLOOR := WORLD_LAYER | FLOOR_LAYER | OCCLUDER_LAYER


func _ready() -> void:
	for i in deck_count:
		add_child(_build_deck(i))
	add_child(_build_pipe())
	ladders.append(_build_ladder())


func spawn_point() -> Vector3:
	return Vector3(-2, 0.05, -2)


## "Pipe" inside the shaft, otherwise the deck at height `p.y`.
func room_at(p: Vector3) -> String:
	if absf(p.x - PIPE_CENTER.x) < PIPE_INNER and absf(p.z - PIPE_CENTER.y) < PIPE_INNER:
		return "Pipe"
	return "Deck%d" % clampi(floori(p.y / PITCH), 0, deck_count - 1)




func _build_deck(i: int) -> Node3D:
	var deck := Node3D.new()
	deck.name = "Deck%d" % i
	var room := deck.name
	var base := i * PITCH
	var top := base + HEIGHT
	var floor_color := room_color(i, deck_count)
	var trim := trim_color(i, deck_count)
	var reach := HALF + SLAB

	if i == 0:
		deck.add_child(make_panel("Floor", box_points(Vector3(-reach, -SLAB, -reach), Vector3(reach, 0, reach)),
				floor_color, WORLD_LAYER | FLOOR_LAYER))
	else:
		# Deck i's floor is also deck i-1's ceiling.
		for piece in _add_slab(deck, "Slab%d" % (i - 1), base - SLAB, floor_color, SOLID_FLOOR):
			add_room_bound("Deck%d" % (i - 1), piece, Vector3.UP)

	deck.add_child(make_panel("WallLeft", box_points(Vector3(-reach, base, -reach), Vector3(-HALF, top, reach)), trim, WALL))
	deck.add_child(make_panel("WallRight", box_points(Vector3(HALF, base, -reach), Vector3(reach, top, reach)), trim, WALL))
	deck.add_child(make_panel("WallFore", box_points(Vector3(-HALF, base, -reach), Vector3(HALF, top, -HALF)), trim, WALL))
	deck.add_child(make_panel("WallAft", box_points(Vector3(-HALF, base, HALF), Vector3(HALF, top, reach)), trim, WALL))
	add_room_bound(room, deck.get_node("WallLeft"), Vector3.LEFT)
	add_room_bound(room, deck.get_node("WallRight"), Vector3.RIGHT)
	add_room_bound(room, deck.get_node("WallFore"), Vector3.FORWARD)
	add_room_bound(room, deck.get_node("WallAft"), Vector3.BACK)

	if i == deck_count - 1:
		deck.add_child(make_panel("Roof", box_points(Vector3(-reach, top, -reach), Vector3(reach, top + SLAB, reach)),
				trim, WALL))
		add_room_bound(room, deck.get_node("Roof"), Vector3.UP)

	deck.add_child(make_light(Vector3(0, top - 0.6, 0), 14.0))
	deck.add_child(make_crate("Crate0", 1.0, Transform3D(Basis.IDENTITY, Vector3(-4.5, base + 0.5, 3.5))))
	deck.add_child(make_crate("Crate1", 1.0, Transform3D(Basis.IDENTITY, Vector3(-3.5, base + 0.5, -4.5))))
	return deck


## Four panels `prefix`a to d from y = `y0` up `SLAB`, around a hole the size of the pipe's outer footprint.
func _add_slab(parent: Node3D, prefix: String, y0: float, color: Color, layers: int) -> Array[StaticBody3D]:
	var reach := HALF + SLAB
	var o := PIPE_OUTER
	var x0 := PIPE_CENTER.x - o
	var x1 := PIPE_CENTER.x + o
	var z0 := PIPE_CENTER.y - o
	var z1 := PIPE_CENTER.y + o
	var y1 := y0 + SLAB
	var boxes := [
		[Vector3(-reach, y0, -reach), Vector3(x0, y1, reach)],
		[Vector3(x1, y0, -reach), Vector3(reach, y1, reach)],
		[Vector3(x0, y0, -reach), Vector3(x1, y1, z0)],
		[Vector3(x0, y0, z1), Vector3(x1, y1, reach)],
	]
	var panels: Array[StaticBody3D] = []
	for k in boxes.size():
		var panel := make_panel("%s%s" % [prefix, "abcd"[k]], box_points(boxes[k][0], boxes[k][1]), color, layers)
		parent.add_child(panel)
		panels.append(panel)
	return panels


## The shaft walls on every deck, the doorway blockers and the rungs.
func _build_pipe() -> Node3D:
	var pipe := Node3D.new()
	pipe.name = "Pipe"
	var o := PIPE_OUTER
	var cx := PIPE_CENTER.x
	var cz := PIPE_CENTER.y
	for i in deck_count:
		var y0 := i * PITCH
		var y1 := y0 + (HEIGHT if i == deck_count - 1 else PITCH)
		var door_top := y0 + DOOR_HEIGHT
		var trim := trim_color(i, deck_count)
		# [name, lo, hi, outward]. The side walls span the -Z wall's corners, so it is only a lintel over the doorway.
		var pieces := [
			["Left%d" % i, Vector3(cx - o, y0, cz - o), Vector3(cx - PIPE_INNER, y1, cz + o), Vector3.LEFT],
			["Right%d" % i, Vector3(cx + PIPE_INNER, y0, cz - o), Vector3(cx + o, y1, cz + o), Vector3.RIGHT],
			["Aft%d" % i, Vector3(cx - PIPE_INNER, y0, cz + PIPE_INNER), Vector3(cx + PIPE_INNER, y1, cz + o), Vector3.BACK],
			["Lintel%d" % i, Vector3(cx - PIPE_INNER, door_top, cz - o), Vector3(cx + PIPE_INNER, y1, cz - PIPE_INNER), Vector3.FORWARD],
		]
		for piece in pieces:
			var panel := make_panel(piece[0], box_points(piece[1], piece[2]), trim, WALL)
			pipe.add_child(panel)
			add_room_bound("Pipe", panel, piece[3])
		pipe.add_child(_build_hatch(i, y0, door_top))
	var rungs := int(floor(_ladder_length() / RUNG_SPACING)) + 1
	var rung_material := StandardMaterial3D.new()
	rung_material.albedo_color = RUNG_COLOR
	for k in rungs:
		var rung := MeshInstance3D.new()
		rung.name = "Rung%d" % k
		var box := BoxMesh.new()
		box.size = Vector3(2.0 * PIPE_INNER - 0.2, 0.04, 0.04)
		rung.mesh = box
		rung.material_override = rung_material
		rung.position = Vector3(cx, 0.05 + k * RUNG_SPACING, cz + PIPE_INNER - 0.06)
		pipe.add_child(rung)
	return pipe


## An invisible blocker filling deck i's pipe doorway, on the hatch layer only.
func _build_hatch(i: int, y0: float, door_top: float) -> StaticBody3D:
	var hatch := StaticBody3D.new()
	hatch.name = "Hatch%d" % i
	hatch.collision_layer = HATCH_LAYER
	hatch.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * PIPE_INNER, door_top - y0, PIPE_WALL)
	shape.shape = box
	hatch.add_child(shape)
	hatch.position = Vector3(PIPE_CENTER.x, (y0 + door_top) / 2.0, PIPE_CENTER.y - PIPE_INNER - PIPE_WALL / 2.0)
	return hatch


func _ladder_length() -> float:
	return (deck_count - 1) * PITCH


func _build_ladder() -> Ladder:
	var ladder := Ladder.new(Vector3(PIPE_CENTER.x, 0.05, PIPE_CENTER.y), Vector3.UP, _ladder_length())
	for i in deck_count:
		var exit := Vector3(PIPE_CENTER.x, i * PITCH + 0.05, PIPE_CENTER.y - PIPE_INNER - PIPE_WALL - 0.7)
		ladder.add_landing(i * PITCH, exit, Vector3.BACK)
	return ladder
