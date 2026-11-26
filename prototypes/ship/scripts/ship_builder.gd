class_name ShipBuilder
extends Node3D
## Builds the 12-section ring (floor, ceiling and walls per section), its lights and crates from code.

const WORLD_LAYER := 1
const OCCLUDER_LAYER := 2
const CRATES_PER_SECTION := 2
const CRATE_SEED := 1337
const CRATE_COLOR := Color(0.62, 0.45, 0.28)


static func section_color(k: int) -> Color:
	return Color.from_hsv(float(k) / RingGeometry.SECTIONS, 0.65, 0.85)


static func trim_color(k: int) -> Color:
	return Color.from_hsv(float(k) / RingGeometry.SECTIONS, 0.25, 0.75)


func _ready() -> void:
	for k in RingGeometry.SECTIONS:
		add_child(_build_section(k))
	add_child(_build_crates())
	add_child(_build_environment())


# --- sections ---------------------------------------------------------------

## The meshes that hide a player standing in section k from a camera looking along `view`:
## its ceiling and the wall on the camera's side.
func room_fade_meshes(k: int, view: Vector3) -> Array[MeshInstance3D]:
	var section := get_node("Section%d" % k)
	var wall := "WallLeft" if view.x > 0.0 else "WallRight"
	return [section.get_node("Ceiling/Mesh"), section.get_node(wall + "/Mesh")]


func _build_section(k: int) -> Node3D:
	var section := Node3D.new()
	section.name = "Section%d" % k
	var t := RingGeometry.SLAB_THICKNESS
	var w := RingGeometry.HALF_WIDTH
	var floor_r := RingGeometry.floor_apothem()
	var ceiling_r := RingGeometry.ceiling_apothem()

	section.add_child(_panel("Floor", _slab_points(k, -w - t, w + t, floor_r, floor_r + t),
			section_color(k), WORLD_LAYER))
	section.add_child(_panel("Ceiling", _slab_points(k, -w - t, w + t, ceiling_r - t, ceiling_r),
			trim_color(k), WORLD_LAYER | OCCLUDER_LAYER))
	section.add_child(_panel("WallLeft", _slab_points(k, -w - t, -w, ceiling_r, floor_r),
			trim_color(k), WORLD_LAYER | OCCLUDER_LAYER))
	section.add_child(_panel("WallRight", _slab_points(k, w, w + t, ceiling_r, floor_r),
			trim_color(k), WORLD_LAYER | OCCLUDER_LAYER))

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = RingGeometry.section_down(k) * (ceiling_r + 0.6)
	light.omni_range = 22.0
	light.light_energy = 1.6
	light.shadow_enabled = true
	section.add_child(light)
	return section


## The 8 corners of a slab in section k spanning x ∈ [x0, x1] and radius ∈ [r0, r1].
## Its length along the panel scales with radius, so neighboring slabs meet exactly at the seams.
func _slab_points(k: int, x0: float, x1: float, r0: float, r1: float) -> PackedVector3Array:
	var down := RingGeometry.section_down(k)
	var along := RingGeometry.section_tangent(k)
	var points := PackedVector3Array()
	for x in [x0, x1]:
		for r in [r0, r1]:
			var half := RingGeometry.half_length_at(r)
			for s in [-1.0, 1.0]:
				points.append(Vector3(x, 0, 0) + down * r + along * (half * s))
	return points


func _panel(panel_name: String, points: PackedVector3Array, color: Color, layers: int) -> StaticBody3D:
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
	mesh.mesh = _prism_mesh(points)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material_override = material
	body.add_child(mesh)

	if layers & OCCLUDER_LAYER:
		body.set_meta("fade_mesh", mesh)
	return body


## Flat-shaded mesh for a slab from `_slab_points` (index = x*4 + r*2 + s).
func _prism_mesh(p: PackedVector3Array) -> ArrayMesh:
	var center := Vector3.ZERO
	for v in p:
		center += v
	center /= p.size()
	var faces := [
		[0, 1, 3, 2], [4, 5, 7, 6],  # x0, x1
		[0, 1, 5, 4], [2, 3, 7, 6],  # r0, r1
		[0, 2, 6, 4], [1, 3, 7, 5],  # s-, s+
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


# --- crates -----------------------------------------------------------------

func _build_crates() -> Node3D:
	var crates := Node3D.new()
	crates.name = "Crates"
	var rng := RandomNumberGenerator.new()
	rng.seed = CRATE_SEED
	var material := StandardMaterial3D.new()
	material.albedo_color = CRATE_COLOR
	material.roughness = 0.9
	var count := 0
	for k in RingGeometry.SECTIONS:
		var placed := 0
		while placed < CRATES_PER_SECTION:
			var size := 1.0 if rng.randf() < 0.5 else 1.5
			var x := rng.randf_range(-4.0, 4.0)
			var offset := rng.randf_range(-10.0, 10.0)
			var yaw := rng.randf_range(0.0, TAU)
			if k == 0 and absf(offset) < 3.0:
				continue  # keep the spawn point clear
			crates.add_child(_crate(k, x, offset, size, yaw, material, count))
			placed += 1
			count += 1
	return crates


func _crate(k: int, x: float, offset: float, size: float, yaw: float,
		material: StandardMaterial3D, index: int) -> StaticBody3D:
	var down := RingGeometry.section_down(k)
	var up := -down
	var body := StaticBody3D.new()
	body.name = "Crate%d" % index
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("size", size)
	var basis := Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)).rotated(up, yaw)
	var origin := Vector3(x, 0, 0) + RingGeometry.section_tangent(k) * offset \
			+ down * (RingGeometry.floor_apothem() - size / 2.0)
	body.transform = Transform3D(basis, origin)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)
	return body


# --- environment ------------------------------------------------------------

func _build_environment() -> WorldEnvironment:
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
