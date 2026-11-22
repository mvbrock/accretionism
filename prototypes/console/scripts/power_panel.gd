class_name PowerPanel
extends RefCounted
## Circuit breakers. A tripped breaker cuts power to whatever it feeds, and
## stays tripped until it is reset. Breakers also trip at random.

## Every breaker id, in the order random trips draw.
var breaker_ids: Array[String]
var tripped: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _mean_time_between_trips_s: float


func _init(rng_seed: int, mean_time_between_trips_s: float, ids: Array[String]) -> void:
	_rng.seed = rng_seed
	_mean_time_between_trips_s = mean_time_between_trips_s
	breaker_ids = ids
	for id in breaker_ids:
		tripped[id] = false


## is_powered, trip and reset expect an id for which has() is true.
func has(id: String) -> bool:
	return tripped.has(id)


func is_powered(id: String) -> bool:
	return not tripped[id]


func trip(id: String) -> bool:
	if tripped[id]:
		return false
	tripped[id] = true
	return true


func reset(id: String) -> bool:
	if not tripped[id]:
		return false
	tripped[id] = false
	return true


## The random stream must not depend on breaker state, so this draws once per
## breaker, tripped or not. Each closed breaker trips with chance `dt / mean`.
func roll_random_trips(dt: float) -> Array[String]:
	var result: Array[String] = []
	if _mean_time_between_trips_s <= 0.0:
		return result
	var chance := dt / _mean_time_between_trips_s
	for id in breaker_ids:
		var draw := _rng.randf()
		if not tripped[id] and draw < chance:
			tripped[id] = true
			result.append(id)
	return result
