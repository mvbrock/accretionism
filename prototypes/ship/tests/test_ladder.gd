extends TestCase


func test_point_at_clamps() -> void:
	var ladder := Ladder.new(Vector3(1, 0, 1), Vector3.UP, 4.4)
	assert_true(ladder.point_at(2.0).is_equal_approx(Vector3(1, 2, 1)), "inside the length")
	assert_true(ladder.point_at(-1.0) == ladder.start, "clamped to the start")
	assert_true(ladder.point_at(9.0).is_equal_approx(Vector3(1, 4.4, 1)), "clamped to the end")


func test_landing_near_and_at() -> void:
	var ladder := Ladder.new(Vector3(1, 0, 1), Vector3.UP, 4.4)
	ladder.add_landing(0.0, Vector3(1, 0, 0), Vector3.BACK)
	ladder.add_landing(4.4, Vector3(1, 4.4, 0), Vector3.BACK)
	assert_true(ladder.landing_near(Vector3(1.3, 0, 0.2), 1.0) == 0, "near the lower exit")
	assert_true(ladder.landing_near(Vector3(1, 2, 0), 1.0) == -1, "midway is near none")
	assert_true(ladder.landing_at(4.3, 0.3) == 1, "at the upper landing")
	assert_true(ladder.landing_at(2.0, 0.3) == -1, "midway is at none")
