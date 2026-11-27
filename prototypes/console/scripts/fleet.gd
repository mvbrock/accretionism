class_name Fleet
extends RefCounted
## The ships the console can connect to, each by name. All of them run on the one clock, whether or not
## the console is connected to them.

## ship name -> Ship, in the order given.
var ships := {}


func _init(ships_by_name := {}) -> void:
	ships = ships_by_name


## One ship of each type: `ring`, `skiff`, `tug`, `freighter` and `wheel`.
static func standard() -> Fleet:
	return Fleet.new({
		"ring": RingShip.new(),
		"skiff": SkiffShip.new(),
		"tug": TugShip.new(),
		"freighter": FreighterShip.new(),
		"wheel": WheelShip.new(),
	})


func names() -> PackedStringArray:
	return PackedStringArray(ships.keys())


func advance(sim_seconds: float, step_s: float) -> void:
	for ship in ships.values():
		(ship as Ship).advance(sim_seconds, step_s)
