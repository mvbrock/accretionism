class_name ShipFixture
extends RefCounted
## Builds a Ship from the shipped data file for tests.


## Loads res://data/ship.json with random trips off, deep-merges `overrides`
## (Dictionaries merge, everything else replaces) and builds the ship.
static func make(overrides := {}) -> Ship:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ship.json"))
	data.breakers.mean_time_between_trips_h = 0
	_merge(data, overrides)
	return ShipLoader.from_dict(data)


static func _merge(into: Dictionary, overrides: Dictionary) -> void:
	for key in overrides:
		if into.get(key) is Dictionary and overrides[key] is Dictionary:
			_merge(into[key], overrides[key])
		else:
			into[key] = overrides[key]
