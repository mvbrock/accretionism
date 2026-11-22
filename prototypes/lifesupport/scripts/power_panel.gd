class_name PowerPanel
extends RefCounted
## Circuit breakers. A tripped breaker cuts power to whatever it feeds, and
## stays tripped until it is reset. Breakers also trip at random.

const BREAKER_IDS: Array[String] = [
	"light-cockpit", "light-main", "light-cargo", "d1", "d2", "hatch",
	"pressure-control", "hvac", "air-recycler",
]

## Breaker id -> true when tripped.
var tripped: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _mean_time_between_trips_s: float


func _init(rng_seed: int, mean_time_between_trips_s: float) -> void:
	_rng.seed = rng_seed
	_mean_time_between_trips_s = mean_time_between_trips_s
	for id in BREAKER_IDS:
		tripped[id] = false


## is_powered, trip and reset expect an id for which has() is true.
func has(id: String) -> bool:
	return tripped.has(id)


func is_powered(id: String) -> bool:
	return not tripped[id]


## Trips a closed breaker. False when it was already tripped.
func trip(id: String) -> bool:
	if tripped[id]:
		return false
	tripped[id] = true
	return true


## Closes a tripped breaker. False when it was not tripped.
func reset(id: String) -> bool:
	if not tripped[id]:
		return false
	tripped[id] = false
	return true


## Gives each closed breaker a chance of `dt / mean` to trip. Draws once per
## breaker, tripped or not, so the random stream does not depend on state.
## Returns the ids it tripped.
func roll_random_trips(dt: float) -> Array[String]:
	var result: Array[String] = []
	if _mean_time_between_trips_s <= 0.0:
		return result
	var chance := dt / _mean_time_between_trips_s
	for id in BREAKER_IDS:
		var draw := _rng.randf()
		if not tripped[id] and draw < chance:
			tripped[id] = true
			result.append(id)
	return result
