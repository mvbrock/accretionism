class_name RingShip
extends Ship
## A ring spinning about the x axis: a 10 m wide, 5 m tall corridor 50 m out, in twelve segment
## rooms `s0`…`s11`. Segment 0 hangs straight down (-y) and the angle grows with the number; each
## segment's floor (-y) faces away from the axis. A doorway the corridor's full cross-section joins
## each segment to the next. Hatches in the floors of s0 and s6; one crew member in s0, s3, s6 and s9.

const SEGMENTS := 12
## The floor's corners are 50 m from the axis, as in prototypes/ship.
const FLOOR_CORNER_RADIUS_M := 50.0
const WIDTH_M := 10.0
const HEIGHT_M := 5.0
const DOORWAY_M := Vector2(WIDTH_M, HEIGHT_M)
const SEGMENT_ANGLE := TAU / SEGMENTS


func _build() -> void:
	add_ring(self, "s", 0.0, [0, 3, 6, 9])
	add_hatch("hatch0", "s0", Room.Face.MINUS_Y)
	add_hatch("hatch6", "s6", Room.Face.MINUS_Y)


## Adds a ring's segments `<prefix>0`…`<prefix>11`, centred `axial_m` along the axis, and the
## doors between them, `<prefix>0-<prefix>1` … `<prefix>11-<prefix>0`. The segments numbered in
## `crewed` get one crew member each.
static func add_ring(ship: Ship, prefix: String, axial_m: float, crewed: Array) -> void:
	# Each segment is a box between the floor and ceiling panels, as long as the chord at
	# mid-height, so neighbours' end faces cross at the middle of the doorway between them.
	var centre_radius := floor_apothem() - HEIGHT_M / 2.0
	var length := 2.0 * centre_radius * tan(SEGMENT_ANGLE / 2.0)
	for k in SEGMENTS:
		var turn := segment_basis(k)
		ship.add_room("%s%d" % [prefix, k], Vector3(WIDTH_M, HEIGHT_M, length),
				Vector3(axial_m, 0, 0) + turn * Vector3(0, -centre_radius, 0), turn, 1 if k in crewed else 0)
	for k in SEGMENTS:
		var next := (k + 1) % SEGMENTS
		ship.add_door("%s%d-%s%d" % [prefix, k, prefix, next], "%s%d" % [prefix, k], Room.Face.MINUS_Z,
				"%s%d" % [prefix, next], Room.Face.PLUS_Z, DOORWAY_M)


## Segment k's turn about the axis from segment 0.
static func segment_basis(k: int) -> Basis:
	return Basis(Vector3.RIGHT, SEGMENT_ANGLE * k)


## The floor's distance from the axis, at the middle of a segment.
static func floor_apothem() -> float:
	return FLOOR_CORNER_RADIUS_M * cos(SEGMENT_ANGLE / 2.0)
