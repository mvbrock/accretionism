extends TestCase


func _fleet() -> Fleet:
	return FleetLoader.load_file(Main.FLEET_PATH)


func _pixel(texture: Texture2D, fraction: Vector2) -> Color:
	var image := texture.get_image()
	return image.get_pixelv(Vector2i(fraction * Vector2(image.get_size() - Vector2i.ONE)))


func test_every_ship_has_its_own_color() -> void:
	var fleet := _fleet()
	var seen := {}
	for ship in fleet.cyclers + fleet.transports:
		var html := ShipIcons.color_of(fleet, ship).to_html(false)
		assert_true(not seen.has(html), "%s shares its color with %s" % [ship.name, seen.get(html, "")])
		seen[html] = ship.name


func test_a_cycler_icon_is_a_square_in_its_color() -> void:
	var fleet := _fleet()
	var cycler: Cycler = fleet.cyclers[0]
	var color := ShipIcons.color_of(fleet, cycler)
	var texture := ShipIcons.texture(fleet, cycler)
	assert_color_near(_pixel(texture, Vector2(0.5, 0.5)), color, "the middle is the cycler's color")
	assert_true(_pixel(texture, Vector2(0.1, 0.1)).a > 0.9, "a square fills its corners")


func test_a_transport_icon_is_a_triangle_in_its_color() -> void:
	var fleet := _fleet()
	var transport: Transport = fleet.transports[0]
	var color := ShipIcons.color_of(fleet, transport)
	var texture := ShipIcons.texture(fleet, transport)
	assert_color_near(_pixel(texture, Vector2(0.5, 0.6)), color, "the middle is the transport's color")
	assert_true(_pixel(texture, Vector2(0.05, 0.05)).a < 0.1, "a triangle leaves its top corners empty")
