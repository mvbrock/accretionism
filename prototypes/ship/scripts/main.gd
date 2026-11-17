extends Node3D
## Wires up the prototype. Esc quits.
## Screenshot mode: godot --path . -- --capture <dir>   (auto-walks and saves shots, then quits)

const CAPTURE_FRAMES := [90, 400, 900, 1500]

@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig

var _capture_dir := ""
var _frame := 0


func _ready() -> void:
	Player.ensure_input_actions()
	player.global_position = RingGeometry.section_down(0) * (RingGeometry.floor_apothem() - 0.05)
	player.reset_physics_interpolation()  # teleported: don't interpolate from the origin
	rig.snap()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1 and i + 1 < args.size():
		_capture_dir = args[i + 1]
		player.drive_by_code = true
		player.move_input = Vector2(0.35, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _process(_delta: float) -> void:
	if _capture_dir == "":
		return
	_frame += 1
	if _frame == 700:
		player.move_input = Vector2(-0.6, 1.0)
	if _frame in CAPTURE_FRAMES:
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/shot_%04d.png" % [_capture_dir, _frame])
	if _frame >= CAPTURE_FRAMES.back():
		get_tree().quit()
