extends TestCase


func _link() -> ShipLink:
	return ShipLink.new(Fleet.load_dir(Main.SHIPS_DIR))


func _connected(transmission_s := 10.0) -> ShipLink:
	var link := _link()
	for ship in link.fleet.ships.values():
		(ship as Ship).transmission_s = transmission_s
	link.run("ships connect kestrel")
	return link


func _round_trip(link: ShipLink, line: String) -> String:
	link.run(line)
	var replies := link.advance(link.ship().transmission_s * 2.0 + 1.0, 0.1)
	return replies[0] if not replies.is_empty() else ""


func test_ships_list() -> void:
	var response := _link().run("ships list")
	assert_true(response == "ships: kestrel, wren", "got '%s'" % response)


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
	assert_true(_round_trip(link, "door open hatch") == "hatch: opening (6 s)", "the ship's interpreter answers")
	assert_true(link.fleet.ships.wren.opening("hatch").state != Opening.State.CLOSED, "wren's hatch opens")
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
	var link := _connected(0.0)
	_round_trip(link, "debug fault computer")
	assert_true(link.run("disconnect") == "disconnected from kestrel", "FAULT doesn't hold the link")
	link.run("ships connect kestrel")
	_round_trip(link, "computer restart")
	assert_true(link.run("disconnect") == "disconnected from kestrel", "BOOTING doesn't hold the link")


func test_connected_help_is_local_and_adds_disconnect() -> void:
	var link := _connected()
	var response := link.run("help")
	assert_true(response.begins_with("door open"), "the ship's commands come first, got '%s'" % response.get_slice("\n", 0))
	assert_true(response.ends_with("\ndisconnect — Disconnect from kestrel"), "disconnect comes last")
	assert_true(not link.in_flight(), "nothing was sent")
	link.ship().systems[Ship.COMPUTER_ID].restart(true)
	response = link.run("help")
	assert_true(response.begins_with("door open") and not response.contains("rebooting"),
			"a booting computer doesn't refuse help, got '%s'" % response)


func test_fault_refusal_mentions_disconnect() -> void:
	var link := _connected(0.0)
	_round_trip(link, "debug fault computer")
	var response := _round_trip(link, "door open hatch")
	assert_true(response == "computer: fault; only 'computer restart' works; 'disconnect' also works", "got '%s'" % response)
	response = _round_trip(link, "computer restart")
	assert_true(response.begins_with("computer: rebooting (") and not response.contains("disconnect"),
			"the restart is accepted, with no hint, got '%s'" % response)


func test_sending_reports_the_round_trip() -> void:
	var link := _connected(480.0)
	var response := link.run("door open hatch")
	assert_true(response == "sent to kestrel; reply in 16:00", "got '%s'" % response)
	assert_true(link.ship().opening("hatch").state == Opening.State.CLOSED, "nothing has reached the ship yet")


func test_command_runs_at_the_exact_landing_time() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	var replies := link.advance(9.9, 0.1)
	assert_true(replies.is_empty(), "still in flight")
	assert_true(link.ship().opening("hatch").state == Opening.State.CLOSED, "not yet")
	replies = link.advance(0.1, 0.1)
	assert_true(replies.is_empty(), "the reply is still on its way")
	assert_true(link.ship().opening("hatch").state == Opening.State.OPENING, "the hatch moves when the uplink lands")
	assert_near(link.ship().time_s, 10.0, 1e-6, "the ship is at the landing time")


func test_reply_lands_after_the_downlink() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	link.advance(19.9, 0.1)
	var replies := link.advance(0.1, 0.1)
	assert_true(replies == PackedStringArray(["hatch: opening (6 s)"]), "got %s" % [replies])
	assert_true(not link.in_flight(), "the link is free again")
	assert_true(link.line() == "", "the line is cleared once the reply lands")


func test_one_advance_can_land_both_legs() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	var replies := link.advance(50.0, 0.1)
	assert_true(replies.size() == 1, "one reply, got %d" % replies.size())
	assert_near(link.ship().time_s, 50.0, 1e-6, "the ship got the whole advance")


