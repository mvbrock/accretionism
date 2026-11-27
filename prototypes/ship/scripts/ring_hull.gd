class_name RingHull
extends RefCounted
## Builds a 12-section ring (RingGeometry's sections) around world X into a parent node, for a ship.

const CRATE_SEED := 1337

var center_x := 0.0
var half_width := RingGeometry.HALF_WIDTH
var floor_corner_radius := RingGeometry.FLOOR_CORNER_RADIUS
## Distance between floor and ceiling. 0 means no ceiling.
var ceiling_height := RingGeometry.CEILING_HEIGHT
var walls := true
var crates_per_section := 0
## Room names are room_prefix + "Section%d".
var room_prefix := ""
var light_range := 22.0
## Added to each section's hue fraction, so rings can differ.
var hue_offset := 0.0

## Section index -> list of [across position, half size] of its ceiling / floor holes.
var _ceiling_holes := {}
var _floor_holes := {}


func floor_apothem() -> float:
	return floor_corner_radius * cos(RingGeometry.HALF_ANGLE)


func ceiling_apothem() -> float:
	return floor_apothem() - ceiling_height


## A square hole centered on section k's ceiling panel center at across-position x. Call before build. A section may have several holes, which must not overlap across.
func add_ceiling_hole(k: int, x: float, half_size: float) -> void:
	_add_hole(_ceiling_holes, k, x, half_size)


## A square hole centered on section k's floor panel center at across-position x. Call before build. A section may have several holes, which must not overlap across.
func add_floor_hole(k: int, x: float, half_size: float) -> void:
	_add_hole(_floor_holes, k, x, half_size)


func _add_hole(holes: Dictionary, k: int, x: float, half_size: float) -> void:
	if not holes.has(k):
		holes[k] = []
	holes[k].append([x, half_size])


## The room containing `p`, or "" outside the hull's slabs.
func room_at(p: Vector3) -> String:
	var t := RingGeometry.SLAB_THICKNESS
	if absf(p.x - center_x) > half_width + t:
		return ""
	var radius := Vector2(p.y, p.z).length()
	var inner := ceiling_apothem() - t if ceiling_height > 0.0 else 0.0
	if radius < inner or radius > floor_corner_radius + t:
		return ""
	return room_prefix + "Section%d" % RingGeometry.section_of(p)


## Adds Section0..11 and, with crates_per_section > 0, Crates under `parent`, and registers room bounds on `ship`.
func build(ship: Ship, parent: Node3D) -> void:
	for k in RingGeometry.SECTIONS:
		parent.add_child(_build_section(ship, k))
	if crates_per_section > 0:
		parent.add_child(_build_crates(ship))


func _hue(k: int) -> float:
	return fposmod(float(k) / RingGeometry.SECTIONS + hue_offset, 1.0)


func _build_section(ship: Ship, k: int) -> Node3D:
	var section := Node3D.new()
	section.name = "Section%d" % k
	var t := RingGeometry.SLAB_THICKNESS
	var w := half_width
	var floor_r := floor_apothem()
	var ceiling_r := ceiling_apothem()
	var room := room_prefix + section.name
	var room_color := Color.from_hsv(_hue(k), 0.65, 0.85)
	var trim_color := Color.from_hsv(_hue(k), 0.25, 0.75)

	_add_slab(section, "Floor", k, center_x - w - t, center_x + w + t, floor_r, floor_r + t, _floor_holes.get(k),
			room_color, Ship.WORLD_LAYER | Ship.FLOOR_LAYER, ship, room, Vector3.ZERO)
	if ceiling_height > 0.0:
		_add_slab(section, "Ceiling", k, center_x - w - t, center_x + w + t, ceiling_r - t, ceiling_r,
				_ceiling_holes.get(k), trim_color, Ship.WORLD_LAYER | Ship.OCCLUDER_LAYER, ship, room,
				-RingGeometry.section_down(k))
	if walls:
		section.add_child(ship.make_panel("WallLeft", _slab_points(k, center_x - w - t, center_x - w, ceiling_r, floor_r),
				trim_color, Ship.WORLD_LAYER | Ship.OCCLUDER_LAYER))
		section.add_child(ship.make_panel("WallRight", _slab_points(k, center_x + w, center_x + w + t, ceiling_r, floor_r),
				trim_color, Ship.WORLD_LAYER | Ship.OCCLUDER_LAYER))
		ship.add_room_bound(room, section.get_node("WallLeft"), Vector3.LEFT)
		ship.add_room_bound(room, section.get_node("WallRight"), Vector3.RIGHT)

	var light_r := ceiling_r + 0.6 if ceiling_height > 0.0 else floor_r - 5.0
	section.add_child(ship.make_light(Vector3(center_x, 0, 0) + RingGeometry.section_down(k) * light_r, light_range))
	return section


