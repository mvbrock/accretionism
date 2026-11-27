class_name Ship
extends Node3D
## A ship the player can be aboard. Sits at the world origin.
## Subclasses build their own geometry and override the queries below. Every floor panel goes on
## FLOOR_LAYER as well as WORLD_LAYER, because the floating player measures its height against it.
## Walls and ceilings that may hide the player go on OCCLUDER_LAYER and carry a "fade_mesh" meta
## naming their mesh; `make_panel` does both from the layers it is given.

const WORLD_LAYER := 1
const OCCLUDER_LAYER := 2
const FLOOR_LAYER := 4
## Invisible blockers that keep the player out of a pipe doorway; only a ladder lets it through.
const HATCH_LAYER := 8
const CRATE_COLOR := Color(0.62, 0.45, 0.28)
## Ladder pipes: the open half-width, the wall thickness and the outer half-width.
const PIPE_INNER := 0.7
const PIPE_WALL := 0.15
const PIPE_OUTER := PIPE_INNER + PIPE_WALL
const RUNG_SPACING := 0.35
const RUNG_COLOR := Color(0.55, 0.55, 0.58)

## The ladder pipes aboard this ship.
var ladders: Array[Ladder] = []
var _crate_material: StandardMaterial3D
## Room name -> Array of [MeshInstance3D, outward Vector3] pairs, filled by `add_room_bound`.
var _room_bounds := {}


## Whether the player may walk with gravity aboard this ship (false: it only floats).
func has_gravity() -> bool:
	return true


## Whether gravity acts at `p`; a ship whose gravity varies by position overrides this.
func has_gravity_at(_p: Vector3) -> bool:
	return has_gravity()


## Which way is up for something standing at `p`.
func up_at(_p: Vector3) -> Vector3:
	return Vector3.UP


## Rotation of the camera rig about X when the player stands at `p`.
func camera_roll_at(_p: Vector3) -> float:
	return 0.0


## The name of the room containing `p`, or "" when `p` is in no room.
func room_at(_p: Vector3) -> String:
	return ""


## Records `panel`'s "fade_mesh" as bounding `room`, with `outward` (unit) pointing out of the room.
## A panel bounding two rooms is added once per room.
func add_room_bound(room: String, panel: StaticBody3D, outward: Vector3) -> void:
	var mesh: MeshInstance3D = panel.get_meta("fade_mesh", null)
	if mesh == null:
		push_error("%s has no fade_mesh meta" % panel.name)
		return
	if not _room_bounds.has(room):
		_room_bounds[room] = []
	_room_bounds[room].append([mesh, outward])


## The meshes that hide a player standing at `p` from a camera looking along `view`: the bounds of
## its room whose outward direction points against the view.
func room_fade_meshes(p: Vector3, view: Vector3) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for bound in _room_bounds.get(room_at(p), []):
		if bound[1].dot(view) < 0.0:
			meshes.append(bound[0])
	return meshes


## Nodes to hide so the player at `_p` sees in from above. None by default.
func cutaway_nodes(_p: Vector3) -> Array[Node3D]:
	return []


## Where the player starts.
func spawn_point() -> Vector3:
	return Vector3.ZERO


## A static body with a convex collision shape and a flat-shaded mesh from the 8 corners
## in `points` (see `prism_mesh`). Bodies on the occluder layer carry a "fade_mesh" meta.
func make_panel(panel_name: String, points: PackedVector3Array, color: Color, layers: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = panel_name
	body.collision_layer = layers
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	shape.shape = convex
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = prism_mesh(points)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	body.add_child(mesh)

	if layers & OCCLUDER_LAYER:
		body.set_meta("fade_mesh", mesh)
	return body


## An axis-aligned horizontal slab from `lo` to `hi`, with a square hole through it centered at (`hole_center.x`, `hole_center.y`)
## in X and Z and half-width `hole_half`, built as four box panels `prefix`a..d under `parent`.
func add_holed_slab(parent: Node3D, prefix: String, lo: Vector3, hi: Vector3, hole_center: Vector2, hole_half: float,
		color: Color, layers: int) -> Array[StaticBody3D]:
	var x0 := hole_center.x - hole_half
	var x1 := hole_center.x + hole_half
	var z0 := hole_center.y - hole_half
	var z1 := hole_center.y + hole_half
	var boxes := [
		[Vector3(lo.x, lo.y, lo.z), Vector3(x0, hi.y, hi.z)],
		[Vector3(x1, lo.y, lo.z), Vector3(hi.x, hi.y, hi.z)],
		[Vector3(x0, lo.y, lo.z), Vector3(x1, hi.y, z0)],
		[Vector3(x0, lo.y, z1), Vector3(x1, hi.y, hi.z)],
	]
	var panels: Array[StaticBody3D] = []
	for k in boxes.size():
		var panel := make_panel("%s%s" % [prefix, "abcd"[k]], box_points(boxes[k][0], boxes[k][1]), color, layers)
		parent.add_child(panel)
		panels.append(panel)
	return panels


## A distinct fill color for room `i` of `count`.
static func room_color(i: int, count: int) -> Color:
	return Color.from_hsv(float(i) / count, 0.65, 0.85)


## The paler wall color matching `room_color(i, count)`.
static func trim_color(i: int, count: int) -> Color:
	return Color.from_hsv(float(i) / count, 0.25, 0.75)


## One segment of a ladder pipe. Its axis runs along `frame.basis.y` from `frame.origin`; it spans `from`..`to` along
## the axis. `door_height > 0` opens a doorway on the frame's −Z side from `from` to `from + door_height`, filled by a
## hatch blocker. `capped` closes the `to` end. Pieces go under `parent` (PipeLeft, PipeRight, PipeAft, and PipeLintel
## or PipeFore, Hatch, PipeCap) and register as bounds of `room`.
func add_pipe_segment(parent: Node3D, frame: Transform3D, from: float, to: float, door_height: float,
		capped: bool, color: Color, room: String) -> void:
	var o := PIPE_OUTER
	var i := PIPE_INNER
	var layers := WORLD_LAYER | OCCLUDER_LAYER
	# [name, lo, hi, local outward]. The side walls span the -Z wall's corners, so it is only a lintel over the doorway.
	var pieces := [
		["PipeLeft", Vector3(-o, from, -o), Vector3(-i, to, o), Vector3.LEFT],
		["PipeRight", Vector3(i, from, -o), Vector3(o, to, o), Vector3.RIGHT],
		["PipeAft", Vector3(-i, from, i), Vector3(i, to, o), Vector3.BACK],
	]
	if door_height > 0.0:
		pieces.append(["PipeLintel", Vector3(-i, from + door_height, -o), Vector3(i, to, -i), Vector3.FORWARD])
	else:
		pieces.append(["PipeFore", Vector3(-i, from, -o), Vector3(i, to, -i), Vector3.FORWARD])
	if capped:
		pieces.append(["PipeCap", Vector3(-o, to, -o), Vector3(o, to + PIPE_WALL, o), Vector3.UP])
	for piece in pieces:
		var points := PackedVector3Array()
		for point in box_points(piece[1], piece[2]):
			points.append(frame * point)
		var panel := make_panel(piece[0], points, color, layers)
		parent.add_child(panel)
		add_room_bound(room, panel, (frame.basis * piece[3]).normalized())
	if door_height > 0.0:
		parent.add_child(_make_hatch(frame, from, door_height))


## An invisible blocker filling a pipe doorway, on the hatch layer only.
func _make_hatch(frame: Transform3D, from: float, door_height: float) -> StaticBody3D:
	var hatch := StaticBody3D.new()
	hatch.name = "Hatch"
	hatch.collision_layer = HATCH_LAYER
	hatch.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0 * PIPE_INNER, door_height, PIPE_WALL)
	shape.shape = box
	hatch.add_child(shape)
	var center := Vector3(0, from + door_height / 2.0, -PIPE_INNER - PIPE_WALL / 2.0)
	hatch.transform = Transform3D(frame.basis, frame * center)
	return hatch


