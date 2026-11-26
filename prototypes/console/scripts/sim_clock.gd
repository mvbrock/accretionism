class_name SimClock
extends RefCounted
## Turns real time into sim time at a chosen speed, or none while paused.

const SPEEDS: Array[float] = [1.0, 60.0, 3600.0]
const _SPEED_LABELS: Array[String] = ["real time", "1 min/s", "1 hour/s"]
## The sim step that goes with each speed: a long step at the fastest speed keeps the sim ahead of the clock.
const _STEPS_S: Array[float] = [0.1, 0.1, 1.0]

var paused := false
var speed_index := 0


func tick(real_delta: float) -> float:
	return 0.0 if paused else real_delta * SPEEDS[speed_index]


## The current speed, such as "1 min/s".
func speed_label() -> String:
	return _SPEED_LABELS[speed_index]


## The sim step to advance with at the current speed.
func step_s() -> float:
	return _STEPS_S[speed_index]
