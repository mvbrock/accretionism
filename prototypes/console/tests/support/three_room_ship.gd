class_name ThreeRoomShip
extends Ship
## The ship the physics tests run on: a cockpit, a main room and a cargo room in a line, joined by
## doors `d1` and `d2`, with a `hatch` from cargo to outside. Random breaker trips are off.


func _param_overrides() -> Dictionary:
	return {"breakers": {"mean_time_between_trips_h": 0.0}}


func _build() -> void:
	add_room("cockpit", Vector3(2, 2, 3), Vector3(0, 0, 0), Basis.IDENTITY, 1)
	add_room("main", Vector3(4, 2.5, 4), Vector3(0, 0, 3.5), Basis.IDENTITY, 1)
	add_room("cargo", Vector3(3, 2.5, 4), Vector3(0, 0, 7.5))
	add_door("d1", "cockpit", Room.Face.PLUS_Z, "main", Room.Face.MINUS_Z)
	add_door("d2", "main", Room.Face.PLUS_Z, "cargo", Room.Face.MINUS_Z)
	add_hatch("hatch", "cargo", Room.Face.PLUS_Z)
