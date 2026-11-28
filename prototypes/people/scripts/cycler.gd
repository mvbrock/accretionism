class_name Cycler
extends RefCounted
## An Aldrin cycler on a fixed timetable. Each leg is a straight line from the
## departure planet's position when the leg starts to the arrival planet's
## position when it ends, so every flyby meets its planet exactly.

enum Direction { UP, DOWN }

static var cycle_days := 780.0
static var short_leg_days := 146.0

var name: String
## UP flies Earth -> Mars on its short leg, DOWN flies Mars -> Earth.
var direction: Direction
## Day of the first short-leg departure within one cycle.
var phase_day: float


func _init(cycler_name: String, cycler_direction: Direction, cycler_phase_day: float) -> void:
	name = cycler_name
	direction = cycler_direction
	phase_day = cycler_phase_day


## Works for negative days: legs that began before day 0 follow the same timetable.
func leg_at(day: float) -> Dictionary:
	var cycle_number := floorf((day - phase_day) / cycle_days)
	var cycle_start := phase_day + cycle_number * cycle_days
	var is_short_leg := day - cycle_start < short_leg_days
	var short_leg_origin := Orbits.Body.EARTH if direction == Direction.UP else Orbits.Body.MARS
	var short_leg_destination := Orbits.Body.MARS if direction == Direction.UP else Orbits.Body.EARTH
	if is_short_leg:
		return {from = short_leg_origin, to = short_leg_destination,
			start_day = cycle_start, end_day = cycle_start + short_leg_days}
	return {from = short_leg_destination, to = short_leg_origin,
		start_day = cycle_start + short_leg_days, end_day = cycle_start + cycle_days}


func position(day: float) -> Vector2:
	var leg := leg_at(day)
	var leg_start := Orbits.body_position(leg.from, leg.start_day)
	var leg_end := Orbits.body_position(leg.to, leg.end_day)
	return leg_start.lerp(leg_end, progress(day))


## 0 to 1 through the current leg. The speed is constant, so by time equals by distance.
func progress(day: float) -> float:
	var leg := leg_at(day)
	return (day - leg.start_day) / (leg.end_day - leg.start_day)


func last_flyby(day: float) -> Orbits.Body:
	return leg_at(day).from
