extends TestCase

var ship: ShipBuilder
var player: Player
var rig: CameraRig
var fader: OcclusionFader


func _setup(x: float = 0.0) -> void:
	ship = own(ShipBuilder.new())
	player = load("res://scenes/player.tscn").instantiate()
	player.drive_by_code = true
	own(player)
	player.global_position = Vector3(x, -(RingGeometry.floor_apothem() - 0.05), 0)
	rig = CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	rig.target = player
	own(rig)
	fader = OcclusionFader.new()
	fader.camera = camera
	fader.target = player
	fader.ship = ship
	own(fader)
	fader.set_process(false)  # the tests step it by hand
	await physics_frames(3)
	rig.snap()


func _mesh(path: String) -> MeshInstance3D:
	return ship.get_node(path + "/Mesh")


func test_ceiling_occludes_at_spawn() -> void:
	await _setup()
	var found := fader.find_occluders()
	assert_true(_mesh("Section0/Ceiling") in found, "ceiling over spawn occludes")


func test_ceiling_and_wall_both_occlude() -> void:
	await _setup(1.5)
	var found := fader.find_occluders()
	assert_true(_mesh("Section0/Ceiling") in found, "ceiling occludes")
	assert_true(_mesh("Section0/WallRight") in found, "camera-side wall occludes")


func test_wall_occludes_near_wall() -> void:
	await _setup(4.3)
	assert_true(_mesh("Section0/WallRight") in fader.find_occluders(), "camera-side wall occludes")


func test_floors_never_returned() -> void:
	await _setup(1.5)
	for mesh in fader.find_occluders():
		assert_true(mesh.get_parent().name != "Floor", "floor returned: %s" % mesh.get_path())


func test_fades_and_restores() -> void:
	await _setup()
	var ceiling := _mesh("Section0/Ceiling")
	var material: StandardMaterial3D = ceiling.material_override
	for i in 120:
		fader.step(1.0 / 60.0)
	assert_true(material.albedo_color.a < 0.2, "ceiling faded (alpha %.2f)" % material.albedo_color.a)
	assert_true(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "transparent while faded")

	player.global_position = RingGeometry.section_down(6) * (RingGeometry.floor_apothem() - 0.05)
	await physics_frames(2)
	rig.snap()
	for i in 120:
		fader.step(1.0 / 60.0)
	assert_true(material.albedo_color.a > 0.98, "ceiling restored (alpha %.2f)" % material.albedo_color.a)
	assert_true(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque again")
	assert_true(_mesh("Section6/Ceiling").material_override.albedo_color.a < 0.2, "new ceiling faded")


func test_room_ceiling_and_camera_side_wall_fade_anywhere_in_room() -> void:
	await _setup(-4.3)  # hugging the far wall, where no sight line crosses the camera-side wall
	var found := fader.find_occluders()
	assert_true(_mesh("Section0/Ceiling") in found, "room ceiling fades")
	assert_true(_mesh("Section0/WallRight") in found, "room's camera-side wall fades")
	assert_true(_mesh("Section0/WallLeft") not in found, "far wall stays opaque")


func test_room_follows_player() -> void:
	await _setup()
	player.global_position = RingGeometry.section_down(3) * (RingGeometry.floor_apothem() - 0.05)
	await physics_frames(2)
	rig.snap()
	var found := fader.find_occluders()
	assert_true(_mesh("Section3/Ceiling") in found, "new room's ceiling fades")
	assert_true(_mesh("Section3/WallRight") in found, "new room's wall fades")
	assert_true(_mesh("Section0/WallRight") not in found, "old room's wall no longer fades")
