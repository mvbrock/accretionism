class_name SimClock
extends RefCounted
## The sim day, advanced from real time at one of a few speeds.

const SPEEDS_DAYS_PER_SEC := [1.0 / 24.0, 1.0, 10.0]
const _SPEED_LABELS := ["1 h/s", "1 d/s", "10 d/s"]

var day := 0.0
var paused := false
var speed_index := 1


## Advances by `real_delta` seconds unless paused. Returns the new day.
func tick(real_delta: float) -> float:
	if not paused:
		day += real_delta * SPEEDS_DAYS_PER_SEC[speed_index]
	return day


func label() -> String:
	if paused:
		return "Paused"
	return "Day %.1f · %s" % [day, _SPEED_LABELS[speed_index]]
