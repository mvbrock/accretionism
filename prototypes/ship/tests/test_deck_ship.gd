extends TestCase

const PITCH := DeckShip.PITCH


func _make_ship(decks := 2) -> DeckShip:
	var ship := DeckShip.new()
	ship.deck_count = decks
	own(ship)
	await physics_frames(2)
	return ship


func _ray(from: Vector3, to: Vector3, mask: int = 0xFFFFFFFF) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


func test_has_gravity_and_up() -> void:
	var ship := await _make_ship()
	assert_true(ship.has_gravity(), "gravity")
	assert_true(ship.up_at(Vector3.ZERO) == Vector3.UP, "up is +Y")


func test_rooms() -> void:
	var ship := await _make_ship()
	assert_true(ship.room_at(Vector3(0, 1, 0)) == "Deck0", "lower deck")
	assert_true(ship.room_at(Vector3(0, 5, 0)) == "Deck1", "upper deck")
	assert_true(ship.room_at(Vector3(3.5, 2, 3.5)) == "Pipe", "in the shaft")
	assert_true(ship.room_at(Vector3(0, 50, 0)) == "Deck1", "clamped to the top deck")


func test_floors() -> void:
	await _make_ship()
	var low := _ray(Vector3(0, 3, 0), Vector3(0, -1, 0), Ship.FLOOR_LAYER)
	assert_true(not low.is_empty(), "lower floor hit")
	if not low.is_empty():
		assert_near(low.position.y, 0.0, 0.01, "lower floor top")
	var high := _ray(Vector3(0, 7, 0), Vector3(0, 2, 0), Ship.FLOOR_LAYER)
	assert_true(not high.is_empty(), "upper floor hit")
	if not high.is_empty():
		assert_near(high.position.y, PITCH, 0.01, "upper floor top")


func test_slab_has_hole_over_pipe() -> void:
	await _make_ship()
	var hit := _ray(Vector3(3.5, PITCH + 2, 3.5), Vector3(3.5, -1, 3.5))
	assert_true(not hit.is_empty(), "stops on the lower floor")
	if not hit.is_empty():
		assert_true(hit.position.y < 0.04, "passes the slab (y = %.3f)" % hit.position.y)
		assert_near(hit.position.y, 0.0, 0.01, "lower floor top")


func test_doorway_blocked_only_for_hatch() -> void:
	await _make_ship()
	var from := Vector3(3.5, 1, 1.5)
	var to := Vector3(3.5, 1, 3.5)
	assert_true(not _ray(from, to, Ship.HATCH_LAYER).is_empty(), "the hatch blocks")
	assert_true(_ray(from, to, Ship.WORLD_LAYER).is_empty(), "the doorway is open to the world")


func test_ladder_landings() -> void:
	var ship := await _make_ship()
	assert_true(ship.ladders.size() == 1, "one ladder")
	if ship.ladders.size() != 1:
		return
	var ladder := ship.ladders[0]
	assert_near(ladder.length, PITCH, 0.001, "length")
	assert_true(ladder.landings.size() == 2, "two landings")
	if ladder.landings.size() != 2:
		return
	assert_near(ladder.landings[1].exit.y, PITCH + 0.05, 0.001, "upper exit height")
	for landing in ladder.landings:
		assert_true(ship.room_at(landing.exit) != "Pipe", "exit outside the pipe")


func _meshes(ship: Ship, paths: Array) -> Array:
	var meshes := []
	for path in paths:
		meshes.append(ship.get_node(path + "/Mesh"))
	return meshes


func test_room_fade_on_deck0() -> void:
	var ship := await _make_ship()
	var faded := ship.room_fade_meshes(Vector3(0, 1, 0), Vector3(-0.58, -0.58, -0.58))
	var expected := _meshes(ship, ["Deck1/Slab0a", "Deck1/Slab0b", "Deck1/Slab0c", "Deck1/Slab0d",
			"Deck0/WallRight", "Deck0/WallAft"])
	assert_true(faded.size() == expected.size(), "fade count (got %d)" % faded.size())
	for mesh in expected:
		assert_true(faded.has(mesh), "%s fades" % mesh.get_parent().get_path())
	for path in ["Deck0/WallLeft", "Deck0/WallFore"]:
		assert_true(not faded.has(ship.get_node(path + "/Mesh")), "%s stays" % path)


func test_deck_count_property() -> void:
	var ship := await _make_ship(3)
	assert_true(ship.has_node("Deck2"), "third deck")
	assert_true(ship.has_node("Deck2/Roof"), "roof on the top deck")
	assert_true(ship.ladders.size() == 1, "one ladder")
	if ship.ladders.size() == 1:
		assert_near(ship.ladders[0].length, 2.0 * PITCH, 0.001, "ladder length")
		assert_true(ship.ladders[0].landings.size() == 3, "three landings")
