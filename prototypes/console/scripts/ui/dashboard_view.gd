class_name DashboardView
extends VBoxContainer
## The ship at a glance: clock bar, the ship in 3D, the selected room's readings,
## systems, breakers, tanks and the log. Built in code; show_ship() redraws it
## from a Ship.

signal pause_pressed
signal speed_pressed
signal room_clicked(room_id: String)
signal room_selected

const GREEN := Color("5fd068")
const AMBER := Color("f0b030")
const RED := Color("ee5050")
const BAR_CELLS := 8
## The height left after the clock bar is split in these shares between the 3D view, the panels
## (which scroll when long) and the log, so the view keeps about half however long the panels are.
const SHIP_VIEW_SHARE := 1.2
const PANELS_SHARE := 0.8
const LOG_SHARE := 0.5
const ROOM_READING_KEYS := ["pressure", "temperature", "o2", "n2", "co2", "passengers", "light"]

var clock_bar: HBoxContainer
var pause_button: Button
var speed_button: Button
var ship_view: ShipView3D
var panels: Control
## The id of the room the ROOM panel shows; "" until a ship is shown.
var selected_room := ""
var room_heading: Label
var _clock_label: Label
var _alarm_label: Label
var _room_labels := {}
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
	panels = _build_panels()
	var panels_scroll := ScrollContainer.new()
	panels_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panels_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panels_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels_scroll.size_flags_stretch_ratio = PANELS_SHARE
	panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panels_scroll.add_child(panels)
	add_child(panels_scroll)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.size_flags_stretch_ratio = LOG_SHARE
	add_child(_log)


func show_clock(clock: SimClock) -> void:
	pause_button.text = "Play" if clock.paused else "Pause"
	speed_button.text = "Speed: %s" % clock.speed_label()


func show_ship(ship: Ship) -> void:
	if ship_view == null:
		ship_view = ShipView3D.new(ship)
		ship_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ship_view.size_flags_stretch_ratio = SHIP_VIEW_SHARE
		ship_view.room_clicked.connect(func(room_id: String) -> void: room_clicked.emit(room_id))
		add_child(ship_view)
		move_child(ship_view, 1)
		_build_breaker_labels(ship)
		selected_room = ship.rooms[0].id
	_clock_label.text = DashboardModel.clock_text(ship.time_s)
	var alarm := DashboardModel.top_alarm(ship)
	_alarm_label.text = "⚠ " + alarm.text if alarm.text != "" else ""
	_alarm_label.add_theme_color_override("font_color", status_color(alarm.level))
	ship_view.show_ship(ship, selected_room)
	_show_room_panel(DashboardModel.room_tile(ship, selected_room))
	for id in _system_labels:
		_show_status(_system_labels[id], "%s  %s" % [id, DashboardModel.system_text(ship, id)], DashboardModel.system_level(ship, id))
	_show_breakers(ship)
	for gas in Units.TANK_GASES:
		var percent := DashboardModel.tank_percent(ship, gas)
		var filled := clampi(percent * BAR_CELLS / 100, 0, BAR_CELLS)
		_show_status(_tank_labels[gas], "%s %s%s %d %%" % [DashboardModel.gas_name(gas), "█".repeat(filled),
				"░".repeat(BAR_CELLS - filled), percent], DashboardModel.tank_level(ship, gas))
	_total_label.text = DashboardModel.total_draw_text(ship)
	_show_log(ship)


## One reading of the ROOM panel; `key` is pressure, temperature, o2, n2, co2, passengers or light.
func room_label(key: String) -> Label:
	return _room_labels[key]


func select_room(room_id: String) -> void:
	selected_room = room_id
	room_selected.emit()


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


## One label per breaker of the ship; _show_breakers lists some of them.
func _build_breaker_labels(ship: Ship) -> void:
	for id in ship.power.breaker_ids:
		var label := Label.new()
		_breaker_grid.add_child(label)
		_breaker_labels[id] = label


func _build_panels() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var room := _column("ROOM", [], {})
	room_heading = room.get_child(0)
	for key in ROOM_READING_KEYS:
		var label := Label.new()
		room.add_child(label)
		_room_labels[key] = label
	row.add_child(room)
	row.add_child(_column("SYSTEMS", Ship.SYSTEM_IDS, _system_labels))
	var breakers := _column("BREAKERS", [], _breaker_labels)
	_breaker_grid = GridContainer.new()
	_breaker_grid.columns = 1
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


## Lists the selected room's breakers, the system breakers and every other tripped breaker, in that order.
func _show_breakers(ship: Ship) -> void:
	var listed := DashboardModel.listed_breakers(ship, selected_room)
	for id in _breaker_labels:
		_breaker_labels[id].visible = listed.has(id)
	for i in listed.size():
		var label: Label = _breaker_labels[listed[i]]
		_breaker_grid.move_child(label, i)
		_show_status(label, "%s  %s" % [listed[i], DashboardModel.breaker_text(ship, listed[i])],
				DashboardModel.breaker_level(ship, listed[i]))


func _show_room_panel(tile: Dictionary) -> void:
	room_heading.text = tile.title
	room_heading.add_theme_color_override("font_color", status_color(tile.level))
	_room_labels.pressure.text = tile.pressure
	_room_labels.temperature.text = tile.temperature
	_room_labels.o2.text = DashboardModel.gas_name("O2") + " " + tile.o2
	_room_labels.n2.text = DashboardModel.gas_name("N2") + " " + tile.n2
	_room_labels.co2.text = DashboardModel.gas_name("CO2") + " " + tile.co2
	_room_labels.passengers.text = tile.passengers
	_room_labels.light.text = "light ●" if tile.lit else "light ○"


func _show_status(label: Label, text: String, level: Status.Level) -> void:
	label.text = text
	label.add_theme_color_override("font_color", status_color(level))


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


static func status_color(level: Status.Level) -> Color:
	match level:
		Status.Level.WARNING:
			return AMBER
		Status.Level.DANGER:
			return RED
	return GREEN
