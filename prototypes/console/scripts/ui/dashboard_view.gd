class_name DashboardView
extends VBoxContainer
## The ship at a glance: clock bar, room tiles, systems, breakers, tanks and the
## log. Built in code; show_ship() redraws it from a Ship.

signal pause_pressed
signal speed_pressed

const GREEN := Color("5fd068")
const AMBER := Color("f0b030")
const RED := Color("ee5050")
const BAR_CELLS := 8
const TILE_BORDER_PX := 3

var clock_bar: HBoxContainer
var pause_button: Button
var speed_button: Button
var _clock_label: Label
var _alarm_label: Label
## room id -> {panel: PanelContainer, style: StyleBoxFlat, labels: {key: Label}}
var _tiles := {}
var _opening_labels := {}
var _system_labels := {}
var _breaker_labels := {}
var _tank_labels := {}
var _breaker_grid: GridContainer
var _total_label: Label
var _log: RichTextLabel
var _log_text := ""


func _init() -> void:
	add_theme_constant_override("separation", 10)
	clock_bar = _build_clock_bar()
	add_child(clock_bar)
	add_child(_build_panels())
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_log)


func show_clock(clock: SimClock) -> void:
	pause_button.text = "Play" if clock.paused else "Pause"
	speed_button.text = "Speed: %d×" % int(SimClock.SPEEDS[clock.speed_index])


func show_ship(ship: Ship) -> void:
	if _tiles.is_empty():
		var schematic := _build_schematic(ship)
		add_child(schematic)
		move_child(schematic, 1)
		_build_breaker_labels(ship)
	_clock_label.text = DashboardModel.clock_text(ship.time_s)
	var alarm := DashboardModel.top_alarm(ship)
	_alarm_label.text = "⚠ " + alarm.text if alarm.text != "" else ""
	_alarm_label.add_theme_color_override("font_color", _color(alarm.level))
	for room in ship.rooms:
		_show_tile(room.id, DashboardModel.room_tile(ship, room.id))
	for id in _opening_labels:
		_opening_labels[id].text = "%s\n%s" % [id, DashboardModel.opening_text(ship, id)]
	for id in _system_labels:
		_show_status(_system_labels[id], "%s  %s" % [id, DashboardModel.system_text(ship, id)], DashboardModel.system_level(ship, id))
	for id in _breaker_labels:
		var text := DashboardModel.breaker_text(ship, id)
		_show_status(_breaker_labels[id], "%s  %s" % [id, text],
				DashboardModel.breaker_level(ship, id))
	for gas in Units.TANK_GASES:
		var percent := DashboardModel.tank_percent(ship, gas)
		var filled := clampi(percent * BAR_CELLS / 100, 0, BAR_CELLS)
		_show_status(_tank_labels[gas], "%s %s%s %d %%" % [DashboardModel.gas_name(gas), "█".repeat(filled),
				"░".repeat(BAR_CELLS - filled), percent], DashboardModel.tank_level(ship, gas))
	_total_label.text = DashboardModel.total_draw_text(ship)
	_show_log(ship)


## One line of a room tile; `key` is title, pressure, temperature, o2, n2, co2, passengers or light.
func tile_label(room_id: String, key: String) -> Label:
	return _tiles[room_id].labels[key]


func _build_clock_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	pause_button = _clock_button(pause_pressed)
	speed_button = _clock_button(speed_pressed)
	_clock_label = Label.new()
	_alarm_label = Label.new()
	_alarm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for node in [pause_button, speed_button, _clock_label, _alarm_label]:
		bar.add_child(node)
	return bar


## No focus, so clicking it never takes the command line's focus away.
func _clock_button(pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: pressed_signal.emit())
	return button


## Each opening follows whichever of its rooms comes first in the room order.
func _build_schematic(ship: Ship) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for room in ship.rooms:
		row.add_child(_build_tile(room.id))
		for opening in ship.openings:
			if _first_room_id(ship, opening) == room.id:
				row.add_child(_build_opening(opening.id))
	return row


