extends TestCase

## Six rooms around a hub, to put as many doors on it as a test needs.
class HubShip extends Ship:
	var spokes := 6
	var door_results: Array[Opening] = []

	func _init(spoke_count: int) -> void:
		spokes = spoke_count
		super._init()

	func _build() -> void:
		add_room("hub", Vector3(4, 4, 4), Vector3.ZERO)
		for i in spokes:
			add_room("spoke%d" % i, Vector3(2, 2, 2), Vector3(10 * (i + 1), 0, 0))
			# Every door sits on the hub's +x face: two doors may share a face.
			door_results.append(add_door("s%d" % i, "hub", Room.Face.PLUS_X, "spoke%d" % i, Room.Face.MINUS_X))


class TwoHatchShip extends Ship:
	func _build() -> void:
		add_room("fore", Vector3(2, 2, 2), Vector3(0, 0, 0), Basis.IDENTITY, 1)
		add_room("aft", Vector3(2, 2, 2), Vector3(0, 0, 4))
		add_door("d1", "fore", Room.Face.PLUS_Z, "aft", Room.Face.MINUS_Z)
		add_hatch("hatch-fore", "fore", Room.Face.MINUS_Z)
		add_hatch("hatch-aft", "aft", Room.Face.PLUS_Z)


class GhostDoorShip extends Ship:
	func _build() -> void:
		add_room("a", Vector3(1, 1, 1), Vector3.ZERO)
		add_door("d", "a", Room.Face.PLUS_X, "ghost", Room.Face.MINUS_X)


class SlowSkiff extends Ship:
	func _param_overrides() -> Dictionary:
		return {"transmission_s": 30.0, "tanks": {"O2": {"capacity_mol": 100.0}}}

	func _build() -> void:
		add_room("only", Vector3(1, 1, 1), Vector3.ZERO)


func test_a_room_is_a_box_with_a_volume() -> void:
	var cargo := ShipFixture.make().room("cargo")
	assert_near(cargo.volume, 30.0, 1e-9, "volume is the box's")
	assert_true(cargo.size == Vector3(3, 2.5, 4), "size %s" % cargo.size)
	assert_true(cargo.position == Vector3(0, 0, 7.5), "position %s" % cargo.position)
	assert_true(cargo.orientation == Basis.IDENTITY, "unturned")

func test_a_room_can_be_turned() -> void:
	var ship := Ship.new()
	var room := ship.add_room("seg", Vector3(1, 1, 1), Vector3(5, 0, 0), Ship.yaw(90.0))
	assert_true((room.orientation * Vector3.FORWARD).is_equal_approx(Vector3.LEFT), "yawed a quarter turn")

func test_door_faces_are_recorded_for_both_rooms() -> void:
	var d1 := ShipFixture.make().opening("d1")
	assert_true(d1.face_a == Room.Face.PLUS_Z, "face on cockpit")
	assert_true(d1.face_b == Room.Face.MINUS_Z, "face on main")

func test_a_hatch_records_the_face_of_its_room() -> void:
	assert_true(ShipFixture.make().opening("hatch").face_a == Room.Face.PLUS_Z, "face on cargo")

func test_six_doors_on_one_room_are_allowed_even_on_one_face() -> void:
	var ship := HubShip.new(6)
	assert_true(ship.doors_of("hub").size() == 6, "six doors on the hub")
	assert_true(ship.door_results.all(func(o: Opening) -> bool: return o != null), "none refused")

func test_a_seventh_door_is_an_error_naming_the_room() -> void:
	expect_error("Room 'hub'")
	var ship := HubShip.new(7)
	assert_true(ship.doors_of("hub").size() == 6, "the seventh was not added")
	assert_true(ship.door_results[6] == null, "the seventh is refused")
	assert_true(ship.opening("s6") == null, "and is not on the ship")

func test_a_hatch_counts_toward_a_rooms_six_doors() -> void:
	expect_error("Room 'hub'")
	var ship := HubShip.new(5)
	ship.add_hatch("hatch", "hub", Room.Face.PLUS_Y)
	assert_true(ship.add_hatch("hatch2", "hub", Room.Face.MINUS_Y) == null, "a seventh opening, hatch or not")

func test_a_door_to_an_unknown_room_is_an_error() -> void:
	expect_error("unknown room 'ghost'")
	GhostDoorShip.new()

func test_a_hatch_id_must_start_with_hatch() -> void:
	expect_error("must start with 'hatch'")
	var ship := Ship.new()
	ship.add_room("a", Vector3(1, 1, 1), Vector3.ZERO)
	assert_true(ship.add_hatch("airlock", "a", Room.Face.PLUS_X) == null, "refused")

