class_name Player
extends CharacterBody3D
## Capsule walker on the inside of the spinning ring. "Up" always points toward the spin axis.
## Controls are ship-relative: W/S walk around the ring, A/D walk across it.

@export var walk_speed := 3.0
@export var gravity := 9.8
@export var turn_speed := 12.0

## x = across the ring (D = +1), y = around the ring (W = +1).
var move_input := Vector2.ZERO
## When true, `move_input` is set by code (tests, auto-walk) instead of the keyboard.
var drive_by_code := false

var _facing := Vector3.FORWARD


static func ensure_input_actions() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)


func _ready() -> void:
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(40.0)
	var up := RingGeometry.up_at(global_position)
	_facing = up.cross(Vector3.RIGHT)
	_orient(up)


func _physics_process(delta: float) -> void:
	if not drive_by_code:
		move_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")

	var up := RingGeometry.up_at(global_position)
	up_direction = up
	var around := up.cross(Vector3.RIGHT)
	var desired := around * move_input.y + Vector3.RIGHT * move_input.x
	desired = desired.limit_length(1.0) * walk_speed
	if is_on_floor() and desired.length_squared() > 0.0:
		# Follow the panel's slope so walking downhill toward a seam stays on the floor.
		desired = desired.slide(get_floor_normal()).normalized() * desired.length()

	var vertical := velocity.dot(up)
	vertical = 0.0 if is_on_floor() else vertical - gravity * delta
	velocity = desired + up * vertical
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and not is_on_floor():
		# Walking uphill out of a seam points velocity "up", which disables Godot's own snap.
		apply_floor_snap()

	if desired.length_squared() > 0.0001:
		# Turn around "up" by an angle; a slerp can't turn through 180° when reversing W↔S.
		var weight := 1.0 - exp(-turn_speed * delta)
		var turn := _facing.signed_angle_to(desired.normalized(), up)
		if absf(turn) > PI - 0.01:
			turn = PI - 0.01  # exactly opposite: pick a side so the turn is visible
		_facing = _facing.rotated(up, turn * weight)
	_orient(RingGeometry.up_at(global_position))


## Stands the body upright along `up` and faces it along `_facing` (projected onto the floor plane).
func _orient(up: Vector3) -> void:
	if up.length_squared() < 0.5:
		return  # on the spin axis (e.g. before being placed): no meaningful "up"
	var forward := (_facing - up * _facing.dot(up))
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.RIGHT)
	forward = forward.normalized()
	_facing = forward
	var back := -forward
	global_basis = Basis(up.cross(back), up, back)
