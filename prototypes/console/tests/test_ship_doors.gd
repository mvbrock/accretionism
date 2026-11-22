extends TestCase

func _open_door(ship: Ship, id: String) -> void:
	ship.set_opening(id, true)
	ship.advance(2.0)

func _has_warning(ship: Ship, text: String) -> bool:
	for entry in ship.events.entries:
		if entry.text == text and entry.level == EventLog.Level.WARNING:
			return true
	return false

func test_hatch_closes_open_doors() -> void:
	var ship := ShipFixture.make()
	_open_door(ship, "d1")
	_open_door(ship, "d2")
	var outcome := ship.set_opening("hatch", true)
	assert_true(outcome.auto_closed == ["d1", "d2"], "auto_closed is d1, d2: %s" % [outcome.auto_closed])
	ship.advance(2.0)
	assert_true(ship.opening("d1").state == Opening.State.CLOSED, "d1 closed")
	assert_true(ship.opening("d2").state == Opening.State.CLOSED, "d2 closed")
	assert_true(ship.events.has_text("d1: closing (hatch opening)"), "d1 close logged")

func test_hatch_reverses_opening_door() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("d2", true)
	ship.advance(1.0)
	assert_near(ship.opening("d2").fraction, 0.5, 0.02, "d2 half open")
	ship.set_opening("hatch", true)
	assert_true(ship.opening("d2").state == Opening.State.CLOSING, "d2 closing")
	ship.advance(1.0)
	assert_true(ship.opening("d2").state == Opening.State.CLOSED, "d2 closed")
	assert_true(ship.exposed["cargo"], "cargo exposed")
	assert_true(not ship.exposed["main"], "main not exposed")

func test_unpowered_door_stays_open() -> void:
	var ship := ShipFixture.make()
	_open_door(ship, "d2")
	ship.breaker_trip("d2")
	var outcome := ship.set_opening("hatch", true)
	assert_true(outcome.left_open == ["d2"], "left_open is d2: %s" % [outcome.left_open])
	assert_true(outcome.auto_closed.is_empty(), "nothing auto-closed")
	assert_true(_has_warning(ship, "d2: no power, left open with hatch opening"), "warning logged")
	ship.advance(120.0)
	assert_true(ship.room("main").pressure() < 1000.0, "main below 1 kPa")

func test_whole_ship_vents_with_both_doors_unpowered() -> void:
	var ship := ShipFixture.make()
	_open_door(ship, "d1")
	_open_door(ship, "d2")
	ship.breaker_trip("d1")
	ship.breaker_trip("d2")
	ship.set_opening("hatch", true)
	ship.advance(120.0)
	for room in ship.rooms:
		assert_true(room.pressure() < 1000.0, "%s below 1 kPa" % room.id)

func test_reopening_door_onto_open_hatch_warns() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("hatch", true)
	ship.advance(7.0)
	assert_true(ship.opening("hatch").state == Opening.State.OPEN, "hatch open")
	var outcome := ship.set_opening("d2", true)
	assert_true(outcome.result == Opening.CommandResult.STARTED, "d2 started")
	assert_true(outcome.onto_open_hatch, "onto_open_hatch")
	assert_true(_has_warning(ship, "d2: opened onto an open hatch"), "warning logged")

func test_hatch_tripped_half_open_vents_at_half_rate() -> void:
	var ship := ShipFixture.make()
	ship.set_opening("hatch", true)
	ship.advance(3.0)
	ship.breaker_trip("hatch")
	assert_near(ship.opening("hatch").fraction, 0.5, 0.02, "hatch half open")
	var p3 := ship.room("cargo").pressure()
	ship.advance(12.0)
	assert_near(ship.room("cargo").pressure(), p3 * exp(-5.0 * 0.5 * 12.0 / 30.0), p3 * 0.02, "half-rate venting")
	assert_true(ship.exposed["cargo"], "cargo still exposed")

func test_closing_door_is_not_reported_as_auto_closed() -> void:
	var ship := ShipFixture.make()
	_open_door(ship, "d2")
	ship.set_opening("d2", false)
	var outcome: Dictionary = ship.set_opening("hatch", true)
	assert_true(outcome.auto_closed.is_empty(), "d2 not in auto_closed")
	assert_true(not ship.events.has_text("d2: closing (hatch opening)"), "no close line for d2")
