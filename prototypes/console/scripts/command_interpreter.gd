class_name CommandInterpreter
extends RefCounted
## Turns one typed line into calls on the Ship and one response line. Echo and
## response belong to the console; the Ship's own events are the only log entries.


static var _WHITESPACE := _compile_whitespace()


static func _compile_whitespace() -> RegEx:
	var regex := RegEx.new()
	regex.compile("\\s+")
	return regex


## Whether a line of input can spell the id: the line is lowercased and split on whitespace.
static func is_typeable(id: String) -> bool:
	return not id.is_empty() and id == id.to_lower() and _WHITESPACE.search(id) == null


## The line lowercased and split on whitespace.
static func words(line: String) -> PackedStringArray:
	return _WHITESPACE.sub(line.to_lower(), " ", true).split(" ", false)


static func run(ship: Ship, line: String) -> String:
	var line_words := words(line)
	if line_words.is_empty():
		return ""
	return _respond(ship, line_words)


## Why the computer won't take the command `key` right now; empty when it will.
static func computer_refusal(ship: Ship, key: String) -> String:
	var computer := ship.systems[Ship.COMPUTER_ID] as SystemUnit
	if computer.state == SystemUnit.State.BOOTING:
		return "computer: rebooting; try again in %d s" % Units.whole_seconds_left(computer.boot_left_s)
	if computer.state == SystemUnit.State.FAULT and key != "computer restart":
		return "computer: fault; only 'computer restart' works"
	return ""


static func _respond(ship: Ship, words: PackedStringArray) -> String:
	var commands := _build_commands(ship)
	var key := " ".join(words.slice(0, 2))
	if not commands.has(key) and commands.has(words[0]):
		key = words[0]
	var arg_count := words.size() - key.count(" ") - 1
	var refusal := computer_refusal(ship, key)
	if refusal != "":
		return refusal
	if not commands.has(key):
		return "unknown command '%s'. Type 'help' for commands" % " ".join(words.slice(0, 2))
	var command: Dictionary = commands[key]
	if arg_count != command.args:
		return "usage: " + command.usage
	return command.handler.call(ship, words.slice(words.size() - arg_count))


## The usage lines list the ship's own door and room ids.
static func _build_commands(ship: Ship) -> Dictionary:
	var doors := "<%s>" % "|".join(_opening_ids(ship))
	var rooms := "<%s>" % "|".join(_room_ids(ship))
	var commands := {}
	_add(commands, "door open", "door open " + doors, "Start opening", 1, _door_open)
	_add(commands, "door close", "door close " + doors, "Start closing", 1, _door_close)
	_add(commands, "light on", "light on " + rooms, "Switch that room's light on", 1, _light_on)
	_add(commands, "light off", "light off " + rooms, "Switch it off", 1, _light_off)
	_add(commands, "passenger add", "passenger add " + rooms, "Add a passenger to that room", 1, _passenger_add)
	_add(commands, "passenger remove", "passenger remove " + rooms, "Remove a passenger from that room", 1, _passenger_remove)
	_add(commands, "pressure-control restart", "pressure-control restart", "Reboot pressure control", 0, _restart.bind("pressure-control"))
	_add(commands, "hvac restart", "hvac restart", "Reboot the HVAC", 0, _restart.bind("hvac"))
	_add(commands, "air-recycler restart", "air-recycler restart", "Reboot the recycler", 0, _restart.bind("air-recycler"))
	_add(commands, "computer restart", "computer restart", "Reboot the computer", 0, _restart.bind(Ship.COMPUTER_ID))
	_add(commands, "breaker reset", "breaker reset <breaker ID>", "Close a tripped breaker", 1, _breaker_reset)
	_add(commands, "help", "help", "List the commands", 0, _help)
	_add(commands, "debug trip", "debug trip <breaker ID>", "Trip a breaker", 1, _debug_trip)
	_add(commands, "debug fault", "debug fault <system>", "Put a system in FAULT", 1, _debug_fault)
	return commands


static func _add(commands: Dictionary, key: String, usage: String, effect: String, args: int, handler: Callable) -> void:
	commands[key] = {"usage": usage, "effect": effect, "args": args, "handler": handler}


static func _help(ship: Ship, _args: PackedStringArray) -> String:
	return help_text(ship)


## One line per command. Unlike `run`, it never waits on the ship's computer.
static func help_text(ship: Ship) -> String:
	var lines := PackedStringArray()
	var commands := _build_commands(ship)
	for key in commands:
		lines.append("%s — %s" % [commands[key].usage, commands[key].effect])
	return "\n".join(lines)


static func _door_open(ship: Ship, args: PackedStringArray) -> String:
	return _door(ship, args[0], true)


static func _door_close(ship: Ship, args: PackedStringArray) -> String:
	return _door(ship, args[0], false)