## Rungs on the frame's +Z wall every RUNG_SPACING from `from` to `to`, each added to `parent_for.call(s)`.
func add_rungs(frame: Transform3D, from: float, to: float, parent_for: Callable) -> void:
	var rung_material := StandardMaterial3D.new()
	rung_material.albedo_color = RUNG_COLOR
	for k in int(floor((to - from) / RUNG_SPACING)) + 1:
		var s := from + k * RUNG_SPACING
		var rung := MeshInstance3D.new()
		rung.name = "Rung%d" % k
		var box := BoxMesh.new()
		box.size = Vector3(2.0 * PIPE_INNER - 0.2, 0.04, 0.04)
		rung.mesh = box
		rung.material_override = rung_material
		rung.transform = Transform3D(frame.basis, frame * Vector3(0, s, PIPE_INNER - 0.06))
		parent_for.call(s).add_child(rung)


## A shadow-casting omni light named "Light" at `at`, reaching `light_range` metres.
func make_light(at: Vector3, light_range: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = at
	light.omni_range = light_range
	light.light_energy = 1.6
	light.shadow_enabled = true
	return light


## A crate `size` metres on a side, placed by `at`. It sits on the world layer only, so the
## player bumps into it but a floating player measures its height from the floor beneath.
func make_crate(crate_name: String, size: float, at: Transform3D) -> StaticBody3D:
	if _crate_material == null:
		_crate_material = StandardMaterial3D.new()
		_crate_material.albedo_color = CRATE_COLOR
		_crate_material.roughness = 0.9
	var body := StaticBody3D.new()
	body.name = crate_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("size", size)
	body.transform = at

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * size
	mesh.mesh = box_mesh
	mesh.material_override = _crate_material
	body.add_child(mesh)
	return body


## The 8 corners of the axis-aligned box from `lo` to `hi`, in `prism_mesh` index order
## (index = x*4 + y*2 + z, where 0 picks the lo coordinate and 1 the hi one).
static func box_points(lo: Vector3, hi: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for x in [lo.x, hi.x]:
		for y in [lo.y, hi.y]:
			for z in [lo.z, hi.z]:
				points.append(Vector3(x, y, z))
	return points


## Flat-shaded mesh for a prism with 8 corners (index = a*4 + b*2 + c).
static func prism_mesh(p: PackedVector3Array) -> ArrayMesh:
	var center := Vector3.ZERO
	for v in p:
		center += v
	center /= p.size()
	var faces := [
		[0, 1, 3, 2], [4, 5, 7, 6],  # a0, a1
		[0, 1, 5, 4], [2, 3, 7, 6],  # b0, b1
		[0, 2, 6, 4], [1, 3, 7, 5],  # c0, c1
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var c: Vector3 = p[f[2]]
		var d: Vector3 = p[f[3]]
		var face_center := (a + b + c + d) / 4.0
		var outward := (face_center - center)
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(outward) < 0.0:
			normal = -normal
		else:
			# Godot treats clockwise triangles (seen from outside) as front faces.
			var tmp := b
			b = d
			d = tmp
		st.set_normal(normal)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	return st.commit()


## Dark background with a dim ambient fill.
static func make_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	return world_env
