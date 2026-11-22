extends TestCase

const USAGE_DOOR_OPEN := "usage: door open <d1|d2|hatch>"

func _run(ship: Ship, line: String) -> String:
	return CommandInterpreter.run(ship, line)

func _check(ship: Ship, line: String, expected: String) -> void:
	var actual := _run(ship, line)
	assert_true(actual == expected, "'%s' gave '%s', expected '%s'" % [line, actual, expected])

func test_door_open_started() -> void:
	_check(ShipFixture.make(), "door open d1", "d1: opening (2 s)")

func test_hatch_auto_closed_doors() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d1")
	_run(ship, "door open d2")
	_check(ship, "door open hatch", "hatch: opening (6 s); closing d1, d2")

func test_hatch_door_left_open() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d1")
	_run(ship, "door open d2")
	ship.advance(10.0)
	ship.breaker_trip("d2")
	_check(ship, "door open hatch", "hatch: opening (6 s); closing d1; d2 has no power and stays open")

func test_hatch_only_left_open() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d2")
	ship.advance(10.0)
	ship.breaker_trip("d2")
	_check(ship, "door open hatch", "hatch: opening (6 s); d2 has no power and stays open")

func test_door_onto_open_hatch() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open hatch")
	ship.advance(10.0)
	_check(ship, "door open d2", "d2: opening (2 s); warning: hatch is open")

func test_door_close_started() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d1")
	ship.advance(10.0)
	_check(ship, "door close d1", "d1: closing (2 s)")

func test_door_already() -> void:
	var ship := ShipFixture.make()
	_check(ship, "door close d1", "d1: already closed")
	_run(ship, "door open d1")
	_check(ship, "door open d1", "d1: already opening")
	ship.advance(10.0)
	_check(ship, "door open d1", "d1: already open")
	_run(ship, "door close d1")
	_check(ship, "door close d1", "d1: already closing")

func test_door_no_power() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("d1")
	_check(ship, "door open d1", "d1: no power (breaker tripped)")

func test_unknown_door() -> void:
	_check(ShipFixture.make(), "door open x", "unknown door 'x'. Doors: d1, d2, hatch")

func test_light() -> void:
	var ship := ShipFixture.make()
	_check(ship, "light off main", "main light: off")
	_check(ship, "light off main", "main light: already off")
	_check(ship, "light on main", "main light: on")
	_check(ship, "light on main", "main light: already on")

func test_light_on_without_power() -> void:
	var ship := ShipFixture.make()
	_run(ship, "light off cargo")
	ship.breaker_trip("light-cargo")
	_check(ship, "light on cargo", "cargo light: on (no power; reset breaker 'light-cargo')")

func test_unknown_room() -> void:
	_check(ShipFixture.make(), "light on attic", "unknown room 'attic'. Rooms: cockpit, main, cargo")

func test_restart() -> void:
	var ship := ShipFixture.make()
	_check(ship, "hvac restart", "hvac: rebooting (%d s)" % int(ship.systems["hvac"].boot_s))

func test_restart_no_power() -> void:
	var ship := ShipFixture.make()
	ship.breaker_trip("hvac")
	_check(ship, "hvac restart", "hvac: no power; reset breaker 'hvac' first")

func test_breaker_reset() -> void:
	var ship := ShipFixture.make()
	_check(ship, "breaker reset hvac", "hvac: breaker is not tripped")
	ship.breaker_trip("hvac")
	_check(ship, "breaker reset hvac", "hvac: breaker reset")

func test_unknown_breaker() -> void:
	_check(ShipFixture.make(), "breaker reset zz", "unknown breaker 'zz'. Breakers: light-cockpit, light-main, light-cargo, d1, d2, hatch, pressure-control, hvac, air-recycler")

func test_debug_trip() -> void:
	var ship := ShipFixture.make()
	_check(ship, "debug trip d1", "d1: breaker tripped")
	_check(ship, "debug trip d1", "d1: breaker already tripped")

func test_debug_fault() -> void:
	var ship := ShipFixture.make()
	_check(ship, "debug fault hvac", "hvac: fault injected")
	_check(ship, "debug fault hvac", "hvac: already in fault")
	ship.breaker_trip("air-recycler")
	ship.advance(0.1)
	_check(ship, "debug fault air-recycler", "air-recycler: no power")

func test_unknown_system() -> void:
	_check(ShipFixture.make(), "debug fault x", "unknown system 'x'. Systems: pressure-control, hvac, air-recycler, computer")

func test_wrong_argument_count() -> void:
	var ship := ShipFixture.make()
	_check(ship, "light on", "usage: light on <cockpit|main|cargo>")
	_check(ship, "hvac restart now", "usage: hvac restart")
	_check(ship, "breaker reset", "usage: breaker reset <breaker ID>")
	_check(ship, "debug trip", "usage: debug trip <breaker ID>")
	_check(ship, "debug fault", "usage: debug fault <system>")
	_check(ship, "help me", "usage: help")

