class_name Main
extends Control
## Wires the fleet, the clock, the dashboard and the console. The console starts
## disconnected; the dashboard shows the ship it connects to. Every ship runs on
## the one clock. Space pauses unless the command line has focus; Esc quits.
## Screenshot mode: godot --path . -- --capture <dir>   (runs at 1 min/s, connects to
## the skiff, opens the hatch and selects the hold, saves venting.png at 20 s, closes it, saves refilled.png at 120 s, then quits)

const GREETING := "Not connected. Type 'ships list' to see the ships, 'ships connect <ship name>' to connect."
const OVERLAY_TEXT := "COMPUTER REBOOTING"
const STALE_TEXT := "STALE"
const WINDOW_MARGIN_PX := 12
## The console column and the dashboard split the width in this ratio.
const CONSOLE_SHARE := 40.0
const DASHBOARD_SHARE := 60.0
const CONSOLE_PANEL_COLOR := Color("26282c")
const CONSOLE_PADDING_PX := 8

## The standard fleet unless a test gives it another before it enters the tree.
var fleet: Fleet
var link: ShipLink
## The connected ship, or null.
var ship: Ship:
	get:
		return link.ship() if link != null else null
var clock := SimClock.new()
var dashboard: DashboardView
var console: Console
var console_panel: PanelContainer
var stage: Control
var ship_table: ShipTable
var overlay: Label
var stale_label: Label

var _capture: CaptureScript


func _ready() -> void:
	_match_display_scale()
	if fleet == null:
		fleet = Fleet.standard()
	link = ShipLink.new(fleet)
	_build_ui()
	console.line_submitted.connect(run_line)
	console.print_line(GREETING)
	console.input.grab_focus()
	refresh()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		if i + 1 < args.size():
			_capture = CaptureScript.new(self, args[i + 1])
		else:
			push_error("--capture needs a directory: godot --path . -- --capture <dir>")


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
## Disconnected: no dashboard, only the ship table.
func refresh() -> void:
	console.link_status.show_link(link)
	ship_table.visible = ship == null
	if ship == null:
		ship_table.clock_bar.show_clock(clock)
		ship_table.show_fleet(fleet)
		overlay.visible = false
		stale_label.visible = false
		return
	dashboard.clock_bar.show_clock(clock)
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
	for reply in link.advance(sim_seconds, clock.step_s()):
		console.print_line(reply)
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
	elif event.keycode == KEY_SPACE and not console.input.has_focus():
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", WINDOW_MARGIN_PX)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, WINDOW_MARGIN_PX)
	add_child(split)
	console_panel = PanelContainer.new()
	console_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	console_panel.size_flags_stretch_ratio = CONSOLE_SHARE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = CONSOLE_PANEL_COLOR
	panel_style.set_content_margin_all(CONSOLE_PADDING_PX)
	console_panel.add_theme_stylebox_override("panel", panel_style)
	split.add_child(console_panel)
	console = Console.new()
	console_panel.add_child(console)
	stage = Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = DASHBOARD_SHARE
	split.add_child(stage)
	ship_table = ShipTable.new(fleet)
	ship_table.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ship_table.connect_pressed.connect(func(ship_name: String) -> void: run_line("ships connect " + ship_name))
	ship_table.clock_bar.pause_pressed.connect(_toggle_pause)
	ship_table.clock_bar.speed_pressed.connect(_next_speed)
	stage.add_child(ship_table)
	overlay = _make_banner(OVERLAY_TEXT, Control.PRESET_FULL_RECT, 48)
	overlay.add_theme_stylebox_override("normal", _scrim())
	stage.add_child(overlay)
	stale_label = _make_banner(STALE_TEXT, Control.PRESET_CENTER_TOP, 19)
	stale_label.add_theme_color_override("font_color", DashboardView.YELLOW)
	stage.add_child(stale_label)


## A dashboard is built for one ship's rooms and doors, so each connection gets a
## fresh one, below the banners. It draws the ship once on connect, so a computer
## that is already down leaves a snapshot under the banner rather than an empty dashboard.
func _show_dashboard() -> void:
	if dashboard != null:
		stage.remove_child(dashboard)
		dashboard.queue_free()
		dashboard = null
	if ship == null:
		return
	dashboard = DashboardView.new()
	dashboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(dashboard)
	stage.move_child(dashboard, 0)
	dashboard.clock_bar.pause_pressed.connect(_toggle_pause)
	dashboard.clock_bar.speed_pressed.connect(_next_speed)
	dashboard.clock_bar.disconnect_pressed.connect(run_line.bind("disconnect"))
	dashboard.room_clicked.connect(_on_room_clicked)
	dashboard.room_selected.connect(refresh)
	dashboard.clock_bar.resized.connect(_leave_clock_bar_uncovered)
	dashboard.clock_bar.show_clock(clock)
	dashboard.show_ship(ship)


## The reboot overlay starts where the clock bar ends, wherever the layout puts it.
func _leave_clock_bar_uncovered() -> void:
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


## Echoes the line, runs it through the link and prints the response.
func run_line(line: String) -> void:
	console.print_line("> " + line)
	var connected_before := link.ship_name
	var response := link.run(line)
	if response != "":
		console.print_line(response)
	if link.ship_name != connected_before:
		_show_dashboard()
	refresh()


## A frozen dashboard (computer booting or in FAULT) takes no clicks.
func _on_room_clicked(room_id: String) -> void:
	if not _dashboard_frozen():
		dashboard.select_room(room_id)


func _dashboard_frozen() -> bool:
	var state := (ship.systems[Ship.COMPUTER_ID] as SystemUnit).state
	return state == SystemUnit.State.BOOTING or state == SystemUnit.State.FAULT


func _toggle_pause() -> void:
	clock.paused = not clock.paused
	refresh()


func _next_speed() -> void:
	clock.speed_index = (clock.speed_index + 1) % SimClock.speed_count()
	refresh()


## Drives the `--capture` run by sim time, so the shots don't depend on frame
## rate: the clock is cut short at each stop, paused a few frames for the shot,
## then resumed.
class CaptureScript:
	const SPEED_INDEX := 1
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
		main.run_line("ships connect skiff")
		CommandInterpreter.run(main.ship, "door open hatch")
		main.dashboard.select_room("hold")

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
