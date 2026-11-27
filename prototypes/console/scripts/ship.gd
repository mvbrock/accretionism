class_name Ship
extends RefCounted
## The whole ship: rooms, openings, breakers, systems and tanks, stepped at a
## fixed rate. This is the base class: a ship type extends it and overrides
## `_build` to lay out its rooms and doors with `add_room`, `add_door` and `add_hatch`.
## Every tuning number is in `params`, filled from `default_params()`; a subclass
## overrides some by returning them from `_param_overrides`, and a caller by passing
## `overrides` to `new`. Both are deep-merged: Dictionaries merge, everything else replaces.

const STEP_S := 0.1
## One-way link time unless `params.transmission_s` says otherwise: 8 minutes.
const DEFAULT_TRANSMISSION_S := 480.0
const COMPUTER_ID := "computer"
## The systems that have a breaker. The computer has none.
const SYSTEM_BREAKER_IDS: Array[String] = ["pressure-control", "hvac", "air-recycler"]
## A breaker id with this prefix is a room light's.
const LIGHT_BREAKER_PREFIX := "light-"
## Float residue from summing steps must not cost a whole step.
const _STEP_EPSILON := 1e-9
## A room's walls, floor and ceiling can each carry a door, no more.
const MAX_DOORS_PER_ROOM := 6
## A door's size (width, height) in metres. The reference door, 1 x 2 m, passes the numbers below;
## a door of another area passes in proportion.
const DOOR_SIZE_M := Vector2(1.0, 2.0)
## Hatches are not scaled by size; this is only how big one is drawn.
const HATCH_SIZE_M := Vector2(1.0, 1.0)
const DOOR_TRAVEL_S := 2.0
const DOOR_CONDUCTANCE_M3S := 10.0
const DOOR_MIXING_M3S := 0.5
const DOOR_HEAT_W_PER_K := 100.0
const HATCH_TRAVEL_S := 6.0
const HATCH_CONDUCTANCE_M3S := 5.0
## The defaults were tuned for a ship of this much air. A bigger ship's tanks and pressure control
## grow with its total volume, and each room's HVAC with that room's volume against the largest
## room the defaults were tuned for. Smaller ones keep the defaults.
const REFERENCE_SHIP_VOLUME_M3 := 82.0
const REFERENCE_ROOM_VOLUME_M3 := 40.0

## Every system, the computer last.
static var SYSTEM_IDS: Array[String] = _system_ids()

var rooms: Array[Room] = []
var openings: Array[Opening] = []
var power: PowerPanel
var systems: Dictionary = {}  # system id -> SystemUnit
var tanks: Dictionary = {}  # "O2" / "N2" -> Tank
var light_switches: Dictionary = {}  # room id -> bool
var exposed: Dictionary = {}  # room id -> bool
var params: Dictionary = {}  # default_params() with the subclass's and caller's overrides merged in
## Sim seconds elapsed; derived from the step count so float error never accumulates.
var time_s: float:
	get:
		return _steps * STEP_S
## Sim seconds a command or reply takes to cross the link to this ship, one way.
var transmission_s := DEFAULT_TRANSMISSION_S
var events := EventLog.new()
var last_hvac_w: Dictionary = {}  # room id -> W
var recycler_scrubbing := false

var _pending_s := 0.0
var _steps := 0
var _tank_was_empty: Dictionary = {}  # gas -> bool
var _setpoints_pa: Dictionary = {}
var _setpoint_k := 0.0
var _hull_k := 0.0
var _pressure_control_max_mol_s := 0.0
var _hvac_scale: Dictionary = {}  # room id -> factor on the HVAC's gain and max watts
var _unplaced: Array[Opening] = []  # openings that take the centre of their face once the rooms exist
var _rooms_by_id: Dictionary = {}  # room id -> Room, so step() finds a door's rooms without a scan
var _light_breakers: Dictionary = {}  # room id -> its light's breaker id
var _passing: Array[bool] = []  # each opening's passes() when exposure was last worked out


