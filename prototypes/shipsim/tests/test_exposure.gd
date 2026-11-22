extends TestCase

func _check(actual: Dictionary, expected: Dictionary, message: String) -> void:
	assert_true(actual == expected, "%s (got %s)" % [message, str(actual)])

func _exposed(d1: float, d2: float, hatch: float) -> Dictionary:
	var openings: Array[Opening] = [
		Opening.new("d1", "cockpit", "main", 2.0),
		Opening.new("d2", "main", "cargo", 2.0),
		Opening.new("hatch", "cargo", Opening.OUTSIDE, 6.0),
	]
	openings[0].fraction = d1
	openings[1].fraction = d2
	openings[2].fraction = hatch
	var ids: Array[String] = ["cockpit", "main", "cargo"]
	return Exposure.exposed(ids, openings)

func test_hatch_closed_exposes_nothing() -> void:
	for d1 in [0.0, 1.0]:
		for d2 in [0.0, 1.0]:
			_check(_exposed(d1, d2, 0.0), {"cockpit": false, "main": false, "cargo": false}, "hatch closed, d1 %s d2 %s" % [d1, d2])

func test_d2_closed_hatch_open_exposes_cargo() -> void:
	for d1 in [0.0, 1.0]:
		_check(_exposed(d1, 0.0, 1.0), {"cockpit": false, "main": false, "cargo": true}, "only cargo, d1 %s" % d1)

func test_d1_closed_d2_open_hatch_open_exposes_main_and_cargo() -> void:
	_check(_exposed(0.0, 1.0, 1.0), {"cockpit": false, "main": true, "cargo": true}, "main and cargo")

func test_all_open_exposes_all_three() -> void:
	_check(_exposed(1.0, 1.0, 1.0), {"cockpit": true, "main": true, "cargo": true}, "all three")

func test_partly_open_hatch_exposes() -> void:
	_check(_exposed(0.0, 0.0, 0.01), {"cockpit": false, "main": false, "cargo": true}, "a crack is enough")
