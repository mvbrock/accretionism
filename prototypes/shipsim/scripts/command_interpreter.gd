class_name CommandInterpreter
extends RefCounted
## Turns one typed line into calls on the Ship and one response line.


static var _WHITESPACE := _compile_whitespace()


static func _compile_whitespace() -> RegEx:
	var regex := RegEx.new()
	regex.compile("\\s+")
	return regex


## Runs `line`, logs it and the response to the ship's event log, and returns
## the response. A blank line does nothing and returns "".
static func run(ship: Ship, line: String) -> String:
	var words := _WHITESPACE.sub(line.to_lower(), " ", true).split(" ", false)
	if words.is_empty():
		return ""
	ship.events.add(ship.time_s, "> " + line.strip_edges())
	var response := _respond(ship, words)
	ship.events.add(ship.time_s, response)
	return response


static func _respond(ship: Ship, words: PackedStringArray) -> String:
	var commands := _commands()
	var key := " ".join(words.slice(0, 2))
	if not commands.has(key) and commands.has(words[0]):
		key = words[0]
	var arg_count := words.size() - key.count(" ") - 1
	var computer := ship.systems["computer"] as SystemUnit
	if computer.state == SystemUnit.State.BOOTING:
		return "computer: rebooting; try again in %d s" % _whole_seconds(computer.boot_left_s)
	if computer.state == SystemUnit.State.FAULT and key != "computer restart":
		return "computer: fault; only 'computer restart' works"
	if not commands.has(key):
		return "unknown command '%s'. Type 'help' for commands" % " ".join(words.slice(0, 2))
	var command: Dictionary = commands[key]
	if arg_count != command.args:
		return "usage: " + command.usage
	return command.handler.call(ship, words.slice(words.size() - arg_count))


## Command key (its leading words) -> {usage, effect, args, handler}, in help order.
static func _commands() -> Dictionary:
	var commands := {}
	_add(commands, "door open", "door open <d1|d2|hatch>", "Start opening", 1, _door_open)
	_add(commands, "door close", "door close <d1|d2|hatch>", "Start closing", 1, _door_close)
	_add(commands, "light on", "light on <cockpit|main|cargo>", "Switch that room's light on", 1, _light_on)
	_add(commands, "light off", "light off <cockpit|main|cargo>", "Switch it off", 1, _light_off)
	_add(commands, "pressure-control restart", "pressure-control restart", "Reboot pressure control", 0, _restart.bind("pressure-control"))
	_add(commands, "hvac restart", "hvac restart", "Reboot the HVAC", 0, _restart.bind("hvac"))
	_add(commands, "air-recycler restart", "air-recycler restart", "Reboot the recycler", 0, _restart.bind("air-recycler"))
	_add(commands, "computer restart", "computer restart", "Reboot the computer", 0, _restart.bind("computer"))
	_add(commands, "breaker reset", "breaker reset <breaker ID>", "Close a tripped breaker", 1, _breaker_reset)
	_add(commands, "help", "help", "List the commands.", 0, _help)
	_add(commands, "debug trip", "debug trip <breaker ID>", "Trip a breaker.", 1, _debug_trip)
	_add(commands, "debug fault", "debug fault <system>", "Put a system in FAULT.", 1, _debug_fault)
	return commands


## Rounds up to whole seconds, ignoring float residue from summed steps.
static func _whole_seconds(seconds: float) -> int:
	return int(ceil(seconds - 1e-9))


static func _add(commands: Dictionary, key: String, usage: String, effect: String, args: int, handler: Callable) -> void:
	commands[key] = {"usage": usage, "effect": effect, "args": args, "handler": handler}


static func _help(_ship: Ship, _args: PackedStringArray) -> String:
	var lines := PackedStringArray()
	var commands := _commands()
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
		var ids := PackedStringArray()
		for candidate in ship.openings:
			ids.append(candidate.id)
		return "unknown door '%s'. Doors: %s" % [id, ", ".join(ids)]
	var outcome := ship.set_opening(id, want_open)
	match outcome.result:
		Opening.CommandResult.NO_POWER:
			return "%s: no power (breaker tripped)" % id
		Opening.CommandResult.ALREADY:
			return "%s: already %s" % [id, _state_word(door.state)]
	var response := "%s: %s (%d s)" % [id, "opening" if want_open else "closing", _whole_seconds(door.seconds_to_finish())]
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
		var ids := PackedStringArray()
		for room in ship.rooms:
			ids.append(room.id)
		return "unknown room '%s'. Rooms: %s" % [room_id, ", ".join(ids)]
	var word := "on" if on else "off"
	if not ship.set_light(room_id, on):
		return "%s light: already %s" % [room_id, word]
	if on and not ship.light_lit(room_id):
		return "%s light: on (no power; reset breaker 'light-%s')" % [room_id, room_id]
	return "%s light: %s" % [room_id, word]


static func _restart(ship: Ship, _args: PackedStringArray, id: String) -> String:
	if ship.restart_system(id) == SystemUnit.RestartResult.NO_POWER:
		return "%s: no power; reset breaker '%s' first" % [id, id]
	return "%s: rebooting (%d s)" % [id, _whole_seconds(ship.systems[id].boot_s)]


static func _breaker_reset(ship: Ship, args: PackedStringArray) -> String:
	if not ship.power.has(args[0]):
		return _unknown_breaker(args[0])
	if ship.breaker_reset(args[0]):
		return "%s: breaker reset" % args[0]
	return "%s: breaker is not tripped" % args[0]


static func _debug_trip(ship: Ship, args: PackedStringArray) -> String:
	if not ship.power.has(args[0]):
		return _unknown_breaker(args[0])
	if ship.breaker_trip(args[0]):
		return "%s: breaker tripped" % args[0]
	return "%s: breaker already tripped" % args[0]


static func _unknown_breaker(id: String) -> String:
	return "unknown breaker '%s'. Breakers: %s" % [id, ", ".join(PowerPanel.BREAKER_IDS)]


static func _debug_fault(ship: Ship, args: PackedStringArray) -> String:
	var id := args[0]
	if not ship.systems.has(id):
		return "unknown system '%s'. Systems: %s" % [id, ", ".join(Ship.SYSTEM_IDS)]
	if ship.fault_system(id):
		return "%s: fault injected" % id
	if ship.systems[id].state == SystemUnit.State.NO_POWER:
		return "%s: no power" % id
	return "%s: already in fault" % id