func _init(overrides := {}) -> void:
	params = default_params()
	merge_params(params, _param_overrides())
	merge_params(params, overrides)
	transmission_s = float(params.transmission_s)
	_build()
	for room_ in rooms:
		_rooms_by_id[room_.id] = room_
	_check_doors()
	_place_openings()
	power = PowerPanel.new(int(params.seed), float(params.breakers.mean_time_between_trips_h) * 3600.0,
			_breaker_ids())
	for id in SYSTEM_IDS:
		var section: Dictionary = params[id.replace("-", "_")]
		systems[id] = SystemUnit.new(id, float(section.boot_s))
	var ship_scale := maxf(1.0, _total_volume() / REFERENCE_SHIP_VOLUME_M3)
	for gas in params.tanks:
		var entry: Dictionary = params.tanks[gas]
		tanks[gas] = Tank.new(gas, float(entry.capacity_mol) * ship_scale, float(entry.start_mol) * ship_scale)
		_tank_was_empty[gas] = false
	_pressure_control_max_mol_s = float(params.pressure_control.max_mol_s) * ship_scale
	for room_ in rooms:
		light_switches[room_.id] = true
		_light_breakers[room_.id] = light_breaker_id(room_.id)
		last_hvac_w[room_.id] = 0.0
		# Gain scales with max watts, or a big room's hull loss would leave it a few degrees cold.
		_hvac_scale[room_.id] = maxf(1.0, room_.volume / REFERENCE_ROOM_VOLUME_M3)
	_setpoints_pa = {"O2": params.setpoints.o2_kpa * 1000.0, "N2": params.setpoints.n2_kpa * 1000.0}
	_setpoint_k = Units.kelvin(params.setpoints.temperature_c)
	_hull_k = Units.kelvin(params.heat.hull_temperature_c)
	exposed = _compute_exposed()


## Where a ship type lays out its rooms and doors. Override it and call `add_room`, `add_door`
## and `add_hatch`; rooms may be added after the doors that name them.
func _build() -> void:
	pass


## The params this ship type changes from `default_params()`, as a partial Dictionary.
func _param_overrides() -> Dictionary:
	return {}


## A room: `size_m` (x width, y height, z length) in metres, centred at `position` in ship space,
## turned by `orientation` (see `yaw`). Volume is size.x * size.y * size.z. It starts at the
## `params.start` air. Returns the room, or null (and an error naming the id) if the id is taken.
func add_room(id: String, size_m: Vector3, position: Vector3, orientation := Basis.IDENTITY,
		passengers := 0) -> Room:
	if room(id) != null:
		push_error("Room '%s' already exists" % id)
		return null
	var start: Dictionary = params.start
	var room_ := Room.new(id, size_m.x * size_m.y * size_m.z, Units.kelvin(start.temperature_c), passengers)
	room_.size = size_m
	room_.position = position
	room_.orientation = orientation
	room_.heat_capacity = params.heat.capacity_j_per_k_m3 * room_.volume
	room_.hull_conductance = params.heat.hull_w_per_k_m3 * room_.volume
	room_.set_partial_pressure("O2", start.o2_kpa * 1000.0)
	room_.set_partial_pressure("N2", start.n2_kpa * 1000.0)
	room_.set_partial_pressure("CO2", start.co2_kpa * 1000.0)
	rooms.append(room_)
	_rooms_by_id[id] = room_
	return room_


## A door between two rooms, on `face_a` of `room_a` and `face_b` of `room_b` (each face in
## that room's own frame). It is `size_m` (width, height) and centred at `at`, a point in ship
## space; by default at the centre of `room_a`'s face. Conductance, mixing and heat conductance
## scale with its area against the reference door `DOOR_SIZE_M`. Two doors may share a face. A
## room has at most MAX_DOORS_PER_ROOM doors; one more is an error naming the room, and nothing
## is added (returns null). So is a taken id.
func add_door(id: String, room_a: String, face_a: Room.Face, room_b: String, face_b: Room.Face,
		size_m := DOOR_SIZE_M, at: Variant = null) -> Opening:
	if id.begins_with(Opening.HATCH_PREFIX):
		push_error("Door '%s' cannot start with '%s'; that is for hatches" % [id, Opening.HATCH_PREFIX])
		return null
	var opening_ := Opening.new(id, room_a, room_b, DOOR_TRAVEL_S)
	opening_.face_a = face_a
	opening_.face_b = face_b
	opening_.size = size_m
	var scale := size_m.x * size_m.y / (DOOR_SIZE_M.x * DOOR_SIZE_M.y)
	opening_.conductance = DOOR_CONDUCTANCE_M3S * scale
	opening_.mixing = DOOR_MIXING_M3S * scale
	opening_.heat_conductance = DOOR_HEAT_W_PER_K * scale
	return _add_opening(opening_, at)


