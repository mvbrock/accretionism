class_name Ship
extends RefCounted
## The whole ship: rooms, openings, breakers, systems and tanks, stepped at a
## fixed rate. Build one with ShipLoader.

const STEP_S := 0.1
const SYSTEM_IDS: Array[String] = ["pressure-control", "hvac", "air-recycler", "computer"]
## Float residue from summing steps must not cost a whole step.
const _STEP_EPSILON := 1e-9

var rooms: Array[Room] = []
var openings: Array[Opening] = []
var power: PowerPanel
var systems: Dictionary = {}  # system id -> SystemUnit
var tanks: Dictionary = {}  # "O2" / "N2" -> Tank
var light_switches: Dictionary = {}  # room id -> bool
var exposed: Dictionary = {}  # room id -> bool
var params: Dictionary = {}  # the data file's sections as loaded
## Sim seconds elapsed; derived from the step count so float error never accumulates.
var time_s: float:
	get:
		return _steps * STEP_S
var events := EventLog.new()
var last_hvac_w: Dictionary = {}  # room id -> W
var recycler_scrubbing := false

var _pending_s := 0.0
var _steps := 0
var _tank_was_empty: Dictionary = {}  # gas -> bool
var _setpoints_pa: Dictionary = {}
var _setpoint_k := 0.0
var _hull_k := 0.0


func _init(data: Dictionary, ship_rooms: Array[Room], ship_openings: Array[Opening]) -> void:
	params = data
	rooms = ship_rooms
	openings = ship_openings
	power = PowerPanel.new(int(data.seed), float(data.breakers.mean_time_between_trips_h) * 3600.0)
	for id in SYSTEM_IDS:
		var section: Dictionary = data[id.replace("-", "_")]
		systems[id] = SystemUnit.new(id, float(section.boot_s))
	for gas in data.tanks:
		var entry: Dictionary = data.tanks[gas]
		tanks[gas] = Tank.new(gas, float(entry.capacity_mol), float(entry.start_mol))
		_tank_was_empty[gas] = false
	for room in rooms:
		light_switches[room.id] = true
		last_hvac_w[room.id] = 0.0
	_setpoints_pa = {"O2": data.setpoints.o2_kpa * 1000.0, "N2": data.setpoints.n2_kpa * 1000.0}
	_setpoint_k = Units.kelvin(data.setpoints.temperature_c)
	_hull_k = Units.kelvin(data.heat.hull_temperature_c)
	exposed = _compute_exposed()


func room(id: String) -> Room:
	for candidate in rooms:
		if candidate.id == id:
			return candidate
	return null


func opening(id: String) -> Opening:
	for candidate in openings:
		if candidate.id == id:
			return candidate
	return null


func light_lit(room_id: String) -> bool:
	return light_switches[room_id] and power.is_powered("light-" + room_id)


## The command methods below expect known ids; the command interpreter validates them.
func set_opening(id: String, want_open: bool) -> Dictionary:
	var target := opening(id)
	var hatch_passing := opening("hatch").passes()
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
	if breaker_id.begins_with("light-"):
		return draw.light if light_lit(breaker_id.trim_prefix("light-")) else 0.0
	match breaker_id:
		"pressure-control":
			return draw.pressure_control if systems[breaker_id].state != SystemUnit.State.NO_POWER else 0.0
		"hvac":
			var total: float = draw.hvac_base
			for room_id in last_hvac_w:
				total += absf(last_hvac_w[room_id])
			return total
		"air-recycler":
			return draw.air_recycler_scrubbing if recycler_scrubbing else draw.air_recycler_idle
	var moving := opening(breaker_id).state in [Opening.State.OPENING, Opening.State.CLOSING]
	var prefix := "hatch" if breaker_id == "hatch" else "door"
	return draw["%s_moving" % prefix] if moving else draw["%s_idle" % prefix]


func computer_draw_w() -> float:
	return params.breakers.draw_w.computer


