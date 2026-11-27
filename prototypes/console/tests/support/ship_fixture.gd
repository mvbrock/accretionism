class_name ShipFixture
extends RefCounted


## A ThreeRoomShip with random trips off and `overrides` deep-merged into its params
## (Dictionaries merge, everything else replaces).
static func make(overrides := {}) -> Ship:
	return ThreeRoomShip.new(overrides)


static func make_four_room(overrides := {}) -> Ship:
	return FourRoomShip.new(overrides)


## A Fleet of two test ships for the tests of the link and the console, which need ships to
## connect to but not any ship's shape: `kestrel` is a ThreeRoomShip and `wren` a FourRoomShip.
static func make_fleet() -> Fleet:
	return Fleet.new({"kestrel": make(), "wren": make_four_room()})
