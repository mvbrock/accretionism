extends TestCase

func test_whole_seconds_left_rounds_up() -> void:
	assert_true(Units.whole_seconds_left(19.0 + 1e-3) == 20, "a real fraction of a second counts")
	assert_true(Units.whole_seconds_left(0.5) == 1, "half a second counts")

func test_whole_seconds_left_ignores_float_residue() -> void:
	assert_true(Units.whole_seconds_left(19.0 + 1e-7) == 19, "residue under the epsilon is dropped")

func test_whole_seconds_left_of_nothing_is_zero() -> void:
	assert_true(Units.whole_seconds_left(0.0) == 0, "zero")
