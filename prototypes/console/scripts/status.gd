class_name Status
extends RefCounted
## How worrying something is. NORMAL: everything works. WARNING: equipment is down, such as a
## tripped breaker or a faulted system. DANGER: a change that could cause harm, such as a reading
## outside its normal band. CRITICAL: death is imminent, such as a room open to vacuum.

enum Level { NORMAL, WARNING, DANGER, CRITICAL }


## `band` has `normal` [low, high] (both inclusive) and `critical_below` / `critical_above`, either of
## which may be null. Inside `normal` is NORMAL, past a critical limit CRITICAL, and between them DANGER.
static func classify(value: float, band: Dictionary) -> Level:
	var critical_below: Variant = band.get("critical_below")
	var critical_above: Variant = band.get("critical_above")
	if critical_below != null and value < float(critical_below):
		return Level.CRITICAL
	if critical_above != null and value > float(critical_above):
		return Level.CRITICAL
	if value >= float(band.normal[0]) and value <= float(band.normal[1]):
		return Level.NORMAL
	return Level.DANGER


static func worst(levels: Array) -> Level:
	var result := Level.NORMAL
	for level in levels:
		result = maxi(result, level) as Level
	return result


## The level's name as the ship table shows it, such as `WARNING`.
static func level_name(level: Level) -> String:
	return Level.keys()[level]