## An opening between `room_id` and outside, on `face` of the room, `size_m` and centred at `at`
## like a door (size only matters for drawing). Its id must start with `hatch`; a ship may have
## any number. Returns null on an error, like `add_door`.
func add_hatch(id: String, room_id: String, face: Room.Face, travel_s := HATCH_TRAVEL_S,
		conductance_m3s := HATCH_CONDUCTANCE_M3S, size_m := HATCH_SIZE_M, at: Variant = null) -> Opening:
	if not id.begins_with(Opening.HATCH_PREFIX):
		push_error("Hatch '%s' must start with '%s'" % [id, Opening.HATCH_PREFIX])
		return null
	var opening_ := Opening.new(id, room_id, Opening.OUTSIDE, travel_s)
	opening_.face_a = face
	opening_.size = size_m
	opening_.conductance = conductance_m3s
	return _add_opening(opening_, at)


## A rotation of `degrees` about the vertical (y) axis, for a room's `orientation`.
static func yaw(degrees: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(degrees))


## The openings that join this room to another room or to outside, in opening order.
func doors_of(room_id: String) -> Array[Opening]:
	var found: Array[Opening] = []
	for opening_ in openings:
		if opening_.room_a == room_id or opening_.room_b == room_id:
			found.append(opening_)
	return found


func _add_opening(opening_: Opening, at: Variant) -> Opening:
	if opening(opening_.id) != null:
		push_error("Opening '%s' already exists" % opening_.id)
		return null
	for room_id in [opening_.room_a, opening_.room_b]:
		if room_id != Opening.OUTSIDE and doors_of(room_id).size() >= MAX_DOORS_PER_ROOM:
			push_error("Room '%s' already has %d doors; '%s' would be one too many" % [
					room_id, MAX_DOORS_PER_ROOM, opening_.id])
			return null
	if at != null:
		opening_.position = at
	elif room(opening_.room_a) != null:
		opening_.position = room(opening_.room_a).face_center(opening_.face_a)
	else:
		_unplaced.append(opening_)
	openings.append(opening_)
	return opening_


## Rooms may be added after the doors that name them, so centring waits for the build to finish.
func _place_openings() -> void:
	for opening_ in _unplaced:
		var host := room(opening_.room_a)
		if host != null:
			opening_.position = host.face_center(opening_.face_a)
	_unplaced.clear()


func _total_volume() -> float:
	var total := 0.0
	for room_ in rooms:
		total += room_.volume
	return total


## Reports each opening that names a room the build never added.
func _check_doors() -> void:
	for opening_ in openings:
		for room_id in [opening_.room_a, opening_.room_b]:
			if room_id != Opening.OUTSIDE and room(room_id) == null:
				push_error("Opening '%s' joins unknown room '%s'" % [opening_.id, room_id])


