class_name Main
extends Control
## Wires the clock, the tabs, the selection and dispatch. Space pauses, Esc quits.
## Screenshot mode: godot --path . -- --capture <dir>   (dispatches a few
## transports, runs at 10 d/s, saves table.png and diagram.png, then quits)

signal selection_changed(ship: Variant)

const FLEET_PATH := "res://data/fleet.json"
const TABLE_TAB := 0
const DIAGRAM_TAB := 1

var fleet: Fleet
var clock := SimClock.new()
## The selected Cycler or Transport, or null.
var selected: Variant = null

@onready var play_pause_button: Button = %PlayPause
@onready var speed_button: Button = %Speed
@onready var clock_label: Label = %ClockLabel
@onready var tabs: TabContainer = %Tabs
@onready var table: FleetTable = %Table
@onready var dispatch: DispatchPanel = %DispatchPanel
@onready var diagram: DiagramView = %Diagram

var _capture: CaptureScript


func _ready() -> void:
	fleet = FleetLoader.load_file(FLEET_PATH)
	assert(fleet != null, "could not load %s" % FLEET_PATH)
	clock.day = fleet.day
	table.show_fleet(_ships(), TableModel.rows(fleet))
	table.ship_selected.connect(select)
	diagram.attach(self)
	dispatch.depart_requested.connect(_on_depart_requested)
	play_pause_button.pressed.connect(_toggle_pause)
	speed_button.pressed.connect(_next_speed)
	_show_clock()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1 and i + 1 < args.size():
		_capture = CaptureScript.new(self, args[i + 1])


## `ship` is a Cycler, a Transport, or null.
func select(ship: Variant) -> void:
	if ship == selected:
		return
	selected = ship
	table.show_selected(ship)
	dispatch.show_ship(fleet, ship)
	selection_changed.emit(ship)


func _process(delta: float) -> void:
	fleet.advance_to(clock.tick(delta))
	table.refresh(TableModel.rows(fleet))
	dispatch.refresh()
	_show_clock()
	if _capture != null:
		_capture.step()


func _input(event: InputEvent) -> void:
	# Ahead of the GUI, so Space never presses whichever button has focus.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _ships() -> Array:
	return fleet.cyclers + fleet.transports


func _toggle_pause() -> void:
	clock.paused = not clock.paused
	_show_clock()


func _next_speed() -> void:
	clock.speed_index = (clock.speed_index + 1) % SimClock.SPEEDS_DAYS_PER_SEC.size()
	_show_clock()


func _show_clock() -> void:
	play_pause_button.text = "Play" if clock.paused else "Pause"
	speed_button.text = "Speed: %s" % clock.speed_label()
	clock_label.text = clock.label()


func _on_depart_requested(transport: Transport, target: Variant) -> void:
	fleet.depart(transport, target)
	table.refresh(TableModel.rows(fleet))
	dispatch.refresh()


## Drives the `--capture` run: scripted departures, then the two screenshots.
class CaptureScript:
	const RUN_FRAMES := 60
	## [frame, ship, target]: a few of each kind of trip, so lines show.
	const DEPARTURES := [
		[1, "Heron", "Mars"], [1, "Petrel", "Earth"], [1, "Robin", "Aldrin IV"],
		[1, "Kestrel", "Earth"], [1, "Falcon", "Mars"], [1, "Plover", "Aldrin II"],
		[15, "Swift", "Mars"], [20, "Avocet", "Earth"], [30, "Lark", "Mars"],
	]
	## Earth-Moon trips take about 2.7 h, under one frame at 10 d/s, so they
	## leave once the clock is paused and the capture steps one sim hour.
	const MOON_DEPARTURES := [["Finch", "Moon"], ["Merlin", "Earth"]]
	const MOON_STEP_DAYS := 1.0 / 24.0
	const SELECTED_SHIP := "Heron"

	var _main: Main
	var _dir: String
	var _frame := 0

	func _init(main: Main, dir: String) -> void:
		_main = main
		_dir = dir
		DirAccess.make_dir_recursive_absolute(dir)
		main.clock.speed_index = SimClock.SPEEDS_DAYS_PER_SEC.size() - 1
		main.clock.paused = false

	func step() -> void:
		_frame += 1
		for departure in DEPARTURES:
			if departure[0] == _frame:
				_depart(departure[1], departure[2])
		if _frame == 2:
			_main.select(_ship(SELECTED_SHIP))
		if _frame == RUN_FRAMES:
			_main.clock.paused = true
			for departure in MOON_DEPARTURES:
				_depart(departure[0], departure[1])
			_main.clock.day += MOON_STEP_DAYS
		# Each screenshot is taken a couple of frames after the view it shows is up to date.
		if _frame == RUN_FRAMES + 3:
			_save("table.png")
			_main.tabs.current_tab = DIAGRAM_TAB
		if _frame == RUN_FRAMES + 6:
			_save("diagram.png")
			_main.get_tree().quit()

	func _depart(ship_name: String, target_name: String) -> void:
		var target: Variant = null
		for body in Orbits.Body.values():
			if Orbits.body_name(body) == target_name:
				target = body
		for cycler in _main.fleet.cyclers:
			if cycler.name == target_name:
				target = cycler
		if not _main.fleet.depart(_ship(ship_name), target):
			push_warning("capture: %s could not depart for %s" % [ship_name, target_name])

	func _ship(ship_name: String) -> Variant:
		for ship in _main._ships():
			if ship.name == ship_name:
				return ship
		return null

	func _save(file_name: String) -> void:
		_main.get_viewport().get_texture().get_image().save_png(_dir.path_join(file_name))