static func _door(ship: Ship, id: String, want_open: bool) -> String:
	var door := ship.opening(id)
	if door == null:
		return "unknown door '%s'. Doors: %s" % [id, ", ".join(_opening_ids(ship))]
	var outcome := ship.set_opening(id, want_open)
	match outcome.result:
		Opening.CommandResult.NO_POWER:
			return "%s: no power (breaker tripped)" % id
		Opening.CommandResult.ALREADY:
			return "%s: already %s" % [id, _state_word(door.state)]
	var response := "%s: %s (%d s)" % [id, "opening" if want_open else "closing", Units.whole_seconds_left(door.seconds_to_finish())]
	if not outcome.auto_closed.is_empty():
		response += "; closing " + ", ".join(outcome.auto_closed)
	if not outcome.left_open.is_empty():
		var many: bool = outcome.left_open.size() > 1
		response += "; %s %s no power and %s open" % [", ".join(outcome.left_open),
				"have" if many else "has", "stay" if many else "stays"]
	if outcome.onto_open_hatch:
		response += "; warning: hatch is open"
	return response


static func _state_word(state: Opening.State) -> String:
	match state:
		Opening.State.OPEN: return "open"
		Opening.State.CLOSED: return "closed"
		Opening.State.OPENING: return "opening"
	return "closing"


static func _light_on(ship: Ship, args: PackedStringArray) -> String:
	return _light(ship, args[0], true)


static func _light_off(ship: Ship, args: PackedStringArray) -> String:
	return _light(ship, args[0], false)


static func _light(ship: Ship, room_id: String, on: bool) -> String:
	if ship.room(room_id) == null:
		return _unknown_room(ship, room_id)
	var word := "on" if on else "off"
	if not ship.set_light(room_id, on):
		return "%s light: already %s" % [room_id, word]
	if on and not ship.light_lit(room_id):
		return "%s light: on (no power; reset breaker '%s')" % [room_id, Ship.light_breaker_id(room_id)]
	return "%s light: %s" % [room_id, word]


static func _unknown_room(ship: Ship, room_id: String) -> String:
	return "unknown room '%s'. Rooms: %s" % [room_id, ", ".join(_room_ids(ship))]


static func _room_ids(ship: Ship) -> PackedStringArray:
	var ids := PackedStringArray()
	for room in ship.rooms:
		ids.append(room.id)
	return ids


static func _opening_ids(ship: Ship) -> PackedStringArray:
	var ids := PackedStringArray()
	for opening in ship.openings:
		ids.append(opening.id)
	return ids


static func _passenger_add(ship: Ship, args: PackedStringArray) -> String:
	if ship.room(args[0]) == null:
		return _unknown_room(ship, args[0])
	return _passenger_count(args[0], ship.add_passenger(args[0]))


static func _passenger_remove(ship: Ship, args: PackedStringArray) -> String:
	if ship.room(args[0]) == null:
		return _unknown_room(ship, args[0])
	var count := ship.remove_passenger(args[0])
	if count < 0:
		return "%s: no passengers to remove" % args[0]
	return _passenger_count(args[0], count)


static func _passenger_count(room_id: String, count: int) -> String:
	return "%s: %d passenger%s" % [room_id, count, "" if count == 1 else "s"]


static func _restart(ship: Ship, _args: PackedStringArray, id: String) -> String:
	if ship.restart_system(id) == SystemUnit.RestartResult.NO_POWER:
		return "%s: no power; reset breaker '%s' first" % [id, id]
	return "%s: rebooting (%d s)" % [id, Units.whole_seconds_left(ship.systems[id].boot_s)]


static func _breaker_reset(ship: Ship, args: PackedStringArray) -> String:
	if not ship.power.has(args[0]):
		return _unknown_breaker(ship, args[0])
	if ship.breaker_reset(args[0]):
		return "%s: breaker reset" % args[0]
	return "%s: breaker is not tripped" % args[0]


static func _debug_trip(ship: Ship, args: PackedStringArray) -> String:
	if not ship.power.has(args[0]):
		return _unknown_breaker(ship, args[0])
	if ship.breaker_trip(args[0]):
		return "%s: breaker tripped" % args[0]
	return "%s: breaker already tripped" % args[0]


static func _unknown_breaker(ship: Ship, id: String) -> String:
	return "unknown breaker '%s'. Breakers: %s" % [id, ", ".join(ship.power.breaker_ids)]


static func _debug_fault(ship: Ship, args: PackedStringArray) -> String:
	var id := args[0]
	if not ship.systems.has(id):
		return "unknown system '%s'. Systems: %s" % [id, ", ".join(Ship.SYSTEM_IDS)]
	if ship.fault_system(id):
		return "%s: fault injected" % id
	if ship.systems[id].state == SystemUnit.State.NO_POWER:
		return "%s: no power" % id
	return "%s: already in fault" % id
