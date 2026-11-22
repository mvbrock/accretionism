class_name ShipLoader
extends RefCounted
## Builds a Ship from the data file. Bad data is reported with push_error,
## naming the offending value, and yields null.

const _REQUIRED_KEYS := ["seed", "setpoints", "rooms", "openings", "heat", "crew", "pressure_control",
		"hvac", "air_recycler", "computer", "tanks", "breakers", "status"]
const _ROOM_KEYS := ["id", "volume_m3", "crew", "start"]
const _START_KEYS := ["o2_kpa", "n2_kpa", "co2_kpa", "temperature_c"]
const _OPENING_KEYS := ["id", "between", "travel_s", "conductance_m3s"]


static func load_file(path: String) -> Ship:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Ship file '%s' is missing or empty" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Ship file '%s' is not a JSON object" % path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> Ship:
	var problem := _find_problem(data)
	if problem != "":
		push_error("Bad ship data: %s" % problem)
		return null
	var rooms: Array[Room] = []
	for entry in data.rooms:
		rooms.append(_make_room(entry, data.heat))
	var openings: Array[Opening] = []
	for entry in data.openings:
		openings.append(_make_opening(entry))
	return Ship.new(data, rooms, openings)


## Empty string when the data is usable, otherwise what is wrong with it.
static func _find_problem(data: Dictionary) -> String:
	for key in _REQUIRED_KEYS:
		if not data.has(key):
			return "missing '%s'" % key
	var room_ids := {}
	for entry in data.rooms:
		for key in _ROOM_KEYS:
			if not entry.has(key):
				return "room is missing '%s'" % key
		for key in _START_KEYS:
			if not entry.start.has(key):
				return "room '%s' start is missing '%s'" % [entry.id, key]
		if room_ids.has(entry.id):
			return "duplicate room '%s'" % entry.id
		room_ids[entry.id] = true
		if entry.volume_m3 <= 0:
			return "room '%s' has volume %s m3, which must be above 0" % [entry.id, entry.volume_m3]
		if Units.kelvin(entry.start.temperature_c) <= 0.0:
			return "room '%s' starts at %s C, which is not above absolute zero" % [
				entry.id, entry.start.temperature_c]
	var opening_ids := {}
	for entry in data.openings:
		for key in _OPENING_KEYS:
			if not entry.has(key):
				return "opening is missing '%s'" % key
		if opening_ids.has(entry.id):
			return "duplicate opening '%s'" % entry.id
		opening_ids[entry.id] = true
		if entry.between.size() != 2:
			return "opening '%s' must join exactly two places" % entry.id
		if entry.between[0] == Opening.OUTSIDE:
			return "opening '%s' must list the room first and outside second" % entry.id
		if entry.between[0] == entry.between[1]:
			return "opening '%s' joins '%s' to itself" % [entry.id, entry.between[0]]
		for place in entry.between:
			if place != Opening.OUTSIDE and not room_ids.has(place):
				return "opening '%s' joins unknown room '%s'" % [entry.id, place]
	for gas in ["O2", "N2"]:
		if not data.tanks.has(gas):
			return "missing tank '%s'" % gas
		if data.tanks[gas].capacity_mol <= 0:
			return "tank '%s' has capacity %s mol, which must be above 0" % [gas, data.tanks[gas].capacity_mol]
	return ""


static func _make_room(entry: Dictionary, heat: Dictionary) -> Room:
	var start: Dictionary = entry.start
	var room := Room.new(entry.id, float(entry.volume_m3), Units.kelvin(start.temperature_c), int(entry.crew))
	room.heat_capacity = heat.capacity_j_per_k_m3 * room.volume
	room.hull_conductance = heat.hull_w_per_k_m3 * room.volume
	room.set_partial_pressure("O2", start.o2_kpa * 1000.0)
	room.set_partial_pressure("N2", start.n2_kpa * 1000.0)
	room.set_partial_pressure("CO2", start.co2_kpa * 1000.0)
	return room


static func _make_opening(entry: Dictionary) -> Opening:
	var opening := Opening.new(entry.id, entry.between[0], entry.between[1], float(entry.travel_s))
	opening.conductance = entry.conductance_m3s
	opening.mixing = entry.get("mixing_m3s", 0.0)
	opening.heat_conductance = entry.get("heat_w_per_k", 0.0)
	return opening
