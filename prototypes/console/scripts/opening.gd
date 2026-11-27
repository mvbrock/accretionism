class_name Opening
extends RefCounted
## A door between two rooms, or a hatch between a room and outside. It moves
## at a fixed speed while powered and holds where it is without power.

enum State { CLOSED, OPENING, OPEN, CLOSING }
enum CommandResult { STARTED, ALREADY, NO_POWER }

const OUTSIDE := "outside"
## Every hatch's id starts with this.
const HATCH_PREFIX := "hatch"
## The id of the one hatch on a ship that has just one (and what ShipLoader requires).
const HATCH_ID := HATCH_PREFIX
const END_SNAP := 1e-9  # float drift from repeated dt / travel_s steps is snapped to the end

var id: String
var room_a: String
var room_b: String  # OUTSIDE for a hatch
## The face of room_a the opening sits on, in that room's frame.
var face_a := Room.Face.PLUS_Z
## The face of room_b it sits on; unused for a hatch.
var face_b := Room.Face.MINUS_Z
## Where the opening's centre is, in ship space. Neighbouring rooms meet at a door, so one point
## serves both faces.
var position := Vector3.ZERO
## The opening's width and height in metres, for drawing it and for how much it passes.
var size := Vector2.ZERO
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


func passes() -> bool:
	return fraction > 0.0


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
		fraction += dt / travel_s
		if fraction >= 1.0 - END_SNAP:
			fraction = 1.0
			state = State.OPEN
	elif state == State.CLOSING:
		fraction -= dt / travel_s
		if fraction <= END_SNAP:
			fraction = 0.0
			state = State.CLOSED


func seconds_to_finish() -> float:
	match state:
		State.OPENING:
			return (1.0 - fraction) * travel_s
		State.CLOSING:
			return fraction * travel_s
	return 0.0
