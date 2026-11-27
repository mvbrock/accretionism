class_name Ladder
extends RefCounted
## A pipe with a ladder inside: the climber's feet move along `axis` from `start` for `length` metres.


## A place to step on or off the ladder.
class Landing:
	## Distance along the axis.
	var s: float
	## Where the player stands after stepping off (feet, just above the floor).
	var exit: Vector3
	## Unit vector from `exit` toward the pipe: the way a climber at this landing faces.
	var facing: Vector3


var start: Vector3
## Unit vector.
var axis: Vector3
var length: float
var landings: Array[Landing] = []


func _init(start_point: Vector3, unit_axis: Vector3, ladder_length: float) -> void:
	start = start_point
	axis = unit_axis
	length = ladder_length


func add_landing(s: float, exit: Vector3, facing: Vector3) -> void:
	var landing := Landing.new()
	landing.s = s
	landing.exit = exit
	landing.facing = facing
	landings.append(landing)


## The feet position `s` metres along the ladder, clamped to its length.
func point_at(s: float) -> Vector3:
	return start + axis * clampf(s, 0.0, length)


## The index of the landing whose exit is nearest `p` and within `reach` of it, or -1.
func landing_near(p: Vector3, reach: float) -> int:
	var best := -1
	var best_distance := reach
	for i in landings.size():
		var distance := landings[i].exit.distance_to(p)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


## The index of the landing whose `s` is nearest `s` and within `tolerance` of it, or -1.
func landing_at(s: float, tolerance: float) -> int:
	var best := -1
	var best_distance := tolerance
	for i in landings.size():
		var distance := absf(landings[i].s - s)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best
