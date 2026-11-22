class_name ShipLoader
extends RefCounted
## Builds a Ship from the data file. Bad data is reported with push_error,
## naming the offending value, and yields null.

const _REQUIRED_KEYS := ["seed", "setpoints", "rooms", "openings", "heat", "passenger", "pressure_control",
		"hvac", "air_recycler", "computer", "tanks", "breakers", "status"]
const _ROOM_KEYS := ["id", "volume_m3", "passengers", "start"]
const _START_KEYS := ["o2_kpa", "n2_kpa", "co2_kpa", "temperature_c"]
const _TANK_KEYS := ["capacity_mol", "start_mol"]
const _OPENING_KEYS := ["id", "between", "travel_s", "conductance_m3s"]

## What was wrong with the most recent load; empty when it succeeded.
static var last_problem := ""


static func load_file(path: String) -> Ship:
	last_problem = ""
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail("file is missing or empty", "Ship file '%s' is missing or empty" % path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return _fail("file is not a JSON object", "Ship file '%s' is not a JSON object" % path)
	return from_dict(data)


static func from_dict(data: Dictionary) -> Ship:
	last_problem = ""
	var problem := _find_problem(data)
	if problem != "":
		return _fail(problem, "Bad ship data: " + problem)
	var rooms: Array[Room] = []
	for entry in data.rooms:
		rooms.append(_make_room(entry, data.heat))
	var openings: Array[Opening] = []
	for entry in data.openings:
		openings.append(_make_opening(entry))
	return Ship.new(data, rooms, openings)


static func _fail(problem: String, log_line: String) -> Ship:
	last_problem = problem
	push_error(log_line)
	return null


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
		var room_id_problem := _typing_problem(entry.id)
		if room_id_problem != "":
			return "room id '%s' %s" % [entry.id, room_id_problem]
		if room_ids.has(entry.id):
			return "duplicate room '%s'" % entry.id
		room_ids[entry.id] = true
		if entry.volume_m3 <= 0:
			return "room '%s' has volume %s m3, which must be above 0" % [entry.id, entry.volume_m3]
		if entry.passengers < 0 or entry.passengers != floorf(entry.passengers):
			return "room '%s' has passengers %s; it must be a whole number of at least 0" % [
				entry.id, entry.passengers]
		if Units.kelvin(entry.start.temperature_c) <= 0.0:
			return "room '%s' starts at %s C, which is not above absolute zero" % [
				entry.id, entry.start.temperature_c]
	var opening_ids := {}
	var outside_ids: Array = []
	for entry in data.openings:
		for key in _OPENING_KEYS:
			if not entry.has(key):
				return "opening is missing '%s'" % key
		var opening_id_problem := _typing_problem(entry.id)
		if opening_id_problem != "":
			return "opening id '%s' %s" % [entry.id, opening_id_problem]
		if opening_ids.has(entry.id):
			return "duplicate opening '%s'" % entry.id
		opening_ids[entry.id] = true
		if _clashes_with_a_breaker(entry.id):
			return "opening '%s' cannot be a system's id or start with '%s'" % [entry.id, Ship.LIGHT_BREAKER_PREFIX]
		if entry.between.size() != 2:
			return "opening '%s' must join exactly two places" % entry.id
		if entry.between[0] == Opening.OUTSIDE:
			return "opening '%s' must list the room first and outside second" % entry.id
		if entry.between[0] == entry.between[1]:
			return "opening '%s' joins '%s' to itself" % [entry.id, entry.between[0]]
		if entry.between[1] == Opening.OUTSIDE:
			outside_ids.append(entry.id)
		for place in entry.between:
			if place != Opening.OUTSIDE and not room_ids.has(place):
				return "opening '%s' joins unknown room '%s'" % [entry.id, place]
	if outside_ids.size() != 1:
		return "need exactly one opening to outside, found %d" % outside_ids.size()
	if outside_ids[0] != Opening.HATCH_ID:
		return "the opening to outside is '%s', which must be '%s'" % [outside_ids[0], Opening.HATCH_ID]
	for gas in Units.TANK_GASES:
		if not data.tanks.has(gas):
			return "missing tank '%s'" % gas
		for key in _TANK_KEYS:
			if not data.tanks[gas].has(key):
				return "tank '%s' is missing '%s'" % [gas, key]
		if data.tanks[gas].capacity_mol <= 0:
			return "tank '%s' has capacity %s mol, which must be above 0" % [gas, data.tanks[gas].capacity_mol]
		var start: float = data.tanks[gas].start_mol
		if start < 0 or start > data.tanks[gas].capacity_mol:
			return "tank '%s' starts at %s mol, which must be between 0 and its capacity %s mol" % [
				gas, start, data.tanks[gas].capacity_mol]
	return ""


## An id the command line cannot spell could never be typed.
static func _typing_problem(id: String) -> String:
	if id.is_empty():
		return "is empty"
	if not CommandInterpreter.is_typeable(id):
		return "must be lowercase and contain no whitespace"
	if id == Opening.OUTSIDE:
		return "is reserved for the outside"
	return ""


## Breaker ids are unique. An opening's breaker takes its id, which a system's id or a room light's prefix would collide with.
static func _clashes_with_a_breaker(id: String) -> bool:
	return Ship.SYSTEM_IDS.has(id) or id.begins_with(Ship.LIGHT_BREAKER_PREFIX)


static func _make_room(entry: Dictionary, heat: Dictionary) -> Room:
	var start: Dictionary = entry.start
	var room := Room.new(entry.id, float(entry.volume_m3), Units.kelvin(start.temperature_c), int(entry.passengers))
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
