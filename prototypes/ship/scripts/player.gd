class_name Player
extends CharacterBody3D
## Capsule walker aboard a ship. "Up" is whatever the ship says it is at the body's position.
## It faces the mouse; W/S move forward and back along that facing, A/D strafe.
## E grabs a ladder at a landing, W/S climb it, and E lets go at a landing.
## G toggles gravity. Without it the body lies horizontal and hovers at FLOAT_HEIGHT, and a
## key press sets a drift that carries on after release until it hits something or another key
## changes it.

## Height of the body's origin above the floor while floating, which puts its middle mid-corridor.
const FLOAT_HEIGHT := 1.6
## How quickly the body settles to FLOAT_HEIGHT (1/s).
const FLOAT_SHARPNESS := 3.0
## How quickly the body tips between upright and horizontal.
const TIP_SHARPNESS := 6.0

## Metres per second along a ladder.
const CLIMB_SPEED := 1.5
## How close to a landing's exit the player must stand to grab the ladder.
const REACH := 1.2
## How close along the ladder to a landing the player must be to let go there.
const LANDING_SNAP := 0.5

## The ship the body walks on; it answers which way is up.
@export var ship: Ship
@export var walk_speed := 3.0
@export var gravity := 9.8
@export var turn_speed := 12.0

## Relative to the facing: x = strafe (D = +1), y = forward (W = +1).
var move_input := Vector2.ZERO
## Ship-relative direction to turn and face (x = across (world X), y = perpendicular to up and X); zero keeps
## the current facing.
var aim_heading := Vector2.ZERO
## When true, `move_input` and `aim_heading` are set by code (tests, auto-walk) instead of
## the keyboard and mouse.
var drive_by_code := false
## The view the mouse points through.
var aim_camera: Camera3D

var gravity_enabled := true

## The ladder held, or null while walking or floating.
var climbing: Ladder = null
## Distance along `climbing` the feet are at; `pose()` saves it to resume the climb.
var climb_s := 0.0

## Facing, ship-relative like `aim_heading`, so it turns with the ring as the body walks a lap.
var heading := Vector2(0, 1)
## Zero-g velocity along the floor, ship-relative like `aim_heading` (m/s).
var _drift := Vector2.ZERO

## Holds the visible body; tipped horizontal in zero-g.
@onready var _pivot: Node3D = $Pivot
## Must stay a direct child of the body for Godot to collide with it, so it copies the pivot's tip.
@onready var _shape: CollisionShape3D = $CollisionShape3D


static func ensure_input_actions() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"toggle_gravity": KEY_G,
		"next_ship": KEY_TAB,
		"interact": KEY_E,
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
	if ship == null:
		return
	_orient(ship.up_at(global_position))


## Aims the facing at a world point, flattened onto the floor plane.
func aim_at(point: Vector3) -> void:
	var to_point := point - global_position
	var flat := Vector2(to_point.dot(Vector3.RIGHT), to_point.dot(_around()))
	if flat.length_squared() > 0.01:
		aim_heading = flat.normalized()


## Aims at the spot under `screen_point`, on the floor-parallel plane through the body.
func aim_through(camera: Camera3D, screen_point: Vector2) -> void:
	var plane := Plane(ship.up_at(global_position), global_position)
	var hit = plane.intersects_ray(camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point))
	if hit != null:
		aim_at(hit)


## Floating mode has no floor, so Godot doesn't snap the body back down to it.
func set_gravity_enabled(enabled: bool) -> void:
	gravity_enabled = enabled
	_drift = Vector2.ZERO
	motion_mode = MOTION_MODE_GROUNDED if enabled else MOTION_MODE_FLOATING


## Where the player is now, as a ship would remember it.
func pose() -> PlayerPose:
	var now := PlayerPose.new(global_position, heading, gravity_enabled)
	now.ladder = climbing
	now.climb_s = climb_s
	return now


## Puts the body aboard `new_ship` as `at` describes, at rest and already tipped to match its
## gravity (a ship without gravity overrides `at.gravity`), holding `at.ladder` if it has one.
func board(new_ship: Ship, at: PlayerPose) -> void:
	ship = new_ship
	climbing = null
	global_position = at.position
	heading = at.heading
	aim_heading = Vector2.ZERO
	velocity = Vector3.ZERO
	set_gravity_enabled(at.gravity and new_ship.has_gravity())
	_pivot.rotation.x = _wanted_tip()
	_shape.transform = _pivot.transform
	_orient(ship.up_at(global_position))
	reset_physics_interpolation()
	if at.ladder != null:
		_hold_ladder(at.ladder, at.climb_s)


## E: grab the ladder with a landing within REACH, or let go at a landing within LANDING_SNAP.
func interact() -> void:
	if climbing == null:
		_grab_nearby_ladder()
	else:
		_let_go_at_landing()


## What E would do now, as a prompt for the screen.
func interact_hint() -> String:
	if climbing == null:
		return "E: climb" if _ladder_in_reach() != null else ""
	if climbing.landing_at(climb_s, LANDING_SNAP) != -1:
		return "W/S: climb   E: let go"
	return "W/S: climb"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("toggle_gravity") and climbing == null and ship != null and ship.has_gravity():
		set_gravity_enabled(not gravity_enabled)


## The ladder with a landing in reach of the spot on the floor under the body, so a floating
## player can grab too.
func _ladder_in_reach() -> Ladder:
	if ship == null:
		return null
	var reach_point := _reach_point()
	for ladder in ship.ladders:
		if ladder.landing_near(reach_point, REACH) != -1:
			return ladder
	return null