## The numbers a ship runs on unless a subclass or caller changes them. Fresh each call.
static func default_params() -> Dictionary:
	return {
		"seed": 7,
		"transmission_s": DEFAULT_TRANSMISSION_S,
		"setpoints": {"o2_kpa": 21.2, "n2_kpa": 80.1, "co2_max_kpa": 0.3, "temperature_c": 21.0},
		"start": {"o2_kpa": 21.2, "n2_kpa": 80.1, "co2_kpa": 0.04, "temperature_c": 21.0},
		"heat": {"capacity_j_per_k_m3": 5000.0, "hull_w_per_k_m3": 0.5, "hull_temperature_c": -20.0,
				"passenger_w": 100.0, "light_w": 40.0},
		"passenger": {"o2_mol_s": 0.0003, "co2_mol_s": 0.00026},
		"pressure_control": {"max_mol_s": 20.0, "boot_s": 10.0},
		"hvac": {"gain_w_per_k": 5000.0, "max_w": 1500.0, "boot_s": 8.0},
		"air_recycler": {"max_mol_s": 0.01, "min_pressure_kpa": 10.0, "boot_s": 15.0},
		"computer": {"boot_s": 20.0},
		"tanks": {
			"O2": {"capacity_mol": 3000.0, "start_mol": 3000.0},
			"N2": {"capacity_mol": 8000.0, "start_mol": 8000.0},
		},
		"breakers": {
			"mean_time_between_trips_h": 24.0,
			"draw_w": {"light": 40.0, "door_idle": 5.0, "door_moving": 200.0, "hatch_idle": 5.0,
					"hatch_moving": 500.0, "pressure_control": 300.0, "hvac_base": 200.0,
					"air_recycler_scrubbing": 800.0, "air_recycler_idle": 50.0, "computer": 150.0},
		},
		"status": {
			"pressure_kpa": {"nominal": [95.0, 105.0], "danger_below": 70.0, "danger_above": null},
			"o2_kpa": {"nominal": [19.0, 23.5], "danger_below": 16.0, "danger_above": 30.0},
			"co2_kpa": {"nominal": [0.0, 0.5], "danger_below": null, "danger_above": 1.0},
			"temperature_c": {"nominal": [18.0, 26.0], "danger_below": 10.0, "danger_above": 32.0},
			"tank_percent": {"nominal": [25.0, 100.0], "danger_below": 5.0, "danger_above": null},
		},
	}


## Merges `overrides` into `into`: Dictionaries merge, everything else replaces.
static func merge_params(into: Dictionary, overrides: Dictionary) -> void:
	for key in overrides:
		if into.get(key) is Dictionary and overrides[key] is Dictionary:
			merge_params(into[key], overrides[key])
		else:
			into[key] = overrides[key]


static func _system_ids() -> Array[String]:
	var ids: Array[String] = SYSTEM_BREAKER_IDS.duplicate()
	ids.append(COMPUTER_ID)
	return ids


static func light_breaker_id(room_id: String) -> String:
	return LIGHT_BREAKER_PREFIX + room_id


## Room lights in room order, then openings in opening order, then the systems.
func _breaker_ids() -> Array[String]:
	var ids: Array[String] = []
	for room_ in rooms:
		ids.append(light_breaker_id(room_.id))
	for opening_ in openings:
		ids.append(opening_.id)
	ids.append_array(SYSTEM_BREAKER_IDS)
	return ids


func room(id: String) -> Room:
	return _rooms_by_id.get(id)


func opening(id: String) -> Opening:
	for candidate in openings:
		if candidate.id == id:
			return candidate
	return null


func light_lit(room_id: String) -> bool:
	return light_switches[room_id] and power.is_powered(light_breaker_id(room_id))


## The command methods below expect known ids; the command interpreter validates them.
func set_opening(id: String, want_open: bool) -> Dictionary:
	var target := opening(id)
	var hatch_passing := openings.any(func(o: Opening) -> bool: return o.is_hatch() and o.passes())
	var result := target.command(want_open, power.is_powered(id))
	var auto_closed: Array[String] = []
	var left_open: Array[String] = []
	var onto_open_hatch := false
	if result == Opening.CommandResult.STARTED and want_open:
		if target.is_hatch():
			_close_doors_for_hatch(auto_closed, left_open)
		elif hatch_passing:
			onto_open_hatch = true
			events.add(time_s, "%s: opened onto an open hatch" % id, EventLog.Level.WARNING)
	return {"result": result, "auto_closed": auto_closed, "left_open": left_open,
			"onto_open_hatch": onto_open_hatch}


