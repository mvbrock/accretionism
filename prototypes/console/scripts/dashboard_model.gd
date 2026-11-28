class_name DashboardModel
extends RefCounted
## Turns a Ship into the strings and levels the dashboard shows. Pure functions;
## this is where SI units become kPa and °C.

const NO_READING := "—"
## Below this the room has no air worth reporting a mix for.
const _VACUUM_PA := 1000.0
const _GAS_NAMES := {"O2": "O₂", "N2": "N₂", "CO2": "CO₂"}


static func gas_name(gas: String) -> String:
	return _GAS_NAMES[gas]


static func room_tile(ship: Ship, room_id: String) -> Dictionary:
	var room := ship.room(room_id)
	var in_vacuum := room.pressure() < _VACUUM_PA
	return {
		"title": room_id.to_upper(),
		"pressure": "%.1f kPa" % (room.pressure() / 1000.0),
		"temperature": "%.1f °C" % Units.celsius(room.temperature),
		"o2": NO_READING if in_vacuum else "%.1f %%" % (room.share("O2") * 100.0),
		"n2": NO_READING if in_vacuum else "%.1f %%" % (room.share("N2") * 100.0),
		"co2": NO_READING if in_vacuum else "%.2f kPa" % (room.partial_pressure("CO2") / 1000.0),
		"passengers": "passengers %d" % room.passengers,
		"lit": ship.light_lit(room_id),
		"level": room_level(ship, room_id),
	}


## The worst of the room's readings and its breakers: a tripped light or door breaker makes it a WARNING.
static func room_level(ship: Ship, room_id: String) -> Status.Level:
	var levels := _readings(ship, ship.room(room_id)).map(func(reading: Dictionary) -> int: return reading.level)
	for id in listed_breakers(ship, room_id):
		levels.append(breaker_level(ship, id))
	return Status.worst(levels)


static func system_text(ship: Ship, id: String) -> String:
	var unit: SystemUnit = ship.systems[id]
	match unit.state:
		SystemUnit.State.BOOTING:
			return "BOOT %ds" % Units.whole_seconds_left(unit.boot_left_s)
		SystemUnit.State.FAULT:
			return "FAULT"
		SystemUnit.State.NO_POWER:
			return "NO POWER"
	return "RUN"


## The room's breakers, which the BREAKERS panel lists: its light, then its doors and hatches.
static func listed_breakers(ship: Ship, room_id: String) -> Array[String]:
	var ids: Array[String] = [Ship.light_breaker_id(room_id)]
	for opening_ in ship.doors_of(room_id):
		ids.append(opening_.id)
	return ids


static func breaker_text(ship: Ship, id: String) -> String:
	if not ship.power.is_powered(id):
		return "□ TRIP"
	return "■ %d W" % roundi(ship.draw_w(id))


static func tank_percent(ship: Ship, gas: String) -> int:
	return floori(ship.tanks[gas].fraction() * 100.0)


static func tank_level(ship: Ship, gas: String) -> Status.Level:
	return Status.classify(ship.tanks[gas].fraction() * 100.0, ship.params.status.tank_percent)


static func system_level(ship: Ship, id: String) -> Status.Level:
	match ship.systems[id].state:
		SystemUnit.State.FAULT, SystemUnit.State.NO_POWER:
			return Status.Level.WARNING
	return Status.Level.NORMAL


static func breaker_level(ship: Ship, id: String) -> Status.Level:
	return Status.Level.NORMAL if ship.power.is_powered(id) else Status.Level.WARNING


static func clock_text(time_s: float) -> String:
	var whole := int(time_s)
	return "T+%02d:%02d:%02d" % [whole / 3600, whole / 60 % 60, whole % 60]


static func total_draw_text(ship: Ship) -> String:
	return "total %.1f kW" % (ship.total_draw_w() / 1000.0)


## The ship's type as the ship table shows it: its class name without `Ship`, such as `Skiff`.
static func ship_class(ship: Ship) -> String:
	return (ship.get_script() as Script).get_global_name().trim_suffix("Ship")


## The ship table's status: the worst level of every room, tank, system and breaker on the ship.
static func ship_level(ship: Ship) -> Status.Level:
	return top_alarm(ship).level


static func top_alarm(ship: Ship) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for room in ship.rooms:
		if ship.exposed[room.id]:
			candidates.append({"text": "%s EXPOSED" % room.id.to_upper(), "level": Status.Level.CRITICAL})
	for room in ship.rooms:
		for reading in _readings(ship, room):
			if reading.level != Status.Level.NORMAL:
				candidates.append({"text": "%s %s %s" % [room.id.to_upper(), reading.name, reading.direction],
						"level": reading.level})
	for gas in Units.TANK_GASES:
		var level := tank_level(ship, gas)
		if level != Status.Level.NORMAL:
			candidates.append({"text": "%s TANK LOW" % gas_name(gas), "level": level})
	for id in Ship.SYSTEM_IDS:
		var state: SystemUnit.State = ship.systems[id].state
		if state == SystemUnit.State.FAULT or state == SystemUnit.State.NO_POWER:
			candidates.append({"text": "%s %s" % [id.to_upper(), system_text(ship, id)],
					"level": Status.Level.WARNING})
	for id in ship.power.breaker_ids:
		if not ship.power.is_powered(id):
			candidates.append({"text": "BREAKER %s TRIPPED" % id, "level": Status.Level.WARNING})
	var top := {"text": "", "level": Status.Level.NORMAL}
	for candidate in candidates:
		if candidate.level > top.level:
			top = candidate
	return top


static func _readings(ship: Ship, room: Room) -> Array[Dictionary]:
	var bands: Dictionary = ship.params.status
	var values := [
		["PRESSURE", room.pressure() / 1000.0, bands.pressure_kpa],
		[gas_name("O2"), room.partial_pressure("O2") / 1000.0, bands.o2_kpa],
		[gas_name("CO2"), room.partial_pressure("CO2") / 1000.0, bands.co2_kpa],
		["TEMPERATURE", Units.celsius(room.temperature), bands.temperature_c],
	]
	var readings: Array[Dictionary] = []
	for entry in values:
		readings.append({
			"name": entry[0],
			"level": Status.classify(entry[1], entry[2]),
			"direction": "LOW" if entry[1] < float(entry[2].normal[0]) else "HIGH",
		})
	return readings
