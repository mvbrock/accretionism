class_name ShipTable
extends VBoxContainer
## What the dashboard side shows while the console is disconnected: one row per ship with its
## name, class, status and a Connect button. The status is the worst level anywhere on the ship,
## NORMAL, WARNING, DANGER or CRITICAL, and show_fleet() refreshes it.

signal connect_pressed(ship_name: String)

const TITLE := "NO SHIP CONNECTED"
const HEADINGS := ["SHIP", "CLASS", "STATUS", ""]
const HEADING_COLOR := Color(1, 1, 1, 0.5)

var grid: GridContainer
var _status_labels := {}
var _connect_buttons := {}


func _init(fleet: Fleet) -> void:
	add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	add_child(title)
	grid = GridContainer.new()
	grid.columns = HEADINGS.size()
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for heading in HEADINGS:
		var label := _cell(heading)
		label.add_theme_color_override("font_color", HEADING_COLOR)
	for ship_name in fleet.ships:
		_cell(ship_name)
		_cell(DashboardModel.ship_class(fleet.ships[ship_name]))
		var status := _cell("")
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status_labels[ship_name] = status
		var button := Button.new()
		button.text = "Connect"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: connect_pressed.emit(ship_name))
		grid.add_child(button)
		_connect_buttons[ship_name] = button
	show_fleet(fleet)


func show_fleet(fleet: Fleet) -> void:
	for ship_name in _status_labels:
		var level := DashboardModel.ship_level(fleet.ships[ship_name])
		var label: Label = _status_labels[ship_name]
		label.text = Status.level_name(level)
		label.add_theme_color_override("font_color", DashboardView.status_color(level))


func status_label(ship_name: String) -> Label:
	return _status_labels[ship_name]


func connect_button(ship_name: String) -> Button:
	return _connect_buttons[ship_name]


func _cell(text: String) -> Label:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	return label