func test_a_door_id_cannot_start_with_hatch() -> void:
	expect_error("cannot start with 'hatch'")
	var ship := Ship.new()
	assert_true(ship.add_door("hatchway", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")

func test_a_room_id_must_be_typeable() -> void:
	expect_error("Room id 'Big Room' must be lowercase")
	var ship := Ship.new()
	assert_true(ship.add_room("Big Room", Vector3(1, 1, 1), Vector3.ZERO) == null, "refused")
	assert_true(ship.rooms.is_empty(), "nothing added")

func test_a_room_id_cannot_be_outside() -> void:
	expect_error("Room id 'outside' is reserved")
	assert_true(Ship.new().add_room("outside", Vector3(1, 1, 1), Vector3.ZERO) == null, "refused")

func test_a_room_id_cannot_be_empty() -> void:
	expect_error("Room id '' is empty")
	assert_true(Ship.new().add_room("", Vector3(1, 1, 1), Vector3.ZERO) == null, "refused")

func test_a_door_id_must_be_typeable() -> void:
	expect_error("Door id 'Door 1' must be lowercase")
	assert_true(Ship.new().add_door("Door 1", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")

func test_a_door_id_cannot_be_outside() -> void:
	expect_error("Door id 'outside' is reserved")
	assert_true(Ship.new().add_door("outside", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")

func test_a_door_id_cannot_be_a_system_id() -> void:
	expect_error("Door id 'hvac' cannot be a system's id")
	assert_true(Ship.new().add_door("hvac", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")

func test_a_door_id_cannot_be_a_lights_breaker() -> void:
	expect_error("Door id 'light-a' cannot be a system's id or start with 'light-'")
	assert_true(Ship.new().add_door("light-a", "a", Room.Face.PLUS_X, "b", Room.Face.MINUS_X) == null, "refused")

func test_a_hatch_id_must_be_typeable() -> void:
	expect_error("Hatch id 'hatch A' must be lowercase")
	var ship := Ship.new()
	ship.add_room("a", Vector3(1, 1, 1), Vector3.ZERO)
	assert_true(ship.add_hatch("hatch A", "a", Room.Face.PLUS_X) == null, "refused")

func test_the_standard_fleet_builds_without_errors() -> void:
	assert_true(Fleet.standard().ships.size() == 5, "five ships built")

func test_two_hatches_each_expose_their_room() -> void:
	var ship := TwoHatchShip.new()
	assert_true(not ship.exposed["fore"] and not ship.exposed["aft"], "sealed at first")
	ship.set_opening("hatch-aft", true)
	ship.advance(7.0)
	assert_true(ship.exposed["aft"], "aft exposed through its hatch")
	assert_true(not ship.exposed["fore"], "fore still sealed")
	ship.set_opening("hatch-aft", false)
	ship.set_opening("hatch-fore", true)
	ship.advance(7.0)
	assert_true(ship.exposed["fore"], "fore exposed through its hatch")

func test_opening_either_hatch_closes_open_doors() -> void:
	for hatch in ["hatch-fore", "hatch-aft"]:
		var ship := TwoHatchShip.new()
		ship.set_opening("d1", true)
		ship.advance(2.0)
		var outcome := ship.set_opening(hatch, true)
		assert_true(outcome.auto_closed == ["d1"], "%s closes d1: %s" % [hatch, outcome.auto_closed])

func test_a_door_opened_onto_either_open_hatch_warns() -> void:
	var ship := TwoHatchShip.new()
	ship.set_opening("hatch-fore", true)
	ship.advance(1.0)
	assert_true(ship.set_opening("d1", true).onto_open_hatch, "warns")

func test_every_hatch_has_a_breaker_and_hatch_power_draw() -> void:
	var ship := TwoHatchShip.new()
	for id in ["hatch-fore", "hatch-aft"]:
		assert_true(ship.power.has(id), "breaker for %s" % id)
		assert_near(ship.draw_w(id), ship.params.breakers.draw_w.hatch_idle, 1e-9, "%s idle" % id)
	ship.set_opening("hatch-aft", true)
	assert_near(ship.draw_w("hatch-aft"), ship.params.breakers.draw_w.hatch_moving, 1e-9, "moving")

func test_params_default_to_the_base_class_values() -> void:
	var ship := Ship.new()
	assert_near(ship.params.setpoints.o2_kpa, 21.2, 1e-9, "o2 setpoint")
	assert_near(ship.params.tanks.N2.capacity_mol, 8000.0, 1e-9, "N2 tank")
	assert_near(ship.transmission_s, Ship.DEFAULT_TRANSMISSION_S, 1e-9, "link time")

func test_a_subclass_overrides_params_by_merging() -> void:
	var ship := SlowSkiff.new()
	assert_near(ship.transmission_s, 30.0, 1e-9, "link time")
	assert_near(ship.tanks["O2"].capacity, 100.0, 1e-9, "O2 capacity overridden")
	assert_near(ship.params.tanks.O2.start_mol, 3000.0, 1e-9, "the rest of O2 is the default")
	assert_near(ship.params.tanks.N2.capacity_mol, 8000.0, 1e-9, "N2 untouched")

func test_a_caller_override_wins_over_the_subclass() -> void:
	var ship := SlowSkiff.new({"transmission_s": 5.0})
	assert_near(ship.transmission_s, 5.0, 1e-9, "caller's link time")
	assert_near(ship.tanks["O2"].capacity, 100.0, 1e-9, "subclass's tank still applies")

func test_overriding_one_ship_leaves_the_defaults_alone() -> void:
	SlowSkiff.new({"setpoints": {"o2_kpa": 1.0}})
	assert_near(Ship.default_params().setpoints.o2_kpa, 21.2, 1e-9, "defaults are fresh each time")