func test_the_computer_refusal_is_decided_on_arrival() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	link.advance(5.0, 0.1)
	link.ship().systems[Ship.COMPUTER_ID].restart(true)
	var replies := link.advance(20.0, 0.1)
	assert_true(replies.size() == 1 and replies[0].begins_with("computer: rebooting") and replies[0].ends_with("; 'disconnect' also works"),
			"got %s" % [replies])
	assert_true(link.ship().opening("hatch").state == Opening.State.CLOSED, "the refused command did nothing")


func test_a_ready_computer_at_arrival_accepts_a_command_sent_while_down() -> void:
	var link := _connected(30.0)
	link.ship().systems[Ship.COMPUTER_ID].restart(true)
	link.run("door open hatch")
	var replies := link.advance(70.0, 0.1)
	assert_true(replies == PackedStringArray(["hatch: opening (6 s)"]), "booted by arrival (20 s boot), got %s" % [replies])


func test_a_second_command_is_refused_while_one_is_in_flight() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	var response := link.run("light off cargo")
	assert_true(response == "waiting on 'door open hatch'; one command at a time", "got '%s'" % response)
	link.advance(10.0, 0.1)
	assert_true(link.run("light off cargo") == "waiting on 'door open hatch'; one command at a time", "busy during the downlink too")


func test_disconnect_is_refused_in_flight() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	var response := link.run("disconnect")
	assert_true(response == "waiting on 'door open hatch'; disconnect when the reply is in", "got '%s'" % response)
	assert_true(link.ship_name == "kestrel", "still connected")
	link.advance(20.0, 0.1)
	assert_true(link.run("disconnect") == "disconnected from kestrel", "free once the reply is in")


func test_console_commands_stay_instant_in_flight() -> void:
	var link := _connected(10.0)
	link.run("door open hatch")
	assert_true(link.run("ships list") == "connected to kestrel; type 'disconnect' first", "ships is answered at once")
	assert_true(link.run("help").begins_with("door open"), "help is answered at once")


func test_zero_transmission_replies_on_the_next_advance() -> void:
	var link := _connected(0.0)
	var response := link.run("door open hatch")
	assert_true(response == "sent to kestrel; reply in 0:00", "got '%s'" % response)
	assert_true(link.ship().opening("hatch").state == Opening.State.CLOSED, "nothing runs before an advance")
	var replies := link.advance(0.0, 0.1)
	assert_true(replies == PackedStringArray(["hatch: opening (6 s)"]), "got %s" % [replies])


func test_progress_accessors_follow_each_leg() -> void:
	var link := _connected(10.0)
	assert_true(not link.uplink_active() and not link.downlink_active(), "idle")
	link.run("door open hatch")
	link.advance(4.0, 0.1)
	assert_true(link.uplink_active() and not link.downlink_active(), "uplink first")
	assert_near(link.downlink_fraction(), 0.0, 1e-9, "the downlink hasn't started")
	assert_near(link.downlink_left_s(), 0.0, 1e-9, "no downlink time is counted yet")
	assert_true(link.line() == "door open hatch", "the line, got '%s'" % link.line())
	assert_near(link.uplink_fraction(), 0.4, 1e-6, "40% up")
	assert_near(link.uplink_left_s(), 6.0, 1e-6, "6 s left up")
	link.advance(8.0, 0.1)
	assert_true(link.downlink_active() and not link.uplink_active(), "then downlink")
	assert_near(link.downlink_fraction(), 0.2, 1e-6, "20% down")
	assert_near(link.downlink_left_s(), 8.0, 1e-6, "8 s left down")
	assert_near(link.uplink_fraction(), 1.0, 1e-9, "the uplink is complete")
	assert_near(link.uplink_left_s(), 0.0, 1e-9, "no uplink time is left")
	link.advance(8.0, 0.1)
	assert_true(not link.uplink_active() and not link.downlink_active() and link.line() == "", "idle again")
	for value in [link.uplink_fraction(), link.uplink_left_s(), link.downlink_fraction(), link.downlink_left_s()]:
		assert_near(value, 0.0, 1e-9, "every accessor is back at 0")


func test_the_whole_fleet_advances_through_the_link() -> void:
	var link := _link()
	link.advance(5.0, 0.1)
	for ship in link.fleet.ships.values():
		assert_near((ship as Ship).time_s, 5.0, 1e-6, "every ship advanced")