## Adds one panel, or with holes several pieces named `panel_name` + "a", "b", "c"... in build order.
## Holes (lists of [across position, half size]) must not overlap across. Across the panel come full-length
## strips in the gaps and beyond the outermost holes, and before and after each hole its two along-panel strips.
## Each piece is registered as a room bound facing `outward`; a zero `outward` registers nothing.
func _add_slab(section: Node3D, panel_name: String, k: int, x0: float, x1: float, r0: float, r1: float,
		holes: Variant, color: Color, layers: int, ship: Ship, room: String, outward: Vector3) -> void:
	var pieces: Array[PackedVector3Array] = []
	if holes == null:
		pieces.append(_slab_points(k, x0, x1, r0, r1))
	else:
		var sorted: Array = holes.duplicate()
		sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var cursor := x0
		for hole: Array in sorted:
			var hx: float = hole[0]
			var h: float = hole[1]
			if hx - h > cursor:
				pieces.append(_slab_points(k, cursor, hx - h, r0, r1))
			pieces.append(_slab_points(k, hx - h, hx + h, r0, r1, -INF, -h))
			pieces.append(_slab_points(k, hx - h, hx + h, r0, r1, h, INF))
			cursor = hx + h
		if x1 > cursor:
			pieces.append(_slab_points(k, cursor, x1, r0, r1))
	for i in pieces.size():
		var piece := ship.make_panel(panel_name if holes == null else panel_name + char(97 + i), pieces[i], color, layers)
		section.add_child(piece)
		if outward != Vector3.ZERO:
			ship.add_room_bound(room, piece, outward)


## The 8 corners of a slab in section k spanning x ∈ [x0, x1] and radius ∈ [r0, r1].
## Its length along the panel scales with radius, so neighboring slabs meet exactly at the seams;
## `along_min` and `along_max` clamp it to a stretch of the panel, as offsets from the panel's center.
func _slab_points(k: int, x0: float, x1: float, r0: float, r1: float,
		along_min := -INF, along_max := INF) -> PackedVector3Array:
	var down := RingGeometry.section_down(k)
	var along := RingGeometry.section_tangent(k)
	var points := PackedVector3Array()
	for x in [x0, x1]:
		for r in [r0, r1]:
			var half := RingGeometry.half_length_at(r)
			for s in [-1.0, 1.0]:
				points.append(Vector3(x, 0, 0) + down * r + along * clampf(half * s, along_min, along_max))
	return points


func _build_crates(ship: Ship) -> Node3D:
	var crates := Node3D.new()
	crates.name = "Crates"
	var rng := RandomNumberGenerator.new()
	rng.seed = CRATE_SEED
	var count := 0
	for k in RingGeometry.SECTIONS:
		var placed := 0
		while placed < crates_per_section:
			var size := 1.0 if rng.randf() < 0.5 else 1.5
			var x := rng.randf_range(-4.0, 4.0)
			var offset := rng.randf_range(-10.0, 10.0)
			var yaw := rng.randf_range(0.0, TAU)
			if k == 0 and absf(offset) < 3.0:
				continue  # keep the spawn point clear
			crates.add_child(_crate(ship, k, x, offset, size, yaw, count))
			placed += 1
			count += 1
	return crates


func _crate(ship: Ship, k: int, x: float, offset: float, size: float, yaw: float, index: int) -> StaticBody3D:
	var down := RingGeometry.section_down(k)
	var up := -down
	var basis := Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)).rotated(up, yaw)
	var origin := Vector3(center_x + x, 0, 0) + RingGeometry.section_tangent(k) * offset \
			+ down * (floor_apothem() - size / 2.0)
	return ship.make_crate("Crate%d" % index, size, Transform3D(basis, origin))
