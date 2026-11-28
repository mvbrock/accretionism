extends TestCase

const NAME := 0
const ID := 1
const ORIGIN := 2
const LOCATION := 3
const DESTINATION := 4
const PROGRESS := 5


func _party_where(sim: Sim, condition: Callable) -> Party:
	for party in sim.parties:
		if condition.call(party):
			return party
	return null


func _table(sim: Sim) -> PassengerTable:
	var table := PassengerTable.new()
	own(table)
	table.show_passengers(sim.passengers_by_id.values())
	table.refresh(sim)
	return table


func _visible_ids(table: PassengerTable) -> Array:
	var ids := []
	for item in table.get_root().get_children():
		if item.visible:
			ids.append(item.get_text(ID))
	return ids


func test_row_states() -> void:
	var sim := SharedSim.get_sim()
	var aboard := _party_where(sim, func(party: Party) -> bool: return party.aboard != null)
	var member := aboard.members[0]
	var row := TableModel.row(sim, member)
	assert_true(row[NAME] == member.full_name and row[ID] == member.id, "name and id lead")
	assert_true(row[ORIGIN] == Fleet.target_name(aboard.origin), "origin is a body name")
	assert_true(row[LOCATION] == aboard.aboard.ship.name, "the ship's name while aboard, got %s" % row[LOCATION])
	assert_true(row[DESTINATION] == Fleet.target_name(aboard.destination), "the destination shows")
	assert_true(row[PROGRESS].ends_with("%"), "progress is a percentage, got %s" % row[PROGRESS])

	var at_body := _party_where(sim, func(party: Party) -> bool:
		return party.aboard == null and party.place is int and party.state == Party.State.TRAVELLING)
	assert_true(at_body != null, "someone is waiting at a body")
	row = TableModel.row(sim, at_body.members[0])
	assert_true(row[LOCATION] == Fleet.target_name(at_body.place), "a body name while at a body")

	var unplanned := Sim.new(false, false)
	var held := unplanned.parties[0]
	row = TableModel.row(unplanned, held.members[0])
	assert_true(row[PROGRESS] == "-", "HELD with no route shows -, got %s" % row[PROGRESS])
	assert_true(row[DESTINATION] == Fleet.target_name(held.destination), "HELD still shows its destination")

	held.state = Party.State.ARRIVED
	row = TableModel.row(unplanned, held.members[0])
	assert_true(row[DESTINATION] == "Arrived" and row[PROGRESS] == "100.00%", "ARRIVED says so, got %s" % [row])


func test_percent_floor() -> void:
	assert_true(TableModel.percent(0.41209) == "41.20%", "rounds down, got %s" % TableModel.percent(0.41209))
	assert_true(TableModel.percent(0.99999) == "99.99%", "100 shows only on arrival")
	assert_true(TableModel.percent(1.0) == "100.00%", "arrival")
	assert_true(TableModel.percent(0.0) == "0.00%", "start")


func test_sort_progress_numeric() -> void:
	var sim := SharedSim.get_sim()
	var key: Variant = TableModel.sort_key(sim, sim.parties[0].members[0], TableModel.PROGRESS_COLUMN)
	assert_true(key is float, "progress sorts as a number")
	assert_true(TableModel.sort_key(sim, sim.parties[0].members[0], NAME) is String, "other columns sort as text")

	var table := _table(sim)
	table.set_sort(PROGRESS, true)
	table.refresh(sim)
	var previous := -INF
	for item in table.get_root().get_children():
		var progress := sim.progress(sim.parties[item.get_metadata(0).party_id])
		assert_true(progress >= previous, "ascending by number, %s after %s" % [progress, previous])
		previous = progress


func test_filter_matches_any_cell() -> void:
	var sim := SharedSim.get_sim()
	var table := _table(sim)
	var passengers := sim.passengers_by_id.values()
	var target: Passenger = passengers[5]
	table.set_filter(target.id.to_lower())
	table.refresh(sim)
	assert_true(_visible_ids(table) == [target.id], "the id matches, got %s" % [_visible_ids(table)])
	table.set_filter(sim.location_name(target).to_upper())
	table.refresh(sim)
	assert_true(_visible_ids(table).has(target.id), "location matches ignoring case")
	table.set_filter("")
	table.refresh(sim)
	assert_true(_visible_ids(table).size() == passengers.size(), "an empty filter shows everyone")


func test_selection_survives_sort() -> void:
	var sim := SharedSim.get_sim()
	var table := _table(sim)
	var chosen: Passenger = sim.passengers_by_id.values()[100]
	table.show_selected(chosen)
	for column in PassengerTable.COLUMN_TITLES.size():
		table.set_sort(column, false)
		table.refresh(sim)
		assert_true(table.get_selected() != null and table.get_selected().get_metadata(0) == chosen, "still selected after sorting column %d" % column)
	table.set_sort(NAME, false)
	table.refresh(sim)
	var names := table.get_root().get_children().map(func(item: TreeItem) -> String: return item.get_text(NAME))
	assert_true(names[0] >= names[names.size() - 1], "descending by name")


func test_filter_hides_selected_but_keeps_it() -> void:
	var sim := SharedSim.get_sim()
	var table := _table(sim)
	var chosen: Passenger = sim.passengers_by_id.values()[10]
	var other: Passenger = sim.passengers_by_id.values()[11]
	table.show_selected(chosen)
	table.set_filter(other.id)
	table.refresh(sim)
	assert_true(table.get_selected() == null, "the hidden row is not shown selected")
	table.set_filter("")
	table.refresh(sim)
	assert_true(table.get_selected() != null and table.get_selected().get_metadata(0) == chosen, "the selection returns with the row")


func test_history_growth_highlights_the_row() -> void:
	var sim := SharedSim.get_sim()
	var table := _table(sim)
	var touched: Passenger = sim.passengers_by_id.values()[3]
	var item: TreeItem = table.get_root().get_child(3)
	assert_true(item.get_custom_bg_color(0) != PassengerTable.HIGHLIGHT_COLOR, "untouched rows are plain")
	touched.add_history(sim.day, "test event", "test")
	table.refresh(sim)
	assert_true(table.get_root().get_children().any(func(row: TreeItem) -> bool:
		return row.get_metadata(0) == touched and row.get_custom_bg_color(0) == PassengerTable.HIGHLIGHT_COLOR), "the touched row is highlighted")
	touched.history.pop_back()


func test_scroll_follows_only_explicit_selection() -> void:
	var sim := SharedSim.get_sim()
	var table := _table(sim)
	table.size = Vector2(600, 300)
	var last: Passenger = sim.passengers_by_id.values()[-1]
	table.show_selected(last)
	await physics_frames(2)
	assert_true(table.get_scroll().y > 0.0, "an explicit selection scrolls to the row")
	table.scroll_to_item(table.get_root().get_first_child()) # the user scrolling away
	table._last_reapply_msec = 0
	table.refresh(sim)
	await physics_frames(2)
	assert_true(table.get_scroll().y == 0.0, "a periodic refresh leaves the scroll alone")
	table.set_sort(0, false)
	table.refresh(sim)
	await physics_frames(2)
	assert_true(table.get_scroll().y > 0.0, "a sort change scrolls back to the selection")
