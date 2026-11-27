extends TestCase


func _fleet() -> Fleet:
	Orbits.configure({Orbits.Body.EARTH: 0.0, Orbits.Body.MOON: 0.0, Orbits.Body.MARS: 45.0})
	var fleet := Fleet.new()
	fleet.cyclers.append(Cycler.new("Aldrin I", Cycler.Direction.UP, 0.0))
	fleet.cyclers.append(Cycler.new("Aldrin II", Cycler.Direction.DOWN, 130.0))
	fleet.transports.append(Transport.parked_at("Kestrel", Orbits.Body.EARTH))
	fleet.transports.append(Transport.docked_to("Wren", fleet.cyclers[0]))
	fleet.transports.append(Transport.parked_at("Heron", Orbits.Body.EARTH))
	return fleet


func test_rows_are_cyclers_then_transports_in_fleet_order() -> void:
	var rows := TableModel.rows(_fleet())
	var ship_names := rows.map(func(row: PackedStringArray) -> String: return row[0])
	assert_true(ship_names == ["Aldrin I", "Aldrin II", "Kestrel", "Wren", "Heron"], "got %s" % [ship_names])


func test_parked_row() -> void:
	var rows := TableModel.rows(_fleet())
	assert_true(rows[2] == PackedStringArray(["Kestrel", "Earth", "-", "-"]), "got %s" % [rows[2]])


func test_docked_row() -> void:
	var rows := TableModel.rows(_fleet())
	assert_true(rows[3] == PackedStringArray(["Wren", "Aldrin I", "-", "-"]), "got %s" % [rows[3]])


func test_in_flight_row() -> void:
	var fleet := _fleet()
	var transport := fleet.transports[2]
	fleet.depart(transport, Orbits.Body.MARS)
	fleet.advance_to(transport.t0 + 0.379 * (transport.t_arrive - transport.t0))
	var row := TableModel.rows(fleet)[4]
	assert_true(row == PackedStringArray(["Heron", "Earth", "37.90%", "Mars"]), "got %s" % [row])


func test_in_flight_row_names_a_cycler_destination() -> void:
	var fleet := _fleet()
	fleet.advance_to(30.0)
	var transport := fleet.transports[0]
	fleet.depart(transport, fleet.cyclers[1])
	assert_true(TableModel.rows(fleet)[2][3] == "Aldrin II", "destination is the cycler's name")


func test_cycler_row() -> void:
	var fleet := _fleet()
	fleet.advance_to(73.0)
	var row := TableModel.rows(fleet)[0]
	assert_true(row == PackedStringArray(["Aldrin I", "Earth", "50.00%", "-"]), "got %s" % [row])


func test_cycler_on_its_long_leg_names_the_last_planet() -> void:
	var fleet := _fleet()
	fleet.advance_to(200.0)
	assert_true(TableModel.rows(fleet)[0][1] == "Mars", "Aldrin I passed Mars on day 146")


func test_progress_rounds_down_so_100_shows_only_on_arrival() -> void:
	assert_true(TableModel.percent(0.99999) == "99.99%", "got %s" % TableModel.percent(0.99999))
	assert_true(TableModel.percent(1.0) == "100.00%", "got %s" % TableModel.percent(1.0))
