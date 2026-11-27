class_name Fleet
extends Node3D
## Holds every ship; only the active one is shown, processed and collidable.
## Each ship remembers where the player was when it was left.

signal ship_changed(ship: Ship)

@export var player: Player
@export var rig: CameraRig
@export var fader: OcclusionFader

var active: Ship
## Ship -> {position, heading, gravity, ladder, climb_s}, for each ship the player has left.
var _poses := {}


func _ready() -> void:
	add_child(Ship.make_environment())
	for ship in ships():
		_set_active(ship, false)
	# Boarding uses the player's and rig's own nodes, so wait for them wherever they sit in the tree.
	for node: Node in [player, rig]:
		if not node.is_node_ready():
			await node.ready
	switch_to(ships()[0])


## The ship children, in scene order.
func ships() -> Array[Ship]:
	var found: Array[Ship] = []
	for child in get_children():
		if child is Ship:
			found.append(child)
	return found


func switch_to(ship: Ship) -> void:
	if ship == active:
		return
	if active != null:
		_poses[active] = {
			"position": player.global_position,
			"heading": player.heading,
			"gravity": player.gravity_enabled,
			"ladder": player.climbing,
			"climb_s": player.climb_s,
		}
		_set_active(active, false)
	active = ship
	_set_active(ship, true)
	var pose: Dictionary = _poses.get(ship, {
		"position": ship.spawn_point(),
		"heading": Vector2(0, 1),
		"gravity": ship.has_gravity(),
		"ladder": null,
		"climb_s": 0.0,
	})
	player.board(ship, pose.position, pose.heading, pose.gravity)
	if pose.ladder != null:
		player.hold_ladder(pose.ladder, pose.climb_s)
	rig.ship = ship
	fader.ship = ship
	rig.snap()
	ship_changed.emit(ship)


## Switches to the ship after the active one, wrapping around.
func next_ship() -> void:
	var all := ships()
	switch_to(all[(all.find(active) + 1) % all.size()])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_ship"):
		next_ship()


func _set_active(ship: Ship, on: bool) -> void:
	ship.visible = on
	ship.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
