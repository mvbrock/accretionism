extends TestCase

const CYCLER_NAMES := ["Aldrin I", "Aldrin II", "Aldrin III", "Aldrin IV", "Aldrin V", "Aldrin VI"]


func _data(transports: Array, seed_value: int = 1) -> Dictionary:
	var cyclers := []
	for i in CYCLER_NAMES.size():
		cyclers.append({name = CYCLER_NAMES[i], direction = "UP" if i % 2 == 0 else "DOWN", phase_day = 130.0 * i})
	return {
		seed = seed_value,
		epoch_angles_deg = {Earth = 0.0, Moon = 0.0, Mars = 45.0},
		timetable = {cycle_days = 780.0, short_leg_days = 146.0, long_leg_days = 634.0},
		cyclers = cyclers,
		transports = transports,
	}


func _random_transports(count: int) -> Array:
	var transports := []
	for i in count:
		transports.append({name = "Ship %d" % i, origin = "random"})
	return transports


## "Earth", "Moon", ... or the host cycler's name, one entry per transport.
func _places(fleet: Fleet) -> Array:
	return fleet.transports.map(func(t: Transport) -> String:
		return t.host.name if t.state == Transport.State.DOCKED else Orbits.body_name(t.body))


func test_loads_shipped_file() -> void:
	var fleet := FleetLoader.load_file("res://data/fleet.json")
	assert_true(fleet != null, "shipped file loads")
	if fleet == null:
		return
	assert_true(fleet.cyclers.size() == 6, "6 cyclers, got %d" % fleet.cyclers.size())
	assert_true(fleet.transports.size() == 30, "30 transports, got %d" % fleet.transports.size())
	assert_true(fleet.transports.all(func(t: Transport) -> bool: return t.state != Transport.State.IN_TRANSIT),
		"every transport starts parked or docked")
	var phases := fleet.cyclers.map(func(c: Cycler) -> float: return c.phase_day)
	assert_true(phases == [0.0, 130.0, 260.0, 390.0, 520.0, 650.0], "cyclers are 130 days apart")
	assert_true(fleet.cyclers.map(func(c: Cycler) -> int: return c.direction) == [0, 1, 0, 1, 0, 1], "alternating UP and DOWN")


func test_same_seed_same_fleet() -> void:
	var first := FleetLoader.from_dict(_data(_random_transports(30), 7))
	var second := FleetLoader.from_dict(_data(_random_transports(30), 7))
	var other_seed := FleetLoader.from_dict(_data(_random_transports(30), 8))
	assert_true(_places(first) == _places(second), "same seed, same origins")
	assert_true(_places(first) != _places(other_seed), "different seed, different origins")


func test_random_origin_spread() -> void:
	var fleet := FleetLoader.from_dict(_data(_random_transports(900)))
	var counts := {}
	for place in _places(fleet):
		counts[place] = counts.get(place, 0) + 1
	assert_true(counts.size() == 9, "all 9 origins used, got %d" % counts.size())
	for place in counts:
		assert_true(counts[place] >= 70 and counts[place] <= 130, "%s got %d of 900" % [place, counts[place]])


func test_explicit_origin() -> void:
	var fleet := FleetLoader.from_dict(_data([{name = "A", origin = "Moon"}, {name = "B", origin = "Aldrin III"}]))
	assert_true(fleet.transports[0].state == Transport.State.AT_BODY and fleet.transports[0].body == Orbits.Body.MOON, "parked at the Moon")
	assert_true(fleet.transports[1].state == Transport.State.DOCKED and fleet.transports[1].host == fleet.cyclers[2], "docked to Aldrin III")


func test_explicit_origins_do_not_shift_the_random_draw() -> void:
	var all_random := FleetLoader.from_dict(_data([{name = "A", origin = "random"}, {name = "B", origin = "random"}]))
	var first_fixed := FleetLoader.from_dict(_data([{name = "A", origin = "Moon"}, {name = "B", origin = "random"}]))
	assert_true(_places(all_random)[0] == _places(first_fixed)[1], "the first random transport gets the first draw")


func test_duplicate_name_fails() -> void:
	expect_error("duplicate ship name 'A'")
	expect_error("duplicate ship name 'Aldrin I'")
	var fleet := FleetLoader.from_dict(_data([{name = "A", origin = "Earth"}, {name = "A", origin = "Mars"}]))
	assert_true(fleet == null, "duplicate transport name")
	var clash_with_cycler := FleetLoader.from_dict(_data([{name = "Aldrin I", origin = "Earth"}]))
	assert_true(clash_with_cycler == null, "transport named like a cycler")


func test_unknown_origin_fails() -> void:
	expect_error("unknown origin 'Jupiter'")
	assert_true(FleetLoader.from_dict(_data([{name = "A", origin = "Jupiter"}])) == null, "unknown origin")


func test_unknown_direction_fails() -> void:
	expect_error("unknown direction 'SIDEWAYS'")
	var data := _data([])
	data.cyclers[0].direction = "SIDEWAYS"
	assert_true(FleetLoader.from_dict(data) == null, "unknown direction")


func test_missing_file_fails() -> void:
	expect_error("is missing or empty")
	assert_true(FleetLoader.load_file("res://data/nope.json") == null, "missing file")


func test_inconsistent_timetable_fails() -> void:
	expect_error("must equal the cycle")
	var data := _data([])
	data.timetable.long_leg_days = 600.0
	assert_true(FleetLoader.from_dict(data) == null, "short + long leg must equal the cycle")


func test_timetable_and_epoch_are_applied() -> void:
	var data := _data([])
	data.epoch_angles_deg.Earth = 90.0
	data.timetable.cycle_days = 800.0
	data.timetable.long_leg_days = 654.0
	FleetLoader.from_dict(data)
	assert_near(Orbits.body_position(Orbits.Body.EARTH, 0.0).normalized().y, 1.0, 1e-4, "epoch angle applied")
	assert_near(Cycler.cycle_days, 800.0, 0.0, "cycle length applied")
	FleetLoader.from_dict(_data([]))
	assert_near(Cycler.cycle_days, 780.0, 0.0, "cycle length restored by the next load")

