class_name RingShip
extends Ship
## The 12-section ring: floor, ceiling and walls per section, with lights and crates, built from code.

const CRATES_PER_SECTION := 2
const CRATE_SEED := 1337


func _ready() -> void:
	for k in RingGeometry.SECTIONS:
		add_child(_build_section(k))
	add_child(_build_crates())


# --- sections ---------------------------------------------------------------

func up_at(p: Vector3) -> Vector3:
	return RingGeometry.up_at(p)


func camera_roll_at(p: Vector3) -> float:
	return RingGeometry.angle_of(p)


func room_at(p: Vector3) -> String:
	return "Section%d" % RingGeometry.section_of(p)


func spawn_point() -> Vector3:
	return RingGeometry.section_down(0) * (RingGeometry.floor_apothem() - 0.05)


func _build_section(k: int) -> Node3D:
	var section := Node3D.new()
	section.name = "Section%d" % k
	var t := RingGeometry.SLAB_THICKNESS
	var w := RingGeometry.HALF_WIDTH
	var floor_r := RingGeometry.floor_apothem()
	var ceiling_r := RingGeometry.ceiling_apothem()

	section.add_child(make_panel("Floor", _slab_points(k, -w - t, w + t, floor_r, floor_r + t),
			room_color(k, RingGeometry.SECTIONS), WORLD_LAYER | FLOOR_LAYER))
	section.add_child(make_panel("Ceiling", _slab_points(k, -w - t, w + t, ceiling_r - t, ceiling_r),
			trim_color(k, RingGeometry.SECTIONS), WORLD_LAYER | OCCLUDER_LAYER))
	section.add_child(make_panel("WallLeft", _slab_points(k, -w - t, -w, ceiling_r, floor_r),
			trim_color(k, RingGeometry.SECTIONS), WORLD_LAYER | OCCLUDER_LAYER))
	section.add_child(make_panel("WallRight", _slab_points(k, w, w + t, ceiling_r, floor_r),
			trim_color(k, RingGeometry.SECTIONS), WORLD_LAYER | OCCLUDER_LAYER))
	add_room_bound(section.name, section.get_node("Ceiling"), -RingGeometry.section_down(k))
	add_room_bound(section.name, section.get_node("WallLeft"), Vector3.LEFT)
	add_room_bound(section.name, section.get_node("WallRight"), Vector3.RIGHT)

	section.add_child(make_light(RingGeometry.section_down(k) * (ceiling_r + 0.6), 22.0))
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


# --- crates -----------------------------------------------------------------

func _build_crates() -> Node3D:
	var crates := Node3D.new()
	crates.name = "Crates"
	var rng := RandomNumberGenerator.new()
	rng.seed = CRATE_SEED
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
			crates.add_child(_crate(k, x, offset, size, yaw, count))
			placed += 1
			count += 1
	return crates


func _crate(k: int, x: float, offset: float, size: float, yaw: float, index: int) -> StaticBody3D:
	var down := RingGeometry.section_down(k)
	var up := -down
	var basis := Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)).rotated(up, yaw)
	var origin := Vector3(x, 0, 0) + RingGeometry.section_tangent(k) * offset \
			+ down * (RingGeometry.floor_apothem() - size / 2.0)
	return make_crate("Crate%d" % index, size, Transform3D(basis, origin))
