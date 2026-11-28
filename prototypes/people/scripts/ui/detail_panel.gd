class_name DetailPanel
extends VBoxContainer
## The selected passenger's header, journey, party, health, relationships and
## history. Rebuilt when its content changes; the progress figure updates in place.

signal passenger_clicked(passenger: Passenger)

const NAME_SIZE := 26
const EMPTY_TEXT := "Select a passenger"
const REASON_WORDS := {
	Passenger.Reason.WORK: "work",
	Passenger.Reason.EMIGRATION: "emigration",
	Passenger.Reason.VISIT: "a visit",
	Passenger.Reason.MEDICAL: "medical care",
	Passenger.Reason.RETURNING: "returning home",
}
const LEG_MARKS := {"done": "✓", "current": "▸", "next": "·"}
const HEADING_COLOR := Color(0.55, 0.65, 0.8)

var shown: Passenger = null
var _shown_content := ""
var _progress_label: Label


func show_passenger(sim: Sim, passenger: Passenger) -> void:
	shown = passenger
	_rebuild(sim)


## Follows the clock: rebuilds if anything but the progress figure changed.
func refresh(sim: Sim) -> void:
	if shown == null:
		return
	if _content(sim, shown) != _shown_content:
		_rebuild(sim)
	else:
		_progress_label.text = _progress_text(sim, shown)


func _rebuild(sim: Sim) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_progress_label = null
	if shown == null:
		_shown_content = ""
		add_child(_label(EMPTY_TEXT))
		return
	_shown_content = _content(sim, shown)
	var party := sim.parties[shown.party_id]
	_add_header(shown)
	_add_journey(sim, party)
	_add_party(party)
	_add_health(shown)
	_add_relationships(sim, shown)
	_add_history(shown)


## Everything the panel shows except the progress figure.
func _content(sim: Sim, passenger: Passenger) -> String:
	var party := sim.parties[passenger.party_id]
	var arrived := passenger.relationships.map(func(relation: Dictionary) -> bool: return _has_arrived(sim, relation.other))
	return var_to_str([passenger.history.size(), Planner.legs(party), party.size(), arrived,
		Fleet.target_name(party.origin), Fleet.target_name(party.destination)])


func _add_header(passenger: Passenger) -> void:
	var title := HBoxContainer.new()
	var name_label := _label(passenger.full_name.to_upper())
	name_label.add_theme_font_size_override("font_size", NAME_SIZE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	title.add_child(_label(passenger.id))
	add_child(title)
	add_child(_label("%d · born %s" % [passenger.age, passenger.birthplace]))
	add_child(_label("%s · traveling for %s" % [passenger.occupation, REASON_WORDS[passenger.reason]]))
	add_child(_label("\"%s\"" % passenger.note))


func _add_journey(sim: Sim, party: Party) -> void:
	var title := HBoxContainer.new()
	title.add_child(_heading("JOURNEY"))
	title.add_child(_label("  %s → %s  " % [Fleet.target_name(party.origin), Fleet.target_name(party.destination)]))
	_progress_label = _label(_progress_text(sim, shown))
	title.add_child(_progress_label)
	add_child(title)
	for leg in Planner.legs(party):
		add_child(_label("  %s %s  %s → %s  d%d–d%d" % [LEG_MARKS[leg.status], leg.ship_name, leg.from_name, leg.to_name, int(leg.start), int(leg.end)]))


func _add_party(party: Party) -> void:
	add_child(_heading("TRAVELLING WITH"))
	var companions := party.members.filter(func(member: Passenger) -> bool: return member != shown)
	if companions.is_empty():
		add_child(_label("  alone"))
	for companion: Passenger in companions:
		add_child(_link_row(companion, ""))


func _add_health(passenger: Passenger) -> void:
	add_child(_heading("HEALTH"))
	if passenger.conditions.is_empty():
		add_child(_label("  None"))
	for condition in passenger.conditions:
		add_child(_label("  %s" % condition.name))


func _add_relationships(sim: Sim, passenger: Passenger) -> void:
	add_child(_heading("RELATIONSHIPS"))
	if passenger.relationships.is_empty():
		add_child(_label("  None"))
	for relation in passenger.relationships:
		var note: String = Passenger.Kind.find_key(relation.kind).to_lower()
		if _has_arrived(sim, relation.other):
			note += " (arrived)"
		add_child(_link_row(sim.passengers_by_id[relation.other], note))


func _add_history(passenger: Passenger) -> void:
	add_child(_heading("HISTORY  (newest first)"))
	var history := RichTextLabel.new()
	history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history.custom_minimum_size = Vector2(0, 120)
	var lines: Array[String] = []
	for i in range(passenger.history.size() - 1, -1, -1):
		var entry := passenger.history[i]
		lines.append("d%d  %s" % [int(entry.day), entry.text])
	history.text = "\n".join(lines)
	add_child(history)


func _link_row(other: Passenger, note: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_label("  "))
	var link := LinkButton.new()
	link.text = other.full_name
	link.set_meta("passenger", other)
	link.pressed.connect(func() -> void: passenger_clicked.emit(other))
	row.add_child(link)
	if not note.is_empty():
		row.add_child(_label("  " + note))
	return row


func _has_arrived(sim: Sim, passenger_id: String) -> bool:
	return sim.parties[sim.passengers_by_id[passenger_id].party_id].state == Party.State.ARRIVED


func _progress_text(sim: Sim, passenger: Passenger) -> String:
	var fraction := sim.progress(sim.parties[passenger.party_id])
	return TableModel.NOT_APPLICABLE if fraction < 0.0 else TableModel.percent(fraction)


func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", HEADING_COLOR)
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
