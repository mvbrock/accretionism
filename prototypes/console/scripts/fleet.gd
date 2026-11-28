class_name Fleet
extends RefCounted
## The ships the console can connect to, each by name. All of them run on the one clock, whether or not
## the console is connected to them.

## ship name -> Ship, in the order given.
var ships := {}


## A ship whose name cannot be typed on the command line is left out, with an error naming it.
func _init(ships_by_name := {}) -> void:
	for ship_name in ships_by_name:
		if CommandInterpreter.is_typeable(ship_name):
			ships[ship_name] = ships_by_name[ship_name]
		else:
			push_error("Ship name '%s' must be lowercase and contain no whitespace" % ship_name)


## One ship of each type: `ring`, `skiff`, `tug`, `freighter` and `wheel`.
static func standard() -> Fleet:
	return Fleet.new({
		"ring": RingShip.new(),
		"skiff": SkiffShip.new(),
		"tug": TugShip.new(),
		"freighter": FreighterShip.new(),
		"wheel": WheelShip.new(),
	})


## Every ship runs on the one clock, so any ship's time is the fleet's; 0 with no ships.
func time_s() -> float:
	return (ships.values()[0] as Ship).time_s if not ships.is_empty() else 0.0


func names() -> PackedStringArray:
	return PackedStringArray(ships.keys())


func advance(sim_seconds: float, step_s: float) -> void:
	for ship in ships.values():
		(ship as Ship).advance(sim_seconds, step_s)
