class_name Main
extends Control

var sim: Sim
var clock := SimClock.new()

@onready var play_pause_button: Button = %PlayPause
@onready var speed_button: Button = %Speed
@onready var clock_label: Label = %ClockLabel
@onready var filter: LineEdit = %Filter
@onready var table: PassengerTable = %Table
@onready var detail_panel: DetailPanel = %DetailPanel


func _ready() -> void:
	_match_display_scale()
	if sim == null:
		sim = Sim.new()
	clock.day = sim.day
	table.show_passengers(sim.passengers_by_id.values())
	table.refresh(sim)
	table.passenger_selected.connect(func(passenger: Passenger) -> void: detail_panel.show_passenger(sim, passenger))
	detail_panel.passenger_clicked.connect(_select_from_panel)
	detail_panel.show_passenger(sim, null)
	play_pause_button.pressed.connect(_toggle_pause)
	speed_button.pressed.connect(_next_speed)
	filter.text_changed.connect(table.set_filter)
	filter.text_submitted.connect(func(_text: String) -> void: filter.release_focus())
	_show_clock()


## Without this, a HiDPI display (such as Retina, scale 2) sizes the window in physical
## pixels and the UI renders at 1/scale of its intended size.
func _match_display_scale() -> void:
	var scale := DisplayServer.screen_get_scale()
	if scale <= 1.0:
		return
	var window := get_window()
	window.content_scale_factor = scale
	window.size = scaled_window_size(window.size, scale, DisplayServer.screen_get_usable_rect().size)
	window.move_to_center()


static func scaled_window_size(base: Vector2i, scale: float, usable: Vector2i) -> Vector2i:
	var wanted := Vector2(base) * scale
	var fit := minf(1.0, minf(usable.x / wanted.x, usable.y / wanted.y))
	return Vector2i(wanted * fit)


func _process(delta: float) -> void:
	sim.advance_to(clock.tick(delta))
	table.refresh(sim)
	detail_panel.refresh(sim)
	_show_clock()


func _input(event: InputEvent) -> void:
	# Ahead of the GUI, so Space never presses whichever button has focus.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and not filter.has_focus():
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _select_from_panel(passenger: Passenger) -> void:
	table.show_selected(passenger)
	detail_panel.show_passenger(sim, passenger)


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
