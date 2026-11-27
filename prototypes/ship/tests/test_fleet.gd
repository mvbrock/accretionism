extends TestCase

var fleet: Fleet
var ring: RingShip
var skiff: SkiffShip
var player: Player
var rig: CameraRig
var fader: OcclusionFader


func _setup() -> void:
	player = load("res://scenes/player.tscn").instantiate()
	player.drive_by_code = true
	own(player)
	rig = CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	rig.target = player
	own(rig)
	fader = OcclusionFader.new()
	fader.camera = camera
	fader.target = player
	own(fader)
	fader.set_process(false)
	fleet = Fleet.new()
	ring = RingShip.new()
	ring.name = "Ring"
	skiff = SkiffShip.new()
	skiff.name = "Skiff"
	fleet.add_child(ring)
	fleet.add_child(skiff)
	fleet.player = player
	fleet.rig = rig
	fleet.fader = fader
	own(fleet)  # last: its _ready boards the player, which needs the player's _ready first
	await physics_frames(3)


## Distance from the player to `point`, ignoring height: a floating player rises to FLOAT_HEIGHT.
func _floor_plan_distance(point: Vector3) -> float:
	return Vector2(player.global_position.x - point.x, player.global_position.z - point.z).length()


func test_starts_on_first_ship() -> void:
	await _setup()
	assert_true(fleet.active == ring, "the ring is active")
	assert_true(ring.visible and not skiff.visible, "only the ring is shown")
	assert_near(player.global_position.distance_to(ring.spawn_point()), 0.0, 0.1, "player at the ring's spawn")


func test_next_ship_switches_and_wires() -> void:
	await _setup()
	fleet.next_ship()
	await physics_frames(2)
	assert_true(fleet.active == skiff, "the skiff is active")
	assert_true(player.ship == skiff and rig.ship == skiff and fader.ship == skiff, "player, rig and fader follow")
	assert_near(_floor_plan_distance(skiff.spawn_point()), 0.0, 0.1, "player above the skiff's spawn")
	assert_true(not player.gravity_enabled, "no gravity aboard the skiff")
	assert_true(rig.rotation.x == 0.0, "the rig does not roll")


func test_hidden_ship_does_not_collide() -> void:
	await _setup()
	fleet.next_ship()
	await physics_frames(2)
	var down := RingGeometry.section_down(3)
	var query := PhysicsRayQueryParameters3D.create(down * 47.0, down * 49.0)
	var hit := ring.get_world_3d().direct_space_state.intersect_ray(query)
	assert_true(hit.is_empty(), "the hidden ring's floor is not there")


func test_remembers_position_per_ship() -> void:
	await _setup()
	player.move_input = Vector2(0, 1)
	await physics_frames(30)
	player.move_input = Vector2.ZERO
	var recorded := player.global_position
	fleet.next_ship()
	await physics_frames(5)
	fleet.next_ship()
	await physics_frames(2)
	assert_near(player.global_position.distance_to(recorded), 0.0, 0.05, "back where it left the ring")
	fleet.next_ship()
	await physics_frames(2)
	assert_near(_floor_plan_distance(skiff.spawn_point()), 0.0, 0.1, "the skiff still starts at its spawn")


func test_next_ship_wraps() -> void:
	await _setup()
	fleet.next_ship()
	fleet.next_ship()
	assert_true(fleet.active == ring, "back on the ring")


func test_one_world_environment() -> void:
	await _setup()
	var all := fleet.find_children("*", "WorldEnvironment", true, false)
	assert_true(all.size() == 1, "one WorldEnvironment under the fleet (got %d)" % all.size())
	for ship in fleet.ships():
		assert_true(ship.find_children("*", "WorldEnvironment", true, false).is_empty(), "none under %s" % ship.name)


func test_emits_ship_changed() -> void:
	await _setup()
	var received: Array[Ship] = []
	fleet.ship_changed.connect(func(ship: Ship) -> void: received.append(ship))
	fleet.next_ship()
	assert_true(received.size() == 1 and received[0] == skiff, "ship_changed carried the skiff")
