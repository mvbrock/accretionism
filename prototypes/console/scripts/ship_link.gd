class_name ShipLink
extends RefCounted
## The console's connection to one ship of the fleet. Disconnected, the console
## can only list ships and connect to one. Connected, every line but `disconnect`
## goes to that ship's command interpreter. `disconnect` works even while the
## ship's computer is down, since the link is the console's, not the ship's.

const NOT_CONNECTED := "not connected to a ship; type 'ships list' to see them, 'ships connect <ship name>' to connect"

var fleet: Fleet
## The connected ship's name; empty when disconnected.
var ship_name := ""


func _init(fleet_to_link: Fleet) -> void:
	fleet = fleet_to_link


## The connected ship, or null.
func ship() -> Ship:
	return fleet.ships.get(ship_name)


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
		var left := ship_name
		ship_name = ""
		return "disconnected from " + left
	if words[0] == "ships":
		return "connected to %s; type 'disconnect' first" % ship_name
	var response := CommandInterpreter.run(ship(), line)
	if words.size() == 1 and words[0] == "help" and CommandInterpreter.computer_refusal(ship(), "help") == "":
		response += "\ndisconnect — Disconnect from %s" % ship_name
	return response