func total_draw_w() -> float:
	var total := computer_draw_w()
	for id in PowerPanel.BREAKER_IDS:
		total += draw_w(id)
	return total


func set_light(room_id: String, on: bool) -> bool:
	if light_switches[room_id] == on:
		return false
	light_switches[room_id] = on
	return true


func restart_system(id: String) -> SystemUnit.RestartResult:
	return systems[id].restart(_system_powered(id))


func breaker_reset(id: String) -> bool:
	return power.reset(id)


func breaker_trip(id: String) -> bool:
	return power.trip(id)


func fault_system(id: String) -> bool:
	return systems[id].fault()


## Runs as many whole steps as `sim_seconds` holds, carrying the rest to the next call.
## Returns the steps run.
func advance(sim_seconds: float) -> int:
	_pending_s += maxf(sim_seconds, 0.0)
	var steps := int(floor(_pending_s / STEP_S + _STEP_EPSILON))
	_pending_s -= steps * STEP_S
	for i in steps:
		step()
	return steps


func step() -> void:
	for id in power.roll_random_trips(STEP_S):
		events.add(time_s, "%s: breaker tripped" % id, EventLog.Level.WARNING)
	for id in SYSTEM_IDS:
		if systems[id].step(STEP_S, _system_powered(id)):
			events.add(time_s, "%s: %s" % [id, _state_text(systems[id].state)],
					EventLog.Level.WARNING if systems[id].state != SystemUnit.State.RUNNING else EventLog.Level.INFO)
	for opening_ in openings:
		opening_.step(STEP_S, power.is_powered(opening_.id))
	_update_exposure()
	for opening_ in openings:
		if not opening_.is_hatch():
			Atmosphere.flow_through_door(room(opening_.room_a), room(opening_.room_b), opening_, STEP_S)
	for opening_ in openings:
		if opening_.is_hatch():
			Atmosphere.vent_through_hatch(room(opening_.room_a), opening_, STEP_S)
	_breathe()
	_run_pressure_control()
	_run_recycler()
	_log_empty_tanks()
	_apply_heat()
	_steps += 1


func _system_powered(id: String) -> bool:
	return id == "computer" or power.is_powered(id)


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


func _breathe() -> void:
	for r in rooms:
		LifeSupport.breathe(r, params.crew.o2_mol_s, params.crew.co2_mol_s, STEP_S)


func _run_pressure_control() -> void:
	if not systems["pressure-control"].is_running():
		return
	for r in rooms:
		LifeSupport.pressure_control(r, exposed[r.id], tanks, _setpoints_pa,
				params.pressure_control.max_mol_s, STEP_S)


func _run_recycler() -> void:
	recycler_scrubbing = false
	if not systems["air-recycler"].is_running():
		return
	var section: Dictionary = params.air_recycler
	for r in rooms:
		var removed := LifeSupport.recycle(r, exposed[r.id], tanks["O2"],
				params.setpoints.co2_max_kpa * 1000.0, section.min_pressure_kpa * 1000.0,
				section.max_mol_s, STEP_S)
		if removed > 0.0:
			recycler_scrubbing = true


func _log_empty_tanks() -> void:
	for gas in tanks:
		var is_empty: bool = tanks[gas].mol <= 0.0
		if is_empty and not _tank_was_empty[gas]:
			events.add(time_s, "%s tank empty" % gas, EventLog.Level.DANGER)
		_tank_was_empty[gas] = is_empty


func _apply_heat() -> void:
	var hvac_running: bool = systems["hvac"].is_running()
	for r in rooms:
		var watts: float = r.crew * params.heat.crew_w
		if light_lit(r.id):
			watts += params.heat.light_w
		var hvac_w := 0.0
		if hvac_running:
			hvac_w = LifeSupport.hvac_heat_w(r, _setpoint_k, params.hvac.gain_w_per_k, params.hvac.max_w)
		last_hvac_w[r.id] = hvac_w
		Atmosphere.add_heat(r, (watts + hvac_w) * STEP_S)
		Atmosphere.hull_loss(r, _hull_k, STEP_S)
