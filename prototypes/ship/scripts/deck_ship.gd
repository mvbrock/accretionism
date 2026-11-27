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
const DOOR_HEIGHT := 2.6
const WALL := WORLD_LAYER | OCCLUDER_LAYER
const SOLID_FLOOR := WORLD_LAYER | FLOOR_LAYER | OCCLUDER_LAYER


func _ready() -> void:
	for i in deck_count:
		add_child(_build_deck(i))
	add_rungs(_pipe_frame(), 0.05, _ladder_length() + 0.05,
			func(y: float) -> Node3D: return get_node("Deck%d" % deck_at(Vector3(0, y, 0))))
	ladders.append(_build_ladder())


func spawn_point() -> Vector3:
	return Vector3(-2, 0.05, -2)


## The deck at height `p.y`, clamped to the stack. A deck runs from the underside of its floor slab
## to the underside of the next, so feet resting on a floor are well inside their own deck.
func deck_at(p: Vector3) -> int:
	return clampi(floori((p.y + SLAB) / PITCH), 0, deck_count - 1)


## The decks above the one holding `p`.
func cutaway_nodes(p: Vector3) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for j in range(deck_at(p) + 1, deck_count):
		nodes.append(get_node("Deck%d" % j))
	return nodes


## "Pipe" inside the shaft, otherwise the deck at height `p.y`.
func room_at(p: Vector3) -> String:
	if absf(p.x - PIPE_CENTER.x) < PIPE_INNER and absf(p.z - PIPE_CENTER.y) < PIPE_INNER:
		return "Pipe"
	return "Deck%d" % deck_at(p)


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

	add_pipe_segment(deck, _pipe_frame(), base, base + (HEIGHT if i == deck_count - 1 else PITCH), DOOR_HEIGHT,
			false, trim, "Pipe")
	deck.add_child(make_light(Vector3(0, top - 0.6, 0), 14.0))
	deck.add_child(make_crate("Crate0", 1.0, Transform3D(Basis.IDENTITY, Vector3(-4.5, base + 0.5, 3.5))))
	deck.add_child(make_crate("Crate1", 1.0, Transform3D(Basis.IDENTITY, Vector3(-3.5, base + 0.5, -4.5))))
	return deck


## Four panels `prefix`a to d from y = `y0` up `SLAB`, around a hole the size of the pipe's outer footprint.
func _add_slab(parent: Node3D, prefix: String, y0: float, color: Color, layers: int) -> Array[StaticBody3D]:
	var reach := HALF + SLAB
	return add_holed_slab(parent, prefix, Vector3(-reach, y0, -reach), Vector3(reach, y0 + SLAB, reach), PIPE_CENTER,
			PIPE_OUTER, color, layers)


## The pipe's frame: its axis is world Y through PIPE_CENTER, the doorway toward -Z.
func _pipe_frame() -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(PIPE_CENTER.x, 0, PIPE_CENTER.y))


func _ladder_length() -> float:
	return (deck_count - 1) * PITCH


func _build_ladder() -> Ladder:
	var ladder := Ladder.new(Vector3(PIPE_CENTER.x, 0.05, PIPE_CENTER.y), Vector3.UP, _ladder_length())
	for i in deck_count:
		var exit := Vector3(PIPE_CENTER.x, i * PITCH + 0.05, PIPE_CENTER.y - PIPE_INNER - PIPE_WALL - 0.7)
		ladder.add_landing(i * PITCH, exit, Vector3.BACK)
	return ladder
