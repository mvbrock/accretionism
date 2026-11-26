extends TestCase


func test_loads_every_shipped_ship_by_file_name() -> void:
	var fleet := Fleet.load_dir(Main.SHIPS_DIR)
	assert_true(fleet != null, "the shipped fleet loads, problem: '%s'" % Fleet.last_problem)
	if fleet == null:
		return
	assert_true(fleet.names() == PackedStringArray(["kestrel", "wren"]), "got %s" % fleet.names())
	assert_true(fleet.ships.wren.room("treehouse") != null, "wren has the treehouse")
	assert_true(fleet.ships.kestrel.room("treehouse") == null, "kestrel does not")


func test_advance_runs_every_ship() -> void:
	var fleet := Fleet.load_dir(Main.SHIPS_DIR)
	fleet.advance(2.0)
	for ship_name in fleet.ships:
		assert_near(fleet.ships[ship_name].time_s, 2.0, 1e-6, "%s advanced" % ship_name)


func test_missing_folder() -> void:
	assert_true(Fleet.load_dir("user://no_such_ships") == null, "no fleet")
	assert_true(Fleet.last_problem == "user://no_such_ships: folder is missing", "got '%s'" % Fleet.last_problem)


func _dir_with(files: Dictionary) -> String:
	var dir := "user://fleet_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for old in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(old))
	for file_name in files:
		var file := FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
		file.store_string(files[file_name])
		file.close()
	return dir


func test_folder_without_ship_files() -> void:
	var dir := _dir_with({"notes.txt": "hello"})
	assert_true(Fleet.load_dir(dir) == null, "no fleet")
	assert_true(Fleet.last_problem == "user://fleet_test: no ship files", "got '%s'" % Fleet.last_problem)


func test_untypeable_file_name() -> void:
	var dir := _dir_with({"Big Ship.json": FileAccess.get_file_as_string(ShipFixture.KESTREL_PATH)})
	assert_true(Fleet.load_dir(dir) == null, "no fleet")
	assert_true(Fleet.last_problem.begins_with("user://fleet_test/Big Ship.json: the ship's name"), "got '%s'" % Fleet.last_problem)


func test_bad_ship_file_names_the_file() -> void:
	var dir := _dir_with({"a.json": FileAccess.get_file_as_string(ShipFixture.KESTREL_PATH), "b.json": "[]"})
	expect_error("is not a JSON object")
	assert_true(Fleet.load_dir(dir) == null, "one bad file fails the fleet")
	assert_true(Fleet.last_problem == "user://fleet_test/b.json: file is not a JSON object", "got '%s'" % Fleet.last_problem)
