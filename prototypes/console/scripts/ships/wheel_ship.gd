class_name WheelShip
extends Ship
## Three rings like the RingShip's, `a`, `b` and `c`, 24 m apart along the spin axis around a
## zero-g hub. Each ring joins the hub by two spokes, ladder pipes from the ceilings of segments 0
## and 6 (`spokea0`, `spokea6`, …) to the hub's floor and ceiling, so the hub has exactly six doors.
## The hatch is in b3's floor. One crew member in the hub, b0, a3 and c9.

const RINGS := {"a": -24.0, "b": 0.0, "c": 24.0}
const CREWED := {"a": [3], "b": [0], "c": [9]}
const SPOKE_SEGMENTS := [0, 6]
## The hub's cross-section is that of prototypes/ship's 12-sided hub: its floor corners are 10 m
## from the axis, so it is twice that apothem across.
const HUB_CORNER_RADIUS_M := 10.0
const HUB_LENGTH_M := 60.0
const SPOKE_WIDTH_M := 1.4
const SPOKE_DOORWAY_M := Vector2(SPOKE_WIDTH_M, SPOKE_WIDTH_M)


func _build() -> void:
	for ring in RINGS:
		RingShip.add_ring(self, ring, RINGS[ring], CREWED[ring])
	var hub_half := HUB_CORNER_RADIUS_M * cos(RingShip.SEGMENT_ANGLE / 2.0)
	var spoke_length := RingShip.floor_apothem() - RingShip.HEIGHT_M - hub_half
	for ring in RINGS:
		for k in SPOKE_SEGMENTS:
			var turn := RingShip.segment_basis(k)
			# The spoke's +z points at the axis.
			add_room("spoke%s%d" % [ring, k], Vector3(SPOKE_WIDTH_M, SPOKE_WIDTH_M, spoke_length),
					Vector3(RINGS[ring], 0, 0) + turn * Vector3(0, -(hub_half + spoke_length / 2.0), 0),
					turn * Basis(Vector3.RIGHT, -PI / 2.0))
	add_room("hub", Vector3(HUB_LENGTH_M, 2.0 * hub_half, 2.0 * hub_half), Vector3.ZERO, Basis.IDENTITY, 1)
	for ring in RINGS:
		for k in SPOKE_SEGMENTS:
			var spoke := "spoke%s%d" % [ring, k]
			add_door("%s%d-%s" % [ring, k, spoke], "%s%d" % [ring, k], Room.Face.PLUS_Y, spoke, Room.Face.MINUS_Z,
					SPOKE_DOORWAY_M)
			# Segment 0's spokes come up from below the hub, segment 6's down from above.
			add_door("%s-hub" % spoke, spoke, Room.Face.PLUS_Z, "hub",
					Room.Face.MINUS_Y if k == 0 else Room.Face.PLUS_Y, SPOKE_DOORWAY_M)
	add_hatch("hatch", "b3", Room.Face.MINUS_Y)