func test_unknown_command() -> void:
	var ship := ShipFixture.make()
	_check(ship, "door shut d1", "unknown command 'door shut'. Type 'help' for commands")
	_check(ship, "frobnicate", "unknown command 'frobnicate'. Type 'help' for commands")
	_check(ship, "door", "unknown command 'door'. Type 'help' for commands")
	_check(ship, "hvac explode", "unknown command 'hvac explode'. Type 'help' for commands")

func test_system_restart_unknown_system() -> void:
	_check(ShipFixture.make(), "warp restart", "unknown command 'warp restart'. Type 'help' for commands")

func test_help() -> void:
	var expected := "\n".join([
		"door open <d1|d2|hatch> — Start opening",
		"door close <d1|d2|hatch> — Start closing",
		"light on <cockpit|main|cargo> — Switch that room's light on",
		"light off <cockpit|main|cargo> — Switch it off",
		"pressure-control restart — Reboot pressure control",
		"hvac restart — Reboot the HVAC",
		"air-recycler restart — Reboot the recycler",
		"computer restart — Reboot the computer",
		"breaker reset <breaker ID> — Close a tripped breaker",
		"help — List the commands.",
		"debug trip <breaker ID> — Trip a breaker.",
		"debug fault <system> — Put a system in FAULT.",
	])
	_check(ShipFixture.make(), "help", expected)

func test_tab_and_newline_separators() -> void:
	_check(ShipFixture.make(), "door\topen\r\nhatch\n", "hatch: opening (6 s)")

func test_echo_precedes_events_the_command_logs() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d1")
	_run(ship, "door open d2")
	ship.advance(10.0)
	var before := ship.events.entries.size()
	var response := _run(ship, "door open hatch")
	var texts: Array[String] = []
	for entry in ship.events.entries.slice(before):
		texts.append(entry.text)
	assert_true(texts.size() == 4, "echo, two closings, response; got %s" % [texts])
	assert_true(texts[0] == "> door open hatch", "echo first, got %s" % [texts])
	assert_true(texts[1].contains("d1: closing") and texts[2].contains("d2: closing"), "closings next, got %s" % [texts])
	assert_true(texts[3] == response, "response last, got %s" % [texts])

func test_two_doors_left_open() -> void:
	var ship := ShipFixture.make()
	_run(ship, "door open d1")
	_run(ship, "door open d2")
	ship.advance(10.0)
	ship.breaker_trip("d1")
	ship.breaker_trip("d2")
	_check(ship, "door open hatch", "hatch: opening (6 s); d1, d2 have no power and stay open")

func test_seconds_ignore_float_residue() -> void:
	var ship := ShipFixture.make()
	_run(ship, "computer restart")
	ship.systems["computer"].boot_left_s = 19.0 + 1e-10
	_check(ship, "help", "computer: rebooting; try again in 19 s")

func test_case_and_spacing() -> void:
	_check(ShipFixture.make(), "  DOOR   Open   HATCH ", "hatch: opening (6 s)")

func test_extra_argument() -> void:
	_check(ShipFixture.make(), "door open d1 now", USAGE_DOOR_OPEN)

func test_missing_argument() -> void:
	_check(ShipFixture.make(), "door open", USAGE_DOOR_OPEN)

func test_blank_line() -> void:
	var ship := ShipFixture.make()
	_check(ship, "   ", "")
	assert_true(ship.events.entries.is_empty(), "nothing logged")

func test_command_logged() -> void:
	var ship := ShipFixture.make()
	_run(ship, "light off main")
	var entries := ship.events.entries
	assert_true(entries[-2].text == "> light off main", "command logged as typed")
	assert_true(entries[-1].text == "main light: off", "response logged")

func test_command_logged_as_typed() -> void:
	var ship := ShipFixture.make()
	_run(ship, "LIGHT Off Main")
	assert_true(ship.events.entries[-2].text == "> LIGHT Off Main", "keeps case")

func test_computer_booting_blocks_input() -> void:
	var ship := ShipFixture.make()
	_run(ship, "computer restart")
	_check(ship, "help", "computer: rebooting; try again in 20 s")
	ship.advance(0.5)
	_check(ship, "light off main", "computer: rebooting; try again in 20 s")

func test_computer_fault_allows_only_restart() -> void:
	var ship := ShipFixture.make()
	_run(ship, "debug fault computer")
	_check(ship, "light off main", "computer: fault; only 'computer restart' works")
	_check(ship, "computer restart", "computer: rebooting (20 s)")
	_check(ship, "light off main", "computer: rebooting; try again in 20 s")