func _close_doors_for_hatch(auto_closed: Array[String], left_open: Array[String]) -> void:
	for door in openings:
		if door.is_hatch() or not (door.passes() or door.state == Opening.State.OPENING):
			continue
		match door.command(false, power.is_powered(door.id)):
			Opening.CommandResult.NO_POWER:
				left_open.append(door.id)
				events.add(time_s, "%s: no power, left open with hatch opening" % door.id, EventLog.Level.WARNING)
			Opening.CommandResult.STARTED:
				auto_closed.append(door.id)
				events.add(time_s, "%s: closing (hatch opening)" % door.id)


func draw_w(breaker_id: String) -> float:
	if not power.is_powered(breaker_id):
		return 0.0
	var draw: Dictionary = params.breakers.draw_w
	if breaker_id.begins_with(LIGHT_BREAKER_PREFIX):
		return draw.light if light_lit(breaker_id.trim_prefix(LIGHT_BREAKER_PREFIX)) else 0.0
	match breaker_id:
		"pressure-control":
			return draw.pressure_control
		"hvac":
			var total: float = draw.hvac_base
			for room_id in last_hvac_w:
				total += absf(last_hvac_w[room_id])
			return total
		"air-recycler":
			return draw.air_recycler_scrubbing if recycler_scrubbing else draw.air_recycler_idle
	var target := opening(breaker_id)
	var moving := target.state in [Opening.State.OPENING, Opening.State.CLOSING]
	var prefix := "hatch" if target.is_hatch() else "door"
	return draw["%s_moving" % prefix] if moving else draw["%s_idle" % prefix]


func computer_draw_w() -> float:
	return params.breakers.draw_w.computer


func total_draw_w() -> float:
	var total := computer_draw_w()
	for id in power.breaker_ids:
		total += draw_w(id)
	return total


func set_light(room_id: String, on: bool) -> bool:
	if light_switches[room_id] == on:
		return false
	light_switches[room_id] = on
	return true


func add_passenger(room_id: String) -> int:
	var target := room(room_id)
	target.passengers += 1
	return target.passengers


## Returns the new count, or -1 when the room has none and nothing changed.
func remove_passenger(room_id: String) -> int:
	var target := room(room_id)
	if target.passengers == 0:
		return -1
	target.passengers -= 1
	return target.passengers


func restart_system(id: String) -> SystemUnit.RestartResult:
	return systems[id].restart(_system_powered(id))


func breaker_reset(id: String) -> bool:
	return power.reset(id)


func breaker_trip(id: String) -> bool:
	return power.trip(id)


func fault_system(id: String) -> bool:
	return systems[id].fault()


## Runs as many whole steps of `step_s` as `sim_seconds` holds, carrying the rest to the next
## call, even if that call uses a different step size. `step_s` must be a whole multiple of
## STEP_S. Returns the steps run.
func advance(sim_seconds: float, step_s := STEP_S) -> int:
	assert(step_s > 0.0 and is_equal_approx(step_s / STEP_S, roundf(step_s / STEP_S)), "step_s %s is not a whole multiple of STEP_S" % step_s)
	_pending_s += maxf(sim_seconds, 0.0)
	var steps := int(floor(_pending_s / step_s + _STEP_EPSILON))
	_pending_s -= steps * step_s
	for i in steps:
		step(step_s)
	return steps


## Runs one step of `dt` sim seconds, a whole multiple of STEP_S.
func step(dt := STEP_S) -> void:
	assert(is_equal_approx(dt / STEP_S, roundf(dt / STEP_S)), "step dt %s is not a multiple of STEP_S" % dt)
	for id in power.roll_random_trips(dt):
		events.add(time_s, "%s: breaker tripped" % id, EventLog.Level.WARNING)
	for id in SYSTEM_IDS:
		if systems[id].step(dt, _system_powered(id)):
			events.add(time_s, "%s: %s" % [id, _state_text(systems[id].state)],
					EventLog.Level.WARNING if systems[id].state != SystemUnit.State.RUNNING else EventLog.Level.INFO)
	for opening_ in openings:
		opening_.step(dt, power.is_powered(opening_.id))
	_update_exposure()
	for opening_ in openings:
		if not opening_.is_hatch():
			Atmosphere.flow_through_door(room(opening_.room_a), room(opening_.room_b), opening_, dt)
	for opening_ in openings:
		if opening_.is_hatch():
			Atmosphere.vent_through_hatch(room(opening_.room_a), opening_, dt)
	_breathe(dt)
	_run_pressure_control(dt)
	_run_recycler(dt)
	_log_empty_tanks()
	_apply_heat(dt)
	_steps += roundi(dt / STEP_S)


