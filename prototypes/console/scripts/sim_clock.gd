class_name SimClock
extends RefCounted
## Turns real time into sim time at a chosen speed, or none while paused.

## A long step at the fastest speed keeps the sim ahead of the clock, so each speed (sim seconds
## per real second, with its label) carries its own step, a whole multiple of `Ship.STEP_S`.
const _SPEED_TABLE: Array[Dictionary] = [
	{"speed": 1.0, "label": "real time", "step_s": Ship.STEP_S},
	{"speed": 60.0, "label": "1 min/s", "step_s": Ship.STEP_S},
	{"speed": 3600.0, "label": "1 hour/s", "step_s": Ship.STEP_S * 50.0},
]

var paused := false
var speed_index := 0


static func speed_count() -> int:
	return _SPEED_TABLE.size()


## The distinct step sizes the speeds use, shortest first.
static func step_sizes() -> Array[float]:
	var sizes: Array[float] = []
	for entry in _SPEED_TABLE:
		if not sizes.has(entry.step_s):
			sizes.append(entry.step_s)
	sizes.sort()
	return sizes


func tick(real_delta: float) -> float:
	return 0.0 if paused else real_delta * _SPEED_TABLE[speed_index].speed


func speed_label() -> String:
	return _SPEED_TABLE[speed_index].label


func step_s() -> float:
	return _SPEED_TABLE[speed_index].step_s
