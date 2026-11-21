class_name Units
extends RefCounted
## Physical constants and unit conversions. Internal units are SI.

const R := 8.314462618  # J/(mol K)
const GASES: Array[String] = ["O2", "N2", "CO2"]
const _ZERO_CELSIUS_K := 273.15


static func kelvin(celsius: float) -> float:
	return celsius + _ZERO_CELSIUS_K


static func celsius(kelvin: float) -> float:
	return kelvin - _ZERO_CELSIUS_K
