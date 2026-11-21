extends TestCase

const Main := preload("res://scripts/main.gd")


func test_scaled_window_size_doubles_on_retina() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(4000, 3000))
	assert_true(size == Vector2i(3200, 1800), "2x scale doubles the window (got %s)" % size)


func test_scaled_window_size_fits_the_screen() -> void:
	var size := Main.scaled_window_size(Vector2i(1600, 900), 2.0, Vector2i(3024, 1890))
	assert_true(size.x <= 3024 and size.y <= 1890, "fits the usable screen (got %s)" % size)
	assert_near(float(size.x) / size.y, 16.0 / 9.0, 0.01, "keeps the 16:9 shape")
