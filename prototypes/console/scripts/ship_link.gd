class_name ShipLink
extends RefCounted
## The console's connection to one ship of the fleet. Disconnected, the console
## can only list ships and connect to one. Connected, `ships`, `disconnect` and
## `help` are answered by the console at once; every other line is sent to that
## ship's command interpreter. It takes the ship's `transmission_s` to arrive, runs
## then, and its reply takes as long to come back. One line is in flight at a time.
## `disconnect` works even while the ship's computer is down, since the link is the
## console's, not the ship's.

const NOT_CONNECTED := "not connected to a ship; type 'ships list' to see them, 'ships connect <ship name>' to connect"

enum Phase { IDLE, UPLINK, DOWNLINK }

var fleet: Fleet
## The connected ship's name; empty when disconnected.
var ship_name := ""

var _phase := Phase.IDLE
var _line := ""
var _reply := ""
var _now_s := 0.0
var _leg_start_s := 0.0
var _leg_end_s := 0.0


func _init(fleet_to_link: Fleet) -> void:
	fleet = fleet_to_link


## The connected ship, or null.
func ship() -> Ship:
	return fleet.ships.get(ship_name)


## Advances every ship by `sim_seconds`, running a landing command on its ship at
## the landing time. Returns the replies that landed.
func advance(sim_seconds: float, step_s := Ship.STEP_S) -> PackedStringArray:
	var replies := PackedStringArray()
	var end_s := _now_s + sim_seconds
	while _phase != Phase.IDLE and _leg_end_s <= end_s + Units.SECONDS_EPSILON:
		var landing_s := maxf(_leg_end_s, _now_s)
		fleet.advance(landing_s - _now_s, step_s)
		_now_s = landing_s
		if _phase == Phase.UPLINK:
			_reply = _run_on_ship(_line)
			_start_leg(Phase.DOWNLINK)
		else:
			replies.append(_reply)
			_phase = Phase.IDLE
			_line = ""
			_reply = ""
	fleet.advance(end_s - _now_s, step_s)
	_now_s = end_s
	return replies


func in_flight() -> bool:
	return _phase != Phase.IDLE


## The line being sent or answered; empty when nothing is in flight.
func line() -> String:
	return _line


func uplink_active() -> bool:
	return _phase == Phase.UPLINK


func uplink_fraction() -> float:
	return _fraction(Phase.UPLINK)


func uplink_left_s() -> float:
	return _left_s(Phase.UPLINK)


func downlink_active() -> bool:
	return _phase == Phase.DOWNLINK


func downlink_fraction() -> float:
	return _fraction(Phase.DOWNLINK)


func downlink_left_s() -> float:
	return _left_s(Phase.DOWNLINK)


func run(line: String) -> String:
	var words := CommandInterpreter.words(line)
	if words.is_empty():
		return ""
	if ship_name == "":
		return _respond_disconnected(words)
	return _respond_connected(words, line)


func _respond_disconnected(words: PackedStringArray) -> String:
	match words[0]:
		"help":
			return "\n".join([
				"ships list — List the ships",
				"ships connect <%s> — Connect to that ship" % "|".join(fleet.names()),
			])
		"ships":
			return _ships(words)
		"disconnect":
			return "not connected to a ship"
	return NOT_CONNECTED


func _ships(words: PackedStringArray) -> String:
	var sub := words[1] if words.size() > 1 else ""
	if sub == "list" and words.size() == 2:
		return "ships: " + ", ".join(fleet.names())
	if sub == "connect" and words.size() == 3:
		if not fleet.ships.has(words[2]):
			return "unknown ship '%s'. Ships: %s" % [words[2], ", ".join(fleet.names())]
		ship_name = words[2]
		return "connected to " + ship_name
	if sub == "connect":
		return "usage: ships connect <%s>" % "|".join(fleet.names())
	return "usage: ships list | ships connect <ship name>"


func _respond_connected(words: PackedStringArray, line: String) -> String:
	if words[0] == "disconnect":
		if words.size() != 1:
			return "usage: disconnect"
		if in_flight():
			return "waiting on '%s'; disconnect when the reply is in" % _line
		var left := ship_name
		ship_name = ""
		return "disconnected from " + left
	if words[0] == "ships":
		return "connected to %s; type 'disconnect' first" % ship_name
	if words.size() == 1 and words[0] == "help":
		return CommandInterpreter.help_text(ship()) + "\ndisconnect — Disconnect from %s" % ship_name
	if in_flight():
		return "waiting on '%s'; one command at a time" % _line
	_line = line.strip_edges()
	_start_leg(Phase.UPLINK)
	return "sent to %s; reply in %s" % [ship_name, Units.duration_text(2.0 * ship().transmission_s)]


## Runs on the ship as the uplink lands. The computer's refusal is the reply.
func _run_on_ship(line: String) -> String:
	var words := CommandInterpreter.words(line)
	var refusal := CommandInterpreter.computer_refusal(ship(), " ".join(words.slice(0, 2)))
	if refusal != "":
		return refusal + "; 'disconnect' also works"
	return CommandInterpreter.run(ship(), line)


func _start_leg(phase: Phase) -> void:
	_phase = phase
	_leg_start_s = _now_s
	_leg_end_s = _now_s + ship().transmission_s


func _fraction(leg: Phase) -> float:
	if _phase == Phase.IDLE or (leg == Phase.DOWNLINK and _phase == Phase.UPLINK):
		return 0.0
	if _phase != leg or _leg_end_s <= _leg_start_s:
		return 1.0
	return clampf((_now_s - _leg_start_s) / (_leg_end_s - _leg_start_s), 0.0, 1.0)


func _left_s(leg: Phase) -> float:
	return maxf(_leg_end_s - _now_s, 0.0) if _phase == leg else 0.0
