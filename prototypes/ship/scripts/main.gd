extends Node3D
## Wires up the prototype. Esc quits.
## Screenshot mode: godot --path . -- --capture <dir>   (auto-walks, turns gravity off, saves shots, then quits)

const CAPTURE_FRAMES := [90, 400, 900, 1500, 1800, 2100]

@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig
@onready var fleet: Fleet = $Fleet
@onready var ship_label: Label = $HUD/ShipLabel
@onready var hint_label: Label = $HUD/HintLabel

var _capture_dir := ""
var _frame := 0


func _ready() -> void:
	_match_display_scale()
	Player.ensure_input_actions()
	player.aim_camera = rig.camera
	fleet.ship_changed.connect(_show_ship_name)
	_show_ship_name(fleet.active)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1 and i + 1 < args.size():
		_capture_dir = args[i + 1]
		player.drive_by_code = true
		player.move_input = Vector2(0.35, 1.0)


func _show_ship_name(ship: Ship) -> void:
	ship_label.text = "%s   ·   Tab: next ship" % ship.name


## On a HiDPI display (such as Retina, scale 2) the window is sized in physical
## pixels, so without this the view would render at 1/scale of its intended size.
func _match_display_scale() -> void:
	var scale := DisplayServer.screen_get_scale()
	if scale <= 1.0:
		return
	var window := get_window()
	window.content_scale_factor = scale
	window.size = scaled_window_size(window.size, scale, DisplayServer.screen_get_usable_rect().size)
	window.move_to_center()


## The window size that shows `base` logical pixels at `scale`, shrunk
## proportionally to fit within `usable`.
static func scaled_window_size(base: Vector2i, scale: float, usable: Vector2i) -> Vector2i:
	var wanted := Vector2(base) * scale
	var fit := minf(1.0, minf(usable.x / wanted.x, usable.y / wanted.y))
	return Vector2i(wanted * fit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _process(_delta: float) -> void:
	hint_label.text = player.interact_hint()
	if _capture_dir == "":
		return
	_frame += 1
	if _frame == 700:
		player.move_input = Vector2(-0.6, 1.0)
	if _frame == 1100:
		player.set_gravity_enabled(false)
	if _frame == 1550:
		fleet.next_ship()
	if _frame == 1850:
		fleet.next_ship()
	if _frame in CAPTURE_FRAMES:
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/shot_%04d.png" % [_capture_dir, _frame])
	if _frame >= CAPTURE_FRAMES.back():
		get_tree().quit()
