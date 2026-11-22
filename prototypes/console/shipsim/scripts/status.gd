class_name Status
extends RefCounted
## How worrying a reading is, judged against a band from the data file.

enum Level { NOMINAL, WARNING, DANGER }


## `band` has `nominal` [low, high] (both inclusive) and `danger_below` /
## `danger_above`, either of which may be null.
static func classify(value: float, band: Dictionary) -> Level:
	var danger_below: Variant = band.get("danger_below")
	var danger_above: Variant = band.get("danger_above")
	if danger_below != null and value < float(danger_below):
		return Level.DANGER
	if danger_above != null and value > float(danger_above):
		return Level.DANGER
	if value >= float(band.nominal[0]) and value <= float(band.nominal[1]):
		return Level.NOMINAL
	return Level.WARNING


static func worst(levels: Array) -> Level:
	var result := Level.NOMINAL
	for level in levels:
		result = maxi(result, level) as Level
	return result
