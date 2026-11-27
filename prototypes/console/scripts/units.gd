class_name Units
extends RefCounted
## Physical constants and unit conversions. Internal units are SI.

const R := 8.314462618  # J/(mol K)
const GASES: Array[String] = ["O2", "N2", "CO2"]
const TANK_GASES: Array[String] = ["O2", "N2"]
## Float residue from summing 0.1 s steps, smaller than any real remainder.
const SECONDS_EPSILON := 1e-6
const _ZERO_CELSIUS_K := 273.15


static func kelvin(celsius: float) -> float:
	return celsius + _ZERO_CELSIUS_K


static func celsius(kelvin: float) -> float:
	return kelvin - _ZERO_CELSIUS_K


static func whole_seconds_left(seconds: float) -> int:
	return ceili(seconds - SECONDS_EPSILON)


## `m:ss`, or `h:mm:ss` from an hour up; a part second counts as a whole one.
static func duration_text(seconds: float) -> String:
	var total := whole_seconds_left(seconds)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, total % 60]
	return "%d:%02d" % [minutes, total % 60]