## Whichever of the opening's rooms comes first in the ship's room order; the hatch's is its room.
func _first_room_id(ship: Ship, opening: Opening) -> String:
	var index_a := ship.rooms.find(ship.room(opening.room_a))
	var index_b := ship.rooms.find(ship.room(opening.room_b))
	if index_b == -1 or (index_a != -1 and index_a < index_b):
		return opening.room_a
	return opening.room_b


func _build_tile(room_id: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	panel.add_child(column)
	var labels := {}
	for key in ["title", "pressure", "temperature", "o2", "n2", "co2", "passengers", "light"]:
		var label := Label.new()
		column.add_child(label)
		labels[key] = label
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.25)
	style.set_border_width_all(TILE_BORDER_PX)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_tiles[room_id] = {"panel": panel, "labels": labels, "style": style}
	return panel


## The ship's own breakers; the panel is empty until a ship is shown.
func _build_breaker_labels(ship: Ship) -> void:
	for id in ship.power.breaker_ids:
		var label := Label.new()
		_breaker_grid.add_child(label)
		_breaker_labels[id] = label


func _build_opening(id: String) -> Control:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 0)
	_opening_labels[id] = label
	return label


func _build_panels() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.add_child(_column("SYSTEMS", Ship.SYSTEM_IDS, _system_labels))
	var breakers := _column("BREAKERS", [], _breaker_labels)
	_breaker_grid = GridContainer.new()
	_breaker_grid.columns = 2
	_breaker_grid.add_theme_constant_override("h_separation", 24)
	breakers.add_child(_breaker_grid)
	_total_label = Label.new()
	breakers.add_child(_total_label)
	row.add_child(breakers)
	row.add_child(_column("TANKS", Units.TANK_GASES, _tank_labels))
	return row


func _column(title: String, ids: Array[String], labels: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	var heading := Label.new()
	heading.text = title
	column.add_child(heading)
	for id in ids:
		var label := Label.new()
		column.add_child(label)
		labels[id] = label
	return column


func _show_tile(room_id: String, tile: Dictionary) -> void:
	var labels: Dictionary = _tiles[room_id].labels
	labels.title.text = tile.title
	labels.pressure.text = tile.pressure
	labels.temperature.text = tile.temperature
	labels.o2.text = DashboardModel.gas_name("O2") + " " + tile.o2
	labels.n2.text = DashboardModel.gas_name("N2") + " " + tile.n2
	labels.co2.text = DashboardModel.gas_name("CO2") + " " + tile.co2
	labels.passengers.text = tile.passengers
	labels.light.text = "light ●" if tile.lit else "light ○"
	_tiles[room_id].style.border_color = _color(tile.level)
	labels.title.add_theme_color_override("font_color", _color(tile.level))


func _show_status(label: Label, text: String, level: Status.Level) -> void:
	label.text = text
	label.add_theme_color_override("font_color", _color(level))


func _show_log(ship: Ship) -> void:
	var lines := PackedStringArray()
	for entry in ship.events.entries:
		var stamp := DashboardModel.clock_text(entry.time_s).trim_prefix("T+")
		var text: String = entry.text.replace("[", "[lb]")
		lines.append("%s  [color=#%s]%s[/color]" % [stamp, _log_color(entry.level).to_html(false), text])
	var joined := "\n".join(lines)
	if joined != _log_text:
		_log_text = joined
		_log.text = joined


func _log_color(level: EventLog.Level) -> Color:
	match level:
		EventLog.Level.WARNING:
			return AMBER
		EventLog.Level.DANGER:
			return RED
	return Color.WHITE


func _color(level: Status.Level) -> Color:
	match level:
		Status.Level.WARNING:
			return AMBER
		Status.Level.DANGER:
			return RED
	return GREEN
