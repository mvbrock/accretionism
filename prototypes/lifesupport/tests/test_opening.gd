extends TestCase

func _door() -> Opening:
	return Opening.new("d1", "cockpit", "main", 2.0)

func test_door_opens_in_travel_time() -> void:
	var door := _door()
	door.command(true, true)
	for i in 10:
		door.step(0.1, true)
	assert_near(door.fraction, 0.5, 1e-9, "halfway after 1 s")
	assert_true(door.state == Opening.State.OPENING, "still opening at half")
	for i in 10:
		door.step(0.1, true)
	assert_near(door.fraction, 1.0, 1e-9, "fully open after 2 s")
	assert_true(door.state == Opening.State.OPEN, "open after travel time")

func test_command_results() -> void:
	var door := _door()
	assert_true(door.command(true, true) == Opening.CommandResult.STARTED, "open on closed starts")
	assert_true(door.command(true, true) == Opening.CommandResult.ALREADY, "open while opening is already")
	for i in 10:
		door.step(0.1, true)
	assert_true(door.command(false, true) == Opening.CommandResult.STARTED, "close while opening reverses")
	assert_true(door.state == Opening.State.CLOSING, "now closing")
	assert_near(door.fraction, 0.5, 1e-9, "fraction kept on reversal")
	var open_door := _door()
	open_door.fraction = 1.0
	open_door.state = Opening.State.OPEN
	assert_true(open_door.command(true, true) == Opening.CommandResult.ALREADY, "open when open is already")

func test_unpowered_opening_holds_position() -> void:
	var door := _door()
	door.command(true, true)
	for i in 10:
		door.step(0.1, true)
	for i in 10:
		door.step(0.1, false)
	assert_near(door.fraction, 0.5, 1e-9, "no movement without power")
	assert_true(door.state == Opening.State.OPENING, "state unchanged without power")
	assert_true(door.command(false, false) == Opening.CommandResult.NO_POWER, "command needs power")
	assert_true(door.state == Opening.State.OPENING, "refused command changes nothing")

func test_closing_reaches_closed() -> void:
	var door := _door()
	door.fraction = 1.0
	door.state = Opening.State.OPEN
	door.command(false, true)
	for i in 25:
		door.step(0.1, true)
	assert_near(door.fraction, 0.0, 1e-9, "fully closed")
	assert_true(door.state == Opening.State.CLOSED, "closed state")

func test_seconds_to_finish() -> void:
	var hatch := Opening.new("hatch", "cargo", Opening.OUTSIDE, 6.0)
	assert_true(hatch.is_hatch(), "outside marks the hatch")
	hatch.fraction = 0.25
	hatch.state = Opening.State.OPENING
	assert_near(hatch.seconds_to_finish(), 4.5, 1e-9, "opening time left")
	hatch.state = Opening.State.CLOSING
	assert_near(hatch.seconds_to_finish(), 1.5, 1e-9, "closing time left")
	hatch.state = Opening.State.OPEN
	assert_near(hatch.seconds_to_finish(), 0.0, 0.0, "nothing left when open")
