extends TestCase

func test_draw_limited_by_contents() -> void:
	var tank := Tank.new("O2", 3000.0, 10.0)
	assert_near(tank.draw(4.0), 4.0, 1e-9, "gives what was asked")
	assert_near(tank.draw(100.0), 6.0, 1e-9, "gives only what is left")
	assert_near(tank.mol, 0.0, 1e-9, "empty afterwards")

func test_fill_limited_by_capacity() -> void:
	var tank := Tank.new("O2", 3000.0, 2999.0)
	assert_near(tank.fill(5.0), 1.0, 1e-9, "accepts only the room left")
	assert_near(tank.mol, 3000.0, 1e-9, "full")
	assert_near(tank.fraction(), 1.0, 1e-9, "fraction when full")
