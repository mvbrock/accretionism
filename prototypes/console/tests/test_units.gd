extends TestCase

func test_whole_seconds_left_rounds_up() -> void:
	assert_true(Units.whole_seconds_left(19.0 + 1e-3) == 20, "a real fraction of a second counts")
	assert_true(Units.whole_seconds_left(0.5) == 1, "half a second counts")

func test_whole_seconds_left_ignores_float_residue() -> void:
	assert_true(Units.whole_seconds_left(19.0 + 1e-7) == 19, "residue under the epsilon is dropped")

func test_whole_seconds_left_of_nothing_is_zero() -> void:
	assert_true(Units.whole_seconds_left(0.0) == 0, "zero")

func test_duration_text_is_minutes_and_seconds() -> void:
	assert_true(Units.duration_text(0.0) == "0:00", "got '%s'" % Units.duration_text(0.0))
	assert_true(Units.duration_text(65.0) == "1:05", "got '%s'" % Units.duration_text(65.0))
	assert_true(Units.duration_text(960.0) == "16:00", "got '%s'" % Units.duration_text(960.0))
	assert_true(Units.duration_text(3599.0) == "59:59", "got '%s'" % Units.duration_text(3599.0))

func test_duration_text_adds_hours_from_an_hour() -> void:
	assert_true(Units.duration_text(3600.0) == "1:00:00", "got '%s'" % Units.duration_text(3600.0))
	assert_true(Units.duration_text(7325.0) == "2:02:05", "got '%s'" % Units.duration_text(7325.0))

func test_duration_text_rounds_a_part_second_up() -> void:
	assert_true(Units.duration_text(59.2) == "1:00", "got '%s'" % Units.duration_text(59.2))