func _system_powered(id: String) -> bool:
	return id == COMPUTER_ID or power.is_powered(id)


func _state_text(state: SystemUnit.State) -> String:
	match state:
		SystemUnit.State.RUNNING:
			return "running"
		SystemUnit.State.BOOTING:
			return "booting"
		SystemUnit.State.FAULT:
			return "fault"
	return "no power"


func _compute_exposed() -> Dictionary:
	var ids: Array[String] = []
	for r in rooms:
		ids.append(r.id)
	return Exposure.exposed(ids, openings)


func _update_exposure() -> void:
	# Exposure only changes when an opening starts or stops passing air, so most steps skip the search.
	var changed := _passing.size() != openings.size() or exposed.size() != rooms.size()
	for i in openings.size():
		if changed:
			break
		changed = openings[i].passes() != _passing[i]
	if not changed:
		return
	_passing.resize(openings.size())
	for i in openings.size():
		_passing[i] = openings[i].passes()
	var now := _compute_exposed()
	for r in rooms:
		if now[r.id] == exposed[r.id]:
			continue
		if now[r.id]:
			events.add(time_s, "%s: exposed to vacuum" % r.id, EventLog.Level.DANGER)
			if systems["pressure-control"].is_running():
				events.add(time_s, "pressure-control: not feeding %s (exposed)" % r.id)
		else:
			events.add(time_s, "%s: sealed" % r.id)
	exposed = now


func _breathe(dt: float) -> void:
	var passenger: Dictionary = params.passenger
	for r in rooms:
		LifeSupport.breathe(r, passenger.o2_mol_s, passenger.co2_mol_s, dt)


func _run_pressure_control(dt: float) -> void:
	if not systems["pressure-control"].is_running():
		return
	for r in rooms:
		LifeSupport.pressure_control(r, exposed[r.id], tanks, _setpoints_pa,
				_pressure_control_max_mol_s, dt)


func _run_recycler(dt: float) -> void:
	recycler_scrubbing = false
	if not systems["air-recycler"].is_running():
		return
	var section: Dictionary = params.air_recycler
	for r in rooms:
		var removed := LifeSupport.recycle(r, exposed[r.id], tanks["O2"],
				params.setpoints.co2_max_kpa * 1000.0, section.min_pressure_kpa * 1000.0,
				section.max_mol_s, dt)
		if removed > 0.0:
			recycler_scrubbing = true


func _log_empty_tanks() -> void:
	for gas in tanks:
		var is_empty: bool = tanks[gas].mol <= 0.0
		if is_empty and not _tank_was_empty[gas]:
			events.add(time_s, "%s tank empty" % gas, EventLog.Level.DANGER)
		_tank_was_empty[gas] = is_empty


func _apply_heat(dt: float) -> void:
	var hvac_running: bool = systems["hvac"].is_running()
	var heat: Dictionary = params.heat
	var hvac: Dictionary = params.hvac
	for r in rooms:
		var watts: float = r.passengers * heat.passenger_w
		if light_switches[r.id] and power.is_powered(_light_breakers[r.id]):
			watts += heat.light_w
		var hvac_w := 0.0
		if hvac_running:
			hvac_w = LifeSupport.hvac_heat_w(r, _setpoint_k,
					hvac.gain_w_per_k * _hvac_scale[r.id], hvac.max_w * _hvac_scale[r.id])
		last_hvac_w[r.id] = hvac_w
		Atmosphere.add_heat(r, (watts + hvac_w) * dt)
		Atmosphere.hull_loss(r, _hull_k, dt)
