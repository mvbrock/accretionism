extends TestCase

func test_paused_advances_nothing() -> void:
	var clock := SimClock.new()
	clock.paused = true
	assert_near(clock.tick(0.5), 0.0, 1e-9, "paused tick")

func test_speed_two_is_one_hundred_times() -> void:
	var clock := SimClock.new()
	clock.speed_index = 2
	assert_near(clock.tick(0.5), 50.0, 1e-9, "100x of 0.5 s")

func test_starts_at_real_time() -> void:
	var clock := SimClock.new()
	assert_near(clock.tick(0.5), 0.5, 1e-9, "1x of 0.5 s")
