extends TestCase


func _panel(passenger: Passenger) -> DetailPanel:
	var panel := DetailPanel.new()
	own(panel)
	panel.show_passenger(SharedSim.get_sim(), passenger)
	return panel


func _texts(panel: DetailPanel) -> Array:
	return panel.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)


func _links(panel: DetailPanel) -> Array[Node]:
	return panel.find_children("*", "LinkButton", true, false)


func _passenger_with_relations(sim: Sim) -> Passenger:
	for passenger: Passenger in sim.passengers_by_id.values():
		if not passenger.relationships.is_empty() and sim.parties[passenger.party_id].size() > 1:
			return passenger
	return null


func test_panel_sections_present() -> void:
	var sim := SharedSim.get_sim()
	var passenger := _passenger_with_relations(sim)
	var panel := _panel(passenger)
	var texts := _texts(panel)
	for heading in ["JOURNEY", "TRAVELLING WITH", "HEALTH", "RELATIONSHIPS"]:
		assert_true(texts.has(heading), "%s heading shows" % heading)
	assert_true(texts.has(passenger.full_name.to_upper()) and texts.has(passenger.id), "name and id show")
	assert_true(texts.any(func(text: String) -> bool: return text.contains("born %s" % passenger.birthplace)), "age and birthplace show")
	assert_true(texts.any(func(text: String) -> bool: return text.contains("traveling for")), "the reason shows")
	assert_true(texts.any(func(text: String) -> bool: return text.begins_with("HISTORY")), "history heading shows")
	assert_true(panel.find_children("*", "RichTextLabel", true, false).size() == 1, "history scrolls in a rich text label")
	var name_label: Label = panel.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.text == passenger.full_name.to_upper())[0]
	assert_true(name_label.get_theme_font_size("font_size") == DetailPanel.NAME_SIZE, "the name is 26 px")
	assert_true(_texts(_panel(null)) == ["Select a passenger"], "nothing selected shows the prompt")


func test_history_newest_first() -> void:
	var sim := SharedSim.get_sim()
	var passenger := _passenger_with_relations(sim)
	passenger.add_history(1.0, "Older entry", "test")
	passenger.add_history(2.0, "Newer entry", "test")
	var panel := _panel(passenger)
	var text: String = panel.find_children("*", "RichTextLabel", true, false)[0].text
	assert_true(text.contains("Older entry") and text.find("Newer entry") < text.find("Older entry"), "newest entry comes first")


func test_relationship_click_selects() -> void:
	var sim := SharedSim.get_sim()
	var passenger := _passenger_with_relations(sim)
	var panel := _panel(passenger)
	var clicked: Array[Passenger] = []
	panel.passenger_clicked.connect(func(other: Passenger) -> void: clicked.append(other))
	var wanted: String = passenger.relationships[0].other
	var link: LinkButton = _links(panel).filter(func(l: LinkButton) -> bool: return l.get_meta("passenger").id == wanted)[0]
	link.pressed.emit()
	assert_true(clicked.size() == 1 and clicked[0].id == wanted, "the click names the relation")


func test_main_selects_and_scrolls_on_panel_click() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.sim = SharedSim.get_sim()
	own(main)
	main.set_process(false)
	var passenger := _passenger_with_relations(main.sim)
	main.table.passenger_selected.emit(passenger)
	assert_true(main.detail_panel.shown == passenger, "a table selection fills the panel")
	var other_id: String = passenger.relationships[0].other
	main.detail_panel.passenger_clicked.emit(main.sim.passengers_by_id[other_id])
	assert_true(main.detail_panel.shown.id == other_id, "the panel shows the clicked passenger")
	assert_true(main.table.get_selected().get_metadata(0).id == other_id, "the table selects them")


func test_arrived_relation_still_listed() -> void:
	var sim := SharedSim.get_sim()
	var passenger := _passenger_with_relations(sim)
	var other := sim.passengers_by_id[passenger.relationships[0].other]
	var party := sim.parties[other.party_id]
	var before := party.state
	party.state = Party.State.ARRIVED
	var panel := _panel(passenger)
	party.state = before
	assert_true(_links(panel).any(func(l: LinkButton) -> bool: return l.get_meta("passenger") == other), "the arrived relation is still a link")
	assert_true(_texts(panel).any(func(text: String) -> bool: return text.contains("(arrived)")), "it is marked arrived")


func test_parent_and_child_see_each_other_by_what_the_other_is() -> void:
	var sim := SharedSim.get_sim()
	var parent := sim.passengers_by_id["P-00001"]
	var child := sim.passengers_by_id["P-00002"]
	assert_true(_texts(_panel(parent)).any(func(text: String) -> bool: return text.contains("child")), "parent's panel lists the child as child")
	assert_true(_texts(_panel(child)).any(func(text: String) -> bool: return text.contains("parent")), "child's panel lists the parent as parent")
	assert_true(not _texts(_panel(child)).any(func(text: String) -> bool: return text.contains("child")), "child's panel never says child")
