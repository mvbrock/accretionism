class_name Opening
extends RefCounted
## A door between two rooms, or the hatch between a room and outside. It moves
## at a fixed speed while powered and holds where it is without power.

enum State { CLOSED, OPENING, OPEN, CLOSING }
enum CommandResult { STARTED, ALREADY, NO_POWER }

const OUTSIDE := "outside"

var id: String
var room_a: String
var room_b: String  # OUTSIDE for the hatch
var travel_s: float
var fraction := 0.0  # 0 closed, 1 fully open
var state := State.CLOSED
var conductance := 0.0  # m3/s, set by the loader
var mixing := 0.0  # m3/s, set by the loader
var heat_conductance := 0.0  # W/K, set by the loader


func _init(opening_id: String, a: String, b: String, travel_time_s: float) -> void:
	id = opening_id
	room_a = a
	room_b = b
	travel_s = travel_time_s


func is_hatch() -> bool:
	return room_b == OUTSIDE


## True while any gas can pass.
func passes() -> bool:
	return fraction > 0.0


## Asks the opening to head for open or closed. A moving opening reverses from
## where it is. Without power nothing changes.
func command(want_open: bool, powered: bool) -> CommandResult:
	if not powered:
		return CommandResult.NO_POWER
	var heading_there := (state == State.OPEN or state == State.OPENING) if want_open \
			else (state == State.CLOSED or state == State.CLOSING)
	if heading_there:
		return CommandResult.ALREADY
	state = State.OPENING if want_open else State.CLOSING
	return CommandResult.STARTED


func step(dt: float, powered: bool) -> void:
	if not powered:
		return
	if state == State.OPENING:
		fraction = minf(fraction + dt / travel_s, 1.0)
		if fraction >= 1.0:
			state = State.OPEN
	elif state == State.CLOSING:
		fraction = maxf(fraction - dt / travel_s, 0.0)
		if fraction <= 0.0:
			state = State.CLOSED


## Seconds left to reach the current target; 0 when not moving.
func seconds_to_finish() -> float:
	match state:
		State.OPENING:
			return (1.0 - fraction) * travel_s
		State.CLOSING:
			return fraction * travel_s
	return 0.0
