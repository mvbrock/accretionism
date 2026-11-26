class_name Fleet
extends RefCounted
## Every ship in a folder of ship files, each named by its file: `kestrel.json`
## is the ship `kestrel`. Hidden files are skipped. All of them run on the one clock, whether or not the
## console is connected to them.

## What was wrong with the most recent load, naming the file; empty when it succeeded.
static var last_problem := ""

## ship name -> Ship, in name order.
var ships := {}


static func load_dir(dir: String) -> Fleet:
	last_problem = ""
	if not DirAccess.dir_exists_absolute(dir):
		return _fail(dir, "folder is missing")
	var files := Array(DirAccess.get_files_at(dir)).filter(
		func(file: String) -> bool: return file.get_extension() == "json" and not file.begins_with("."))
	if files.is_empty():
		return _fail(dir, "no ship files")
	files.sort()
	var fleet := Fleet.new()
	for file in files:
		var path := dir.path_join(file)
		var ship_name: String = file.get_basename()
		if not CommandInterpreter.is_typeable(ship_name):
			return _fail(path, "the ship's name comes from the file name, which must be lowercase and contain no whitespace")
		var ship := ShipLoader.load_file(path)
		if ship == null:
			return _fail(path, ShipLoader.last_problem)
		fleet.ships[ship_name] = ship
	return fleet


static func _fail(path: String, problem: String) -> Fleet:
	last_problem = "%s: %s" % [path.trim_prefix("res://"), problem]
	return null


func names() -> PackedStringArray:
	return PackedStringArray(ships.keys())


func advance(sim_seconds: float, step_s := Ship.STEP_S) -> void:
	for ship in ships.values():
		(ship as Ship).advance(sim_seconds, step_s)
