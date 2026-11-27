extends TestCase

func test_paused_advances_nothing() -> void:
	var clock := SimClock.new()
	clock.paused = true
	assert_near(clock.tick(0.5), 0.0, 1e-9, "paused tick")

func test_speeds_are_real_time_a_minute_and_an_hour_a_second() -> void:
	var clock := SimClock.new()
	for i in 3:
		clock.speed_index = i
		assert_near(clock.tick(0.5), 0.5 * [1.0, 60.0, 3600.0][i], 1e-9, "speed %d of 0.5 s" % i)

func test_speed_labels() -> void:
	var clock := SimClock.new()
	var labels: Array[String] = []
	for i in 3:
		clock.speed_index = i
		labels.append(clock.speed_label())
	assert_true(labels == (["real time", "1 min/s", "1 hour/s"] as Array[String]), "labels, got %s" % [labels])

func test_step_follows_speed() -> void:
	var clock := SimClock.new()
	var steps: Array[float] = []
	for i in 3:
		clock.speed_index = i
		steps.append(clock.step_s())
	assert_true(steps == ([0.1, 0.1, 5.0] as Array[float]), "steps, got %s" % [steps])

func test_starts_at_real_time() -> void:
	var clock := SimClock.new()
	assert_near(clock.tick(0.5), 0.5, 1e-9, "1x of 0.5 s")

func test_every_step_is_a_whole_multiple_of_the_ship_step() -> void:
	var clock := SimClock.new()
	for i in SimClock.speed_count():
		clock.speed_index = i
		var multiple := clock.step_s() / Ship.STEP_S
		assert_near(multiple, roundf(multiple), 1e-9, "step at speed %d" % i)
