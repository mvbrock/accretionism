class_name FourRoomShip
extends ThreeRoomShip
## ThreeRoomShip plus a 12 m3 `treehouse` with one passenger, joined to the cockpit by `d0`.
## The treehouse is the first room and `d0` the first opening, so the rooms connect in order.


func _build() -> void:
	add_room("treehouse", Vector3(2, 2, 3), Vector3(0, 0, -3), Basis.IDENTITY, 1)
	add_door("d0", "treehouse", Room.Face.PLUS_Z, "cockpit", Room.Face.MINUS_Z)
	super._build()
