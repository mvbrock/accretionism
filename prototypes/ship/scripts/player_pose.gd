class_name PlayerPose
extends RefCounted
## What a ship remembers about the player aboard it.

var position: Vector3
var heading: Vector2
var gravity: bool
## The ladder held, or null.
var ladder: Ladder = null
## How far along `ladder` the feet are.
var climb_s := 0.0


func _init(at := Vector3.ZERO, facing := Vector2(0, 1), with_gravity := true) -> void:
	position = at
	heading = facing
	gravity = with_gravity


## Standing at the ship's spawn point, facing heading (0, 1), perpendicular to up and world X, with the ship's own gravity.
static func at_spawn(ship: Ship) -> PlayerPose:
	return PlayerPose.new(ship.spawn_point(), Vector2(0, 1), ship.has_gravity())
