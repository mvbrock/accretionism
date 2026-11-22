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


## Seconds left as a whole number, rounded up past float residue.
static func whole_seconds_left(seconds: float) -> int:
	return ceili(seconds - SECONDS_EPSILON)
