class_name CameraRig
extends Node3D
## Sits on the spin axis and rolls by the ship's camera roll at the player (for the ring, the
## player's angle around it), so the player always appears at the bottom of the ring. Its child
## camera keeps a fixed isometric angle, so on screen the ship seems to turn under the player.

@export var target: Node3D
## Supplies the camera roll at the target. Without one the rig does not roll.
@export var ship: Ship
@export var ortho_size := 24.0
@export var distance := 40.0
## Higher = the camera catches up with the player faster.
@export var follow_sharpness := 10.0

var iso_basis := Basis.from_euler(Vector3(deg_to_rad(-35.264), deg_to_rad(45.0), 0.0))

@onready var camera: Camera3D = $Camera


func _ready() -> void:
	# The rig is moved in _process from the player's interpolated position, so it must not be
	# interpolated a second time.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.near = 0.1
	camera.far = 200.0
	camera.basis = iso_basis


func _process(delta: float) -> void:
	update_rig(delta)


func update_rig(delta: float) -> void:
	if target == null:
		return
	# Exact, unsmoothed: the ship turns continuously with the player's position. The interpolated
	# position keeps the turning smooth on displays faster than the 60 Hz physics rate.
	var target_position := target.get_global_transform_interpolated().origin
	rotation.x = _roll_at(target_position)
	var weight := 1.0 - exp(-follow_sharpness * delta)
	camera.position = camera.position.lerp(_camera_goal(target_position), weight)


## Jumps the camera to its resting place without easing.
func snap() -> void:
	if target == null:
		return
	rotation.x = _roll_at(target.global_position)
	camera.position = _camera_goal(target.global_position)


func _roll_at(point: Vector3) -> float:
	return 0.0 if ship == null else ship.camera_roll_at(point)


func _camera_goal(target_position: Vector3) -> Vector3:
	return to_local(target_position) + iso_basis.z * distance
