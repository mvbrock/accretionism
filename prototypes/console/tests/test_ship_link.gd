extends TestCase


func _link() -> ShipLink:
	return ShipLink.new(Fleet.load_dir(Main.SHIPS_DIR))


func test_ships_list() -> void:
	var response := _link().run("ships list")
	assert_true(response == "kestrel\nwren", "got '%s'" % response)


func test_connect_is_case_insensitive() -> void:
	var link := _link()
	assert_true(link.run("Ships Connect WREN") == "connected to wren", "the response names the ship")
	assert_true(link.ship() == link.fleet.ships.wren, "wren is connected")


func test_connect_unknown_ship() -> void:
	var link := _link()
	var response := link.run("ships connect ghost")
	assert_true(response == "unknown ship 'ghost'. Ships: kestrel, wren", "got '%s'" % response)
	assert_true(link.ship() == null, "still disconnected")


func test_ships_usage() -> void:
	var link := _link()
	assert_true(link.run("ships connect") == "usage: ships connect <kestrel|wren>", "got '%s'" % link.run("ships connect"))
	assert_true(link.run("ships") == "usage: ships list | ships connect <ship name>", "got '%s'" % link.run("ships"))
	assert_true(link.run("ships list now") == "usage: ships list | ships connect <ship name>", "got '%s'" % link.run("ships list now"))


func test_ship_commands_need_a_connection() -> void:
	var link := _link()
	assert_true(link.run("door open hatch") == ShipLink.NOT_CONNECTED, "got '%s'" % link.run("door open hatch"))
	assert_true(link.run("disconnect") == "not connected to a ship", "got '%s'" % link.run("disconnect"))
	for ship in link.fleet.ships.values():
		assert_true((ship as Ship).opening("hatch").state == Opening.State.CLOSED, "no hatch moved")


func test_disconnected_help_lists_the_ships_commands() -> void:
	var response := _link().run("help")
	assert_true(response == "ships list — List the ships\nships connect <kestrel|wren> — Connect to that ship", "got '%s'" % response)


func test_connected_commands_reach_only_that_ship() -> void:
	var link := _link()
	link.run("ships connect wren")
	assert_true(link.run("door open hatch") == "hatch: opening (6 s)", "the ship's interpreter answers")
	assert_true(link.fleet.ships.wren.opening("hatch").state == Opening.State.OPENING, "wren's hatch opens")
	assert_true(link.fleet.ships.kestrel.opening("hatch").state == Opening.State.CLOSED, "kestrel's stays shut")


func test_ships_commands_wait_for_disconnect() -> void:
	var link := _link()
	link.run("ships connect kestrel")
	assert_true(link.run("ships list") == "connected to kestrel; type 'disconnect' first", "got '%s'" % link.run("ships list"))
	assert_true(link.run("ships connect wren") == "connected to kestrel; type 'disconnect' first", "no switch without disconnect")
	assert_true(link.ship_name == "kestrel", "still on kestrel")


func test_disconnect() -> void:
	var link := _link()
	link.run("ships connect kestrel")
	assert_true(link.run("disconnect now") == "usage: disconnect", "got '%s'" % link.run("disconnect now"))
	assert_true(link.run("disconnect") == "disconnected from kestrel", "the response names the ship")
	assert_true(link.ship() == null, "disconnected")


func test_disconnect_works_while_the_computer_is_down() -> void:
	var link := _link()
	link.run("ships connect kestrel")
	link.run("debug fault computer")
	assert_true(link.run("disconnect") == "disconnected from kestrel", "FAULT doesn't hold the link")
	link.run("ships connect kestrel")
	link.run("computer restart")
	assert_true(link.run("disconnect") == "disconnected from kestrel", "BOOTING doesn't hold the link")


func test_connected_help_adds_disconnect() -> void:
	var link := _link()
	link.run("ships connect kestrel")
	var response := link.run("help")
	assert_true(response.begins_with("door open"), "the ship's commands come first, got '%s'" % response.get_slice("\n", 0))
	assert_true(response.ends_with("\ndisconnect — Disconnect from kestrel"), "disconnect comes last")
	link.run("computer restart")
	response = link.run("help")
	assert_true(response.begins_with("computer: rebooting") and response.ends_with("; 'disconnect' also works"),
			"a booting computer refuses help and says disconnect still works, got '%s'" % response)


func test_fault_refusal_mentions_disconnect() -> void:
	var link := _link()
	link.run("ships connect kestrel")
	link.run("debug fault computer")
	var response := link.run("door open hatch")
	assert_true(response == "computer: fault; only 'computer restart' works; 'disconnect' also works", "got '%s'" % response)
	response = link.run("computer restart")
	assert_true(response.begins_with("computer: rebooting (") and not response.contains("disconnect"),
			"the restart is accepted, with no hint, got '%s'" % response)
