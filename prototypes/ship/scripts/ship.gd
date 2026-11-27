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


## Whether the player may walk with gravity aboard this ship (false: it only floats).
func has_gravity() -> bool:
	return true


## Which way is up for something standing at `p`.
func up_at(_p: Vector3) -> Vector3:
	return Vector3.UP


## Rotation of the camera rig about X when the player stands at `p`.
func camera_roll_at(_p: Vector3) -> float:
	return 0.0


## The meshes that hide a player standing at `p` from a camera looking along `view`.
func room_fade_meshes(_p: Vector3, _view: Vector3) -> Array[MeshInstance3D]:
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
func make_environment() -> WorldEnvironment:
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
