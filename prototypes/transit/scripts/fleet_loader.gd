class_name FleetLoader
extends RefCounted
## Builds a Fleet from the data file. Bad data is reported with push_error,
## naming the offending value, and yields null; nothing global is touched
## unless the whole file is valid.

const RANDOM_ORIGIN := "random"
const _REQUIRED_KEYS := ["seed", "epoch_angles_deg", "timetable", "cyclers", "transports"]
const _REQUIRED_TIMETABLE_KEYS := ["cycle_days", "short_leg_days", "long_leg_days"]


static func load_file(path: String) -> Fleet:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Fleet file '%s' is missing or empty" % path)
		return null
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Fleet file '%s' is not a JSON object" % path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> Fleet:
	var problem := _find_problem(data)
	if problem != "":
		push_error("Bad fleet data: %s" % problem)
		return null
	_apply_world_settings(data)
	var fleet := Fleet.new()
	for entry in data.cyclers:
		fleet.cyclers.append(Cycler.new(entry.name, Cycler.Direction[entry.direction], entry.phase_day))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed)
	for entry in data.transports:
		var origin: String = entry.origin
		if origin == RANDOM_ORIGIN:
			origin = _random_origin_name(rng, fleet.cyclers)
		fleet.transports.append(_transport_at(entry.name, origin, fleet.cyclers))
	return fleet


## Empty string when the data is usable, otherwise what is wrong with it.
static func _find_problem(data: Dictionary) -> String:
	for key in _REQUIRED_KEYS:
		if not data.has(key):
			return "missing '%s'" % key
	for body_name in _body_names():
		if not data.epoch_angles_deg.has(body_name):
			return "no epoch angle for '%s'" % body_name
	for key in _REQUIRED_TIMETABLE_KEYS:
		if not data.timetable.has(key):
			return "timetable is missing '%s'" % key
	var timetable: Dictionary = data.timetable
	if absf(timetable.short_leg_days + timetable.long_leg_days - timetable.cycle_days) > 1e-9:
		return "short leg %s + long leg %s days must equal the cycle of %s days" % [
			timetable.short_leg_days, timetable.long_leg_days, timetable.cycle_days]

	var ship_names := {}
	for entry in data.cyclers:
		if not Cycler.Direction.has(entry.direction):
			return "cycler '%s' has unknown direction '%s'" % [entry.name, entry.direction]
		if ship_names.has(entry.name):
			return "duplicate ship name '%s'" % entry.name
		ship_names[entry.name] = true
	var cycler_names := ship_names.keys()
	for entry in data.transports:
		if ship_names.has(entry.name):
			return "duplicate ship name '%s'" % entry.name
		ship_names[entry.name] = true
		var origin: String = entry.origin
		if origin != RANDOM_ORIGIN and not _body_names().has(origin) and not cycler_names.has(origin):
			return "transport '%s' has unknown origin '%s'" % [entry.name, origin]
	return ""


static func _body_names() -> Array:
	return Orbits.Body.values().map(func(body: Orbits.Body) -> String: return Orbits.body_name(body))


static func _apply_world_settings(data: Dictionary) -> void:
	var angles := {}
	for body in Orbits.Body.values():
		angles[body] = data.epoch_angles_deg[Orbits.body_name(body)]
	Orbits.configure(angles)
	Cycler.cycle_days = data.timetable.cycle_days
	Cycler.short_leg_days = data.timetable.short_leg_days


static func _random_origin_name(rng: RandomNumberGenerator, cyclers: Array[Cycler]) -> String:
	var index := rng.randi_range(0, Orbits.Body.size() + cyclers.size() - 1)
	var bodies := Orbits.Body.values()
	if index < bodies.size():
		return Orbits.body_name(bodies[index])
	return cyclers[index - bodies.size()].name


static func _transport_at(transport_name: String, origin: String, cyclers: Array[Cycler]) -> Transport:
	for body in Orbits.Body.values():
		if Orbits.body_name(body) == origin:
			return Transport.parked_at(transport_name, body)
	for cycler in cyclers:
		if cycler.name == origin:
			return Transport.docked_to(transport_name, cycler)
	assert(false, "origin '%s' passed validation but matches nothing" % origin)
	return null
