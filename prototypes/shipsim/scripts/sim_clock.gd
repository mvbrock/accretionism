class_name SimClock
extends RefCounted
## Turns real time into sim time at a chosen speed, or none while paused.

const SPEEDS: Array[float] = [1.0, 10.0, 100.0]

var paused := false
var speed_index := 0


func tick(real_delta: float) -> float:
	return 0.0 if paused else real_delta * SPEEDS[speed_index]


func label() -> String:
	if paused:
		return "❚❚ Paused"
	return "▶ %d×" % int(SPEEDS[speed_index])
