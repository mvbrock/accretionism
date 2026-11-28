class_name ClockBar
extends HBoxContainer
## The bar across the top of the dashboard side: Pause/Play, Speed and the sim time, then the most
## serious alarm and a Disconnect button, which show only while connected.

signal pause_pressed
signal speed_pressed
signal disconnect_pressed

var pause_button: Button
var speed_button: Button
var disconnect_button: Button
var clock_label: Label
var alarm_label: Label


func _init(connected: bool) -> void:
	add_theme_constant_override("separation", 14)
	pause_button = _button(pause_pressed)
	speed_button = _button(speed_pressed)
	clock_label = Label.new()
	alarm_label = Label.new()
	alarm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alarm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disconnect_button = _button(disconnect_pressed)
	disconnect_button.text = "Disconnect"
	disconnect_button.visible = connected
	for node in [pause_button, speed_button, clock_label, alarm_label, disconnect_button]:
		add_child(node)


func show_clock(clock: SimClock) -> void:
	pause_button.text = "Play" if clock.paused else "Pause"
	speed_button.text = "Speed: %s" % clock.speed_label()


func show_time(time_s: float) -> void:
	clock_label.text = DashboardModel.clock_text(time_s)


## `alarm` is DashboardModel.top_alarm's: its text, empty when there is none, and its level.
func show_alarm(alarm: Dictionary) -> void:
	alarm_label.text = "⚠ " + alarm.text if alarm.text != "" else ""
	alarm_label.add_theme_color_override("font_color", DashboardView.status_color(alarm.level))


## No focus, so clicking it never takes the command line's focus away.
func _button(pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: pressed_signal.emit())
	return button
