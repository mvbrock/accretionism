class_name ShipChecks
extends RefCounted
## Checks the ship-type tests share. Each returns a list of what is wrong, empty when all is well,
## so a test can assert it is empty and see every problem in one message.

## Overrides that switch random breaker trips off, so a long run is not cut short.
const NO_TRIPS := {"breakers": {"mean_time_between_trips_h": 0.0}}
const _BANDS: Array[String] = ["pressure_kpa", "o2_kpa", "co2_kpa", "temperature_c"]
## A ship's steady state must hold for a day of sim time.
const STEADY_STATE_S := 86400.0
const _DOOR_SETTLE_S := 3.0
const _HATCH_SETTLE_S := 7.0
const _MAX_DOOR_BEND := PI / 6.0


static func room_ids(ship: Ship) -> Array[String]:
	var ids: Array[String] = []
	for room in ship.rooms:
		ids.append(room.id)
	return ids


static func door_ids(ship: Ship) -> Array[String]:
	var ids: Array[String] = []
	for opening in ship.openings:
		if not opening.is_hatch():
			ids.append(opening.id)
	return ids


static func hatches(ship: Ship) -> Array[Opening]:
	var found: Array[Opening] = []
	for opening in ship.openings:
		if opening.is_hatch():
			found.append(opening)
	return found


## Rooms that cannot be reached from the first room through doors (hatches lead outside).
static func unreachable_rooms(ship: Ship) -> Array[String]:
	var reached := {ship.rooms[0].id: true}
	var frontier: Array[String] = [ship.rooms[0].id]
	while not frontier.is_empty():
		var here: String = frontier.pop_back()
		for door in ship.doors_of(here):
			if door.is_hatch():
				continue
			var other := door.room_b if door.room_a == here else door.room_a
			if not reached.has(other):
				reached[other] = true
				frontier.append(other)
	var missing: Array[String] = []
	for room in ship.rooms:
		if not reached.has(room.id):
			missing.append(room.id)
	return missing


## Openings whose position is not on the face of each room they name, and doors whose two faces
## do not face each other. A ring's segments turn by 30 degrees at each door, so that much is allowed.
static func misplaced_doors(ship: Ship) -> Array[String]:
	var found: Array[String] = []
	for door in ship.openings:
		if not door.is_hatch():
			var normal_a := ship.room(door.room_a).face_normal(door.face_a)
			var normal_b := ship.room(door.room_b).face_normal(door.face_b)
			if normal_a.angle_to(-normal_b) > _MAX_DOOR_BEND + 1e-4:
				found.append("%s faces" % door.id)
		var sides: Array = [[door.room_a, door.face_a]]
		if not door.is_hatch():
			sides.append([door.room_b, door.face_b])
		for side in sides:
			if not ship.room(side[0]).face_contains(side[1], door.position):
				found.append("%s on %s" % [door.id, side[0]])
	return found


static func open_all_doors(ship: Ship) -> void:
	for opening in ship.openings:
		if not opening.is_hatch():
			ship.set_opening(opening.id, true)
	ship.advance(_DOOR_SETTLE_S)


## Doors open, hatches shut, one day at `step_s`: every room must stay inside the nominal bands.
static func steady_state_problems(ship: Ship, step_s: float) -> Array[String]:
	open_all_doors(ship)
	ship.advance(STEADY_STATE_S, step_s)
	var problems: Array[String] = []
	for opening in ship.openings:
		var wanted := Opening.State.CLOSED if opening.is_hatch() else Opening.State.OPEN
		if opening.state != wanted:
			problems.append("%s is not %s" % [opening.id, "closed" if opening.is_hatch() else "open"])
	for room in ship.rooms:
		var readings := {
			"pressure_kpa": room.pressure() / 1000.0,
			"o2_kpa": room.partial_pressure("O2") / 1000.0,
			"co2_kpa": room.partial_pressure("CO2") / 1000.0,
			"temperature_c": Units.celsius(room.temperature),
		}
		for band in _BANDS:
			if Status.classify(readings[band], ship.params.status[band]) != Status.Level.NOMINAL:
				problems.append("%s %s %.3f" % [room.id, band, readings[band]])
	return problems


## Opens every door and the hatch, then steps `seconds` at `step_s`. Reports a room with negative
## moles, and the vented room's pressure rising.
static func venting_problems(ship: Ship, hatch_id: String, step_s: float, seconds: float) -> Array[String]:
	open_all_doors(ship)
	var vented := ship.room(ship.opening(hatch_id).room_a)
	ship.set_opening(hatch_id, true)
	var problems: Array[String] = []
	var pressure := vented.pressure()
	for i in int(seconds / step_s):
		ship.step(step_s)
		for room in ship.rooms:
			for gas in Units.GASES:
				if room.mol[gas] < 0.0:
					problems.append("%s %s mol %.6f at %.1f s" % [room.id, gas, room.mol[gas], ship.time_s])
		if vented.pressure() > pressure + 1.0:
			problems.append("%s pressure rose from %.1f to %.1f Pa at %.1f s" % [
					vented.id, pressure, vented.pressure(), ship.time_s])
		pressure = vented.pressure()
		if not problems.is_empty():
			break
	return problems


## Opens every door and the hatch, then reports unless only the hatch's room is exposed and every
## door has closed.
static func hatch_seal_problems(ship: Ship, hatch_id: String, step_s := Ship.STEP_S) -> Array[String]:
	open_all_doors(ship)
	ship.set_opening(hatch_id, true)
	ship.advance(_HATCH_SETTLE_S, step_s)
	var hatch_room := ship.opening(hatch_id).room_a
	var problems: Array[String] = []
	for room in ship.rooms:
		if ship.exposed[room.id] != (room.id == hatch_room):
			problems.append("%s exposed is %s" % [room.id, ship.exposed[room.id]])
	for opening in ship.openings:
		if not opening.is_hatch() and opening.state != Opening.State.CLOSED:
			problems.append("%s did not auto-close" % opening.id)
	return problems


## Every way the ship's rooms and doors are mis-shaped: unreachable rooms and doors off their faces.
static func shape_problems(ship: Ship) -> Array[String]:
	var problems: Array[String] = []
	for room_id in unreachable_rooms(ship):
		problems.append("unreachable: %s" % room_id)
	for door_id in misplaced_doors(ship):
		problems.append("off its face: %s" % door_id)
	return problems