## Where reach is measured from: the body's origin, or the floor point under it when floating.
func _reach_point() -> Vector3:
	if gravity_enabled:
		return global_position
	var up := ship.up_at(global_position)
	return global_position - up * _height_above_floor(up)


func _grab_nearby_ladder() -> void:
	var ladder := _ladder_in_reach()
	if ladder == null:
		return
	var landing := ladder.landings[ladder.landing_near(_reach_point(), REACH)]
	_hold_ladder(ladder, landing.s)
	heading = _heading_toward(landing.facing)
	_orient(ship.up_at(global_position))


## Holds `ladder` with the feet `s` metres along it, at rest.
func _hold_ladder(ladder: Ladder, s: float) -> void:
	climbing = ladder
	climb_s = s
	global_position = ladder.point_at(s)
	_stop()
	reset_physics_interpolation()


func _let_go_at_landing() -> void:
	var i := climbing.landing_at(climb_s, LANDING_SNAP)
	if i == -1:
		return
	var landing := climbing.landings[i]
	climbing = null
	global_position = landing.exit
	heading = _heading_toward(-landing.facing)
	aim_heading = Vector2.ZERO
	_stop()
	reset_physics_interpolation()


## Zeroes velocity and drift.
func _stop() -> void:
	velocity = Vector3.ZERO
	_drift = Vector2.ZERO
	_orient(ship.up_at(global_position))


## The ship-relative 2D heading that faces the 3D direction `direction`.
func _heading_toward(direction: Vector3) -> Vector2:
	return Vector2(direction.dot(Vector3.RIGHT), direction.dot(_around())).normalized()


## Climbing: W/S slide along the ladder; the body is placed on it, with no walking or drift.
func _climb(delta: float) -> void:
	climb_s = clampf(climb_s + move_input.y * CLIMB_SPEED * delta, 0.0, climbing.length)
	global_position = climbing.point_at(climb_s)
	_orient(ship.up_at(global_position))
	_pivot.rotation.x = _wanted_tip()
	_shape.transform = _pivot.transform


func _physics_process(delta: float) -> void:
	if ship == null:
		return
	if not drive_by_code:
		move_input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		if aim_camera != null and climbing == null:
			aim_through(aim_camera, get_viewport().get_mouse_position())
	if climbing != null:
		_climb(delta)
		return
	_turn_toward_aim(delta)

	var up := ship.up_at(global_position)
	up_direction = up
	var right := Vector2(heading.y, -heading.x)
	var push := (heading * move_input.y + right * move_input.x).limit_length(1.0) * walk_speed
	if not gravity_enabled and push != Vector2.ZERO:
		_drift = push
	var ship_velocity := push if gravity_enabled else _drift
	var desired := Vector3.RIGHT * ship_velocity.x + _around() * ship_velocity.y
	if is_on_floor() and desired.length_squared() > 0.0:
		# Follow the panel's slope so walking downhill toward a seam stays on the floor.
		desired = desired.slide(get_floor_normal()).normalized() * desired.length()

	var vertical := velocity.dot(up)
	if not gravity_enabled:
		vertical = (FLOAT_HEIGHT - _height_above_floor(up)) * FLOAT_SHARPNESS
	elif is_on_floor():
		vertical = 0.0
	else:
		vertical -= gravity * delta
	velocity = desired + up * vertical
	var was_on_floor := is_on_floor()
	if move_and_slide() and not gravity_enabled:
		_drift = Vector2.ZERO  # bumped into a wall or crate: the drift ends there
	if gravity_enabled and was_on_floor and not is_on_floor():
		# Walking uphill out of a seam points velocity "up", which disables Godot's own snap.
		apply_floor_snap()

	_orient(ship.up_at(global_position))
	_pivot.rotation.x = lerp_angle(_pivot.rotation.x, _wanted_tip(), 1.0 - exp(-TIP_SHARPNESS * delta))
	_shape.transform = _pivot.transform


## The pivot's tilt about X: upright with gravity, lying horizontal without.
func _wanted_tip() -> float:
	return 0.0 if gravity_enabled or climbing != null else -PI / 2.0


## Unit direction perpendicular to both up and world X (the way a heading's y points).
func _around() -> Vector3:
	return ship.up_at(global_position).cross(Vector3.RIGHT)


func _turn_toward_aim(delta: float) -> void:
	if aim_heading == Vector2.ZERO:
		return
	# Turn by an angle; a lerp can't turn through 180°.
	var turn := heading.angle_to(aim_heading)
	if absf(turn) > PI - 0.01:
		turn = PI - 0.01  # exactly opposite: pick a side so the turn is visible
	heading = heading.rotated(turn * (1.0 - exp(-turn_speed * delta))).normalized()


## Distance from the body's origin down to the floor beneath it, measured perpendicular to the
## floor panel, or FLOAT_HEIGHT when there is none, so floating holds its height.
func _height_above_floor(up: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
			global_position + up * 0.1, global_position - up * 20.0, Ship.FLOOR_LAYER)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return FLOAT_HEIGHT
	return (global_position - hit.position).dot(hit.normal)


## Stands the body upright along `up` and faces it along `heading`.
func _orient(up: Vector3) -> void:
	if up.length_squared() < 0.5:
		return  # on the spin axis (e.g. before being placed): no meaningful "up"
	var back := -(Vector3.RIGHT * heading.x + up.cross(Vector3.RIGHT) * heading.y)
	global_basis = Basis(up.cross(back), up, back)
