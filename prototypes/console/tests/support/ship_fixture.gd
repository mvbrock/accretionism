class_name ShipFixture
extends RefCounted
## Builds the ships the tests run on.

const KESTREL_PATH := "res://data/ships/kestrel.json"


## A ThreeRoomShip with random trips off and `overrides` deep-merged into its params
## (Dictionaries merge, everything else replaces).
static func make(overrides := {}) -> Ship:
	return ThreeRoomShip.new(overrides)


## A FourRoomShip, built like `make`.
static func make_four_room(overrides := {}) -> Ship:
	return FourRoomShip.new(overrides)
