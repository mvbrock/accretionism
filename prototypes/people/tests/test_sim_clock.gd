extends TestCase


func test_does_not_advance_while_paused() -> void:
	var clock := SimClock.new()
	clock.paused = true
	clock.speed_index = 2
	assert_near(clock.tick(5.0), 0.0, 0.0, "day stays put while paused")


func test_ten_days_per_second_at_top_speed() -> void:
	var clock := SimClock.new()
	clock.speed_index = 2
	assert_near(clock.tick(1.0), 10.0, 1e-9, "one second at 10 d/s")
	assert_near(clock.day, 10.0, 1e-9, "day field updated")


func test_slowest_speed_is_one_hour_per_second() -> void:
	var clock := SimClock.new()
	clock.speed_index = 0
	assert_near(clock.tick(24.0), 1.0, 1e-9, "24 seconds at 1 h/s is one day")


func test_labels() -> void:
	var clock := SimClock.new()
	clock.day = 412.5
	clock.speed_index = 1
	assert_true(clock.label() == "Day 412.50 · 1.00 d/s", "got %s" % clock.label())
	clock.speed_index = 0
	assert_true(clock.label() == "Day 412.50 · 1.00 h/s", "got %s" % clock.label())
	clock.speed_index = 2
	assert_true(clock.label() == "Day 412.50 · 10.00 d/s", "got %s" % clock.label())
	clock.paused = true
	assert_true(clock.label() == "Day 412.50 · Paused", "the date stays while paused, got %s" % clock.label())
