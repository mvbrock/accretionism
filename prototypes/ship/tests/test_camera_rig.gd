extends TestCase


func _make_rig() -> Array:
	var target := Node3D.new()
	target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # tests move it outside physics ticks
	own(target)
	var rig := CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	rig.target = target
	rig.ship = own(RingShip.new())
	own(rig)
	return [rig, target]


func test_player_stays_at_local_bottom() -> void:
	var made := _make_rig()
	var rig: CameraRig = made[0]
	var target: Node3D = made[1]
	for k in [0, 3, 6, 11]:
		target.global_position = RingGeometry.section_down(k) * 48.0 + Vector3(2, 0, 0)
		rig.snap()
		var local := rig.to_local(target.global_position)
		assert_near(local.z, 0.0, 0.001, "local z at section %d" % k)
		assert_true(local.y < 0.0, "below axis at section %d" % k)
		assert_near(local.x, 2.0, 0.001, "local x at section %d" % k)


func test_rotation_wraps_the_short_way() -> void:
	var made := _make_rig()
	var rig: CameraRig = made[0]
	var target: Node3D = made[1]
	target.global_position = RingGeometry.section_down(5) * 48.0
	rig.snap()
	var before := rig.rotation.x
	target.global_position = RingGeometry.section_down(7) * 48.0
	rig.update_rig(1.0 / 60.0)
	assert_near(rad_to_deg(wrapf(rig.rotation.x - before, -PI, PI)), 60.0, 0.01, "rotates +60° the short way")


func test_camera_looks_down_at_player() -> void:
	var made := _make_rig()
	var rig: CameraRig = made[0]
	var target: Node3D = made[1]
	target.global_position = RingGeometry.section_down(2) * 48.0
	rig.snap()
	var camera: Camera3D = rig.get_node("Camera")
	var forward_local := rig.global_basis.inverse() * -camera.global_basis.z
	assert_true(forward_local.y < 0.0, "camera looks downward in the rig frame")
	assert_true(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic")
	# The player sits on the camera's center line.
	var to_target := target.global_position - camera.global_position
	assert_near(to_target.normalized().dot(-camera.global_basis.z), 1.0, 0.001, "player centered")


func test_physics_interpolation_enabled_and_rig_opts_out() -> void:
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation", false), "physics interpolation on")
	var made := _make_rig()
	var rig: CameraRig = made[0]
	assert_true(rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
			"rig is positioned in _process, so it must not be interpolated itself")


func test_rig_does_not_roll_for_a_ship_without_roll() -> void:
	var made := _make_rig()
	var rig: CameraRig = made[0]
	var target: Node3D = made[1]
	rig.ship = own(Ship.new())
	target.global_position = RingGeometry.section_down(4) * 48.0
	rig.snap()
	rig.update_rig(1.0 / 60.0)
	assert_near(rig.rotation.x, 0.0, 0.0, "no roll")
