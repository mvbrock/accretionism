class_name SimClock
extends RefCounted
## The sim day, advanced from real time at one of a few speeds.

const SPEEDS_DAYS_PER_SEC := [1.0 / 24.0, 1.0, 10.0]
const _SPEED_LABELS := ["1.00 h/s", "1.00 d/s", "10.00 d/s"]

var day := 0.0
var paused := false
var speed_index := 1


## Advances by `real_delta` seconds unless paused. Returns the new day.
func tick(real_delta: float) -> float:
	if not paused:
		day += real_delta * SPEEDS_DAYS_PER_SEC[speed_index]
	return day


## The sim date with the speed, or with "Paused" in place of the speed.
func label() -> String:
	return "Day %.2f · %s" % [day, "Paused" if paused else speed_label()]


## The current speed, such as "1.00 d/s".
func speed_label() -> String:
	return _SPEED_LABELS[speed_index]
