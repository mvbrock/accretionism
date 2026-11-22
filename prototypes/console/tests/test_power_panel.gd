extends TestCase

func _ids() -> Array[String]:
	return ["light-cockpit", "d1", "hvac"]

func test_exposes_its_breaker_ids_in_order() -> void:
	var panel := PowerPanel.new(1, 0.0, _ids())
	assert_true(panel.breaker_ids == _ids(), "ids in the given order")
	assert_true(not panel.has("light-main"), "a breaker not given does not exist")

func test_trip_and_reset() -> void:
	var panel := PowerPanel.new(1, 0.0, _ids())
	assert_true(panel.has("hvac"), "known breaker")
	assert_true(not panel.has("nope"), "unknown breaker")
	assert_true(panel.is_powered("hvac"), "closed breaker is powered")
	assert_true(not panel.reset("hvac"), "reset of closed breaker refused")
	assert_true(panel.trip("hvac"), "trip closed breaker")
	assert_true(not panel.is_powered("hvac"), "tripped breaker unpowered")
	assert_true(not panel.trip("hvac"), "trip of tripped breaker refused")
	assert_true(panel.reset("hvac"), "reset tripped breaker")
	assert_true(panel.is_powered("hvac"), "powered after reset")

func test_no_random_trips_at_rate_zero() -> void:
	var panel := PowerPanel.new(1, 0.0, _ids())
	var total := 0
	for i in 10000:
		total += panel.roll_random_trips(0.1).size()
	assert_true(total == 0, "no trips at mean 0")

func test_random_trip_rate() -> void:
	var panel := PowerPanel.new(3, 10.0, _ids())
	var total := 0
	for i in 10000:
		var tripped := panel.roll_random_trips(0.1)
		total += tripped.size()
		for id in tripped:
			panel.reset(id)
	assert_near(float(total), 100.0 * _ids().size(), 70.0, "trip count near expectation")

func test_same_seed_same_trips() -> void:
	var a := PowerPanel.new(7, 10.0, _ids())
	var b := PowerPanel.new(7, 10.0, _ids())
	for i in 2000:
		var ta := a.roll_random_trips(0.1)
		var tb := b.roll_random_trips(0.1)
		assert_true(ta == tb, "same trips at call %d" % i)
		for id in ta:
			a.reset(id)
		for id in tb:
			b.reset(id)

func test_tripped_breakers_still_draw() -> void:
	var a := PowerPanel.new(11, 10.0, _ids())
	var b := PowerPanel.new(11, 10.0, _ids())
	a.trip("light-cockpit")
	var others_tripped := 0
	for i in 2000:
		var ta := a.roll_random_trips(0.1)
		var tb := b.roll_random_trips(0.1)
		ta.erase("light-cockpit")
		tb.erase("light-cockpit")
		others_tripped += ta.size()
		assert_true(ta == tb, "other breakers trip on the same calls at call %d" % i)
		for id in ta:
			a.reset(id)
		for id in tb:
			b.reset(id)
		b.reset("light-cockpit")
	assert_true(others_tripped > 0, "other breakers tripped at least once")
