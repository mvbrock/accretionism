extends TestCase
## Where a door sits: its position in ship space and its size, and the room face helpers.


func _ship_with_two_rooms() -> Ship:
	var ship := Ship.new()
	ship.add_room("a", Vector3(4, 2, 6), Vector3(10, 0, 0))
	ship.add_room("b", Vector3(4, 2, 6), Vector3(10, 0, 6))
	return ship


func test_a_face_centre_is_half_the_extent_along_the_face_axis() -> void:
	var room := _ship_with_two_rooms().room("a")
	assert_true(room.face_center(Room.Face.PLUS_X).is_equal_approx(Vector3(12, 0, 0)), "+x %s" % room.face_center(Room.Face.PLUS_X))
	assert_true(room.face_center(Room.Face.MINUS_Y).is_equal_approx(Vector3(10, -1, 0)), "-y")
	assert_true(room.face_center(Room.Face.PLUS_Z).is_equal_approx(Vector3(10, 0, 3)), "+z")

func test_face_centres_and_normals_follow_the_rooms_orientation() -> void:
	var ship := Ship.new()
	var room := ship.add_room("a", Vector3(2, 2, 6), Vector3(0, 0, 0), Ship.yaw(90.0))
	var normal := room.face_normal(Room.Face.PLUS_Z)
	assert_true(normal.is_equal_approx(Vector3(1, 0, 0)), "+z turned to +x: %s" % normal)
	assert_true(room.face_center(Room.Face.PLUS_Z).is_equal_approx(Vector3(3, 0, 0)), "centre %s" % room.face_center(Room.Face.PLUS_Z))

func test_face_contains_a_point_on_the_face_only() -> void:
	var room := _ship_with_two_rooms().room("a")
	assert_true(room.face_contains(Room.Face.PLUS_Z, Vector3(11, 0.5, 3)), "on the face")
	assert_true(not room.face_contains(Room.Face.PLUS_Z, Vector3(11, 0.5, 2.5)), "inside, off the face")
	assert_true(not room.face_contains(Room.Face.PLUS_Z, Vector3(13, 0, 3)), "in the plane but off the face")

func test_face_contains_its_own_centre_on_a_turned_room_50_m_out() -> void:
	var ship := Ship.new()
	var turn := Basis(Vector3.RIGHT, deg_to_rad(30.0))
	var room := ship.add_room("a", Vector3(10, 5, 24.54), turn * Vector3(0, -45.8, 0), turn)
	for face in [Room.Face.PLUS_Z, Room.Face.MINUS_Z, Room.Face.PLUS_Y, Room.Face.MINUS_Y]:
		assert_true(room.face_contains(face, room.face_center(face)), "face %d centre" % face)
	var off := room.face_center(Room.Face.MINUS_Z) + room.face_normal(Room.Face.MINUS_Z) * 0.01
	assert_true(not room.face_contains(Room.Face.MINUS_Z, off), "a centimetre off the face")

func test_a_door_between_faces_pointing_the_same_way_is_misplaced() -> void:
	var ship := Ship.new()
	ship.add_room("a", Vector3(2, 2, 2), Vector3.ZERO)
	ship.add_room("b", Vector3(2, 2, 2), Vector3.ZERO)
	ship.add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.PLUS_Z)
	assert_true(ShipChecks.misplaced_doors(ship) == (["a-b faces"] as Array[String]), "got %s" % [ShipChecks.misplaced_doors(ship)])

func test_a_door_where_the_rooms_bend_by_30_degrees_is_in_place() -> void:
	var ship := Ship.new()
	var turn := Basis(Vector3.RIGHT, deg_to_rad(30.0))
	var length := 2.0 * 10.0 * tan(deg_to_rad(15.0))
	ship.add_room("a", Vector3(2, 2, length), Vector3(0, -10, 0))
	ship.add_room("b", Vector3(2, 2, length), turn * Vector3(0, -10, 0), turn)
	ship.add_door("a-b", "a", Room.Face.MINUS_Z, "b", Room.Face.PLUS_Z)
	assert_true(ShipChecks.misplaced_doors(ship).is_empty(), "got %s" % [ShipChecks.misplaced_doors(ship)])

func test_a_door_defaults_to_the_centre_of_its_first_rooms_face() -> void:
	var ship := _ship_with_two_rooms()
	var door := ship.add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.MINUS_Z)
	assert_true(door.position.is_equal_approx(Vector3(10, 0, 3)), "position %s" % door.position)
	assert_true(door.size == Ship.DOOR_SIZE_M, "size %s" % door.size)

func test_a_door_can_sit_off_centre() -> void:
	var ship := _ship_with_two_rooms()
	var door := ship.add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.MINUS_Z, Vector2(1, 1), Vector3(11, -0.5, 3))
	assert_true(door.position == Vector3(11, -0.5, 3), "position %s" % door.position)
	assert_true(door.size == Vector2(1, 1), "size")

func test_a_door_naming_a_room_added_later_still_defaults_to_its_face_centre() -> void:
	var ship := LateRoomShip.new()
	assert_true(ship.opening("a-b").position.is_equal_approx(Vector3(0, 0, 1)), "position %s" % ship.opening("a-b").position)

func test_a_hatch_has_a_position_and_size_too() -> void:
	var ship := _ship_with_two_rooms()
	var hatch := ship.add_hatch("hatch", "b", Room.Face.PLUS_Z)
	assert_true(hatch.position.is_equal_approx(Vector3(10, 0, 9)), "position %s" % hatch.position)
	assert_true(hatch.size == Ship.HATCH_SIZE_M, "size")

func test_door_strength_scales_linearly_with_area() -> void:
	var ship := _ship_with_two_rooms()
	var big := ship.add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.MINUS_Z, Vector2(2, 4))
	assert_near(big.conductance, 40.0, 1e-9, "four times the reference area")
	assert_near(big.mixing, 2.0, 1e-9, "mixing")
	assert_near(big.heat_conductance, 400.0, 1e-9, "heat")

func test_a_duplicate_room_id_is_an_error_naming_the_id() -> void:
	expect_error("Room 'a'")
	var ship := _ship_with_two_rooms()
	assert_true(ship.add_room("a", Vector3.ONE, Vector3.ZERO) == null, "refused")
	assert_true(ship.rooms.size() == 2, "not added")

func test_a_duplicate_door_id_is_an_error_naming_the_id() -> void:
	expect_error("Opening 'a-b'")
	var ship := _ship_with_two_rooms()
	ship.add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.MINUS_Z)
	assert_true(ship.add_door("a-b", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")
	assert_true(ship.openings.size() == 1, "not added")

func test_a_duplicate_hatch_id_is_an_error_naming_the_id() -> void:
	expect_error("Opening 'hatch'")
	var ship := _ship_with_two_rooms()
	ship.add_hatch("hatch", "a", Room.Face.MINUS_X)
	assert_true(ship.add_hatch("hatch", "b", Room.Face.MINUS_X) == null, "refused")


class LateRoomShip extends Ship:
	func _build() -> void:
		add_door("a-b", "a", Room.Face.PLUS_Z, "b", Room.Face.MINUS_Z)
		add_room("a", Vector3(2, 2, 2), Vector3.ZERO)
		add_room("b", Vector3(2, 2, 2), Vector3(0, 0, 2))
