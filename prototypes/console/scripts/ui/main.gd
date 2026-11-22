class_name Main
extends Control
## Wires the ship, the clock, the dashboard and the console. Space pauses unless
## the command line has focus; Esc quits.
## Screenshot mode: godot --path . -- --capture <dir>   (runs at 100x, opens the
## hatch, saves venting.png at 20 s, closes it, saves refilled.png at 120 s, then quits)

const SHIP_PATH := "res://data/ship.json"
const OVERLAY_TEXT := "COMPUTER REBOOTING"
const STALE_TEXT := "STALE"
const ERROR_MARGIN_PX := 24
const WINDOW_MARGIN_PX := 12
const CONSOLE_WIDTH_PX := 460

## Overridable so a test can load a different file.
var data_path := SHIP_PATH
var ship: Ship
var clock := SimClock.new()
var dashboard: DashboardView
var console: Console
var overlay: Label
var stale_label: Label
var error_label: Label

var _capture: CaptureScript


func _ready() -> void:
	_match_display_scale()
	ship = ShipLoader.load_file(data_path)
	if ship == null:
		_show_load_error()
		return
	_build_ui()
	dashboard.pause_pressed.connect(_toggle_pause)
	dashboard.speed_pressed.connect(_next_speed)
	console.line_submitted.connect(_on_line_submitted)
	console.input.grab_focus()
	refresh()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		if i + 1 < args.size():
			_capture = CaptureScript.new(self, args[i + 1])
		else:
			push_error("--capture needs a directory: godot --path . -- --capture <dir>")


## No sim runs without a ship; Esc still quits.
func _show_load_error() -> void:
	set_process(false)
	error_label = _make_banner("Could not load %s: %s" % [data_path.trim_prefix("res://"), ShipLoader.last_problem],
			Control.PRESET_FULL_RECT, 24)
	error_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, ERROR_MARGIN_PX)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = true
	add_child(error_label)
	if OS.get_cmdline_user_args().has("--capture"):
		get_tree().quit(1)


## On a HiDPI display (such as Retina, scale 2) the window is sized in physical
## pixels, so without this the UI would render at 1/scale of its intended size.
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


## The one place that reads the computer's state. Running: redraw. Booting: the
## overlay covers the panels. Fault: the panels stay as they were, marked stale.
func refresh() -> void:
	dashboard.show_clock(clock)
	match (ship.systems[Ship.COMPUTER_ID] as SystemUnit).state:
		SystemUnit.State.BOOTING:
			overlay.visible = true
			stale_label.visible = false
		SystemUnit.State.FAULT:
			overlay.visible = false
			stale_label.visible = true
		_:
			overlay.visible = false
			stale_label.visible = false
			dashboard.show_ship(ship)


func _process(delta: float) -> void:
	var sim_seconds := clock.tick(delta)
	if _capture != null:
		sim_seconds = _capture.limit(sim_seconds)
	ship.advance(sim_seconds)
	refresh()
	if _capture != null:
		_capture.step()


func _input(event: InputEvent) -> void:
	# Ahead of the GUI, so Space never presses a focused button and the command line can't eat Esc.
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().quit()
	elif event.keycode == KEY_SPACE and ship != null and not console.input.has_focus():
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", WINDOW_MARGIN_PX)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, WINDOW_MARGIN_PX)
	add_child(split)
	console = Console.new()
	console.custom_minimum_size = Vector2(CONSOLE_WIDTH_PX, 0)
	split.add_child(console)
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(stage)
	dashboard = DashboardView.new()
	dashboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(dashboard)
	overlay = _make_banner(OVERLAY_TEXT, Control.PRESET_FULL_RECT, 48)
	overlay.add_theme_stylebox_override("normal", _scrim())
	stage.add_child(overlay)
	dashboard.clock_bar.resized.connect(_leave_clock_bar_uncovered)
	stale_label = _make_banner(STALE_TEXT, Control.PRESET_CENTER_TOP, 19)
	stale_label.add_theme_color_override("font_color", DashboardView.AMBER)
	stage.add_child(stale_label)


## The reboot overlay starts where the clock bar ends, wherever the layout puts it.
func _leave_clock_bar_uncovered() -> void:
	var stage := overlay.get_parent() as Control
	overlay.offset_top = dashboard.clock_bar.get_global_rect().end.y - stage.get_global_rect().position.y


func _make_banner(text: String, preset: Control.LayoutPreset, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.visible = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	return label


func _scrim() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	return style


func _on_line_submitted(line: String) -> void:
	console.print_line("> " + line)
	var response := CommandInterpreter.run(ship, line)
	if response != "":
		console.print_line(response)
	refresh()


func _toggle_pause() -> void:
	clock.paused = not clock.paused
	refresh()


func _next_speed() -> void:
	clock.speed_index = (clock.speed_index + 1) % SimClock.SPEEDS.size()
	refresh()


## Drives the `--capture` run by sim time, so the shots don't depend on frame
## rate: the clock is cut short at each stop, paused a few frames for the shot,
## then resumed.
class CaptureScript:
	const SPEED_INDEX := 2
	const VENT_STOP_S := 20.0
	const REFILL_STOP_S := 120.0
	## Frames to let the redraw reach the screen before saving.
	const SETTLE_FRAMES := 3
	const _STOP_EPSILON_S := 1e-6

	var _main: Main
	var _dir: String
	var _stop_s := VENT_STOP_S
	var _file_name := "venting.png"
	var _settle_left := 0

	func _init(main: Main, dir: String) -> void:
		_main = main
		_dir = dir
		DirAccess.make_dir_recursive_absolute(dir)
		main.clock.speed_index = SPEED_INDEX
		main.clock.paused = false
		CommandInterpreter.run(main.ship, "door open hatch")

	## Sim seconds to run this frame, never past the current stop.
	func limit(sim_seconds: float) -> float:
		return clampf(_stop_s - _main.ship.time_s, 0.0, sim_seconds)

	func step() -> void:
		if _settle_left == 0:
			if _main.ship.time_s < _stop_s - _STOP_EPSILON_S:
				return
			_main.clock.paused = true
			_settle_left = SETTLE_FRAMES
			return
		_settle_left -= 1
		if _settle_left > 0:
			return
		_main.get_viewport().get_texture().get_image().save_png(_dir.path_join(_file_name))
		if _stop_s == REFILL_STOP_S:
			_main.get_tree().quit()
			return
		CommandInterpreter.run(_main.ship, "door close hatch")
		_stop_s = REFILL_STOP_S
		_file_name = "refilled.png"
		_main.clock.paused = false
