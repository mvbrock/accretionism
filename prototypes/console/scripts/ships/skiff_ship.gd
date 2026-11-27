class_name SkiffShip
extends Ship
## A zero-g skiff: cockpit, cabin and hold in a row, fore to aft along -z to +z, each 8 m wide and
## 4 m tall, with the floor at y 0. Doorways 2 m wide and 3.2 m tall at floor level join them; the
## hatch is on the hold's aft wall.

const WIDTH_M := 8.0
const HEIGHT_M := 4.0
const DOORWAY_M := Vector2(2.0, 3.2)
## Doorway centres sit half their height above the floor.
const DOORWAY_Y := 1.6


func _build() -> void:
	add_room("cockpit", Vector3(WIDTH_M, HEIGHT_M, 6.0), Vector3(0, 2, -9), Basis.IDENTITY, 1)
	add_room("cabin", Vector3(WIDTH_M, HEIGHT_M, 10.0), Vector3(0, 2, -1), Basis.IDENTITY, 1)
	add_room("hold", Vector3(WIDTH_M, HEIGHT_M, 8.0), Vector3(0, 2, 8))
	add_door("cockpit-cabin", "cockpit", Room.Face.PLUS_Z, "cabin", Room.Face.MINUS_Z,
			DOORWAY_M, Vector3(0, DOORWAY_Y, -6))
	add_door("cabin-hold", "cabin", Room.Face.PLUS_Z, "hold", Room.Face.MINUS_Z,
			DOORWAY_M, Vector3(0, DOORWAY_Y, 4))
	add_hatch("hatch", "hold", Room.Face.PLUS_Z)
