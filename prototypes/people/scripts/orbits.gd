class_name Orbits
extends RefCounted
## Circular, prograde orbits with the Sun at the origin. A position is a pure
## function of the day, so any day (negative included) can be computed directly.

enum Body { EARTH, MOON, MARS }

const _EARTH_RADIUS_KM := Units.AU_KM
const _MARS_RADIUS_KM := 1.524 * Units.AU_KM
const _MOON_RADIUS_KM := 384400.0
const _EARTH_PERIOD_DAYS := 365.256
const _MARS_PERIOD_DAYS := 686.98
const _MOON_PERIOD_DAYS := 27.32

## Starting angle in radians on day 0, set from the data file.
static var _epoch_angle_rad := {Body.EARTH: 0.0, Body.MOON: 0.0, Body.MARS: 0.0}


static func body_name(b: Body) -> String:
	return Body.keys()[b].capitalize()


## `epoch_angles_deg` is keyed by Body.
static func configure(epoch_angles_deg: Dictionary) -> void:
	for body in epoch_angles_deg:
		_epoch_angle_rad[body] = deg_to_rad(epoch_angles_deg[body])


## Position in km relative to the Sun.
static func body_position(b: Body, day: float) -> Vector2:
	match b:
		Body.EARTH:
			return _circular_position(Body.EARTH, _EARTH_RADIUS_KM, _EARTH_PERIOD_DAYS, day)
		Body.MARS:
			return _circular_position(Body.MARS, _MARS_RADIUS_KM, _MARS_PERIOD_DAYS, day)
		_:
			return body_position(Body.EARTH, day) \
				+ _circular_position(Body.MOON, _MOON_RADIUS_KM, _MOON_PERIOD_DAYS, day)


static func _circular_position(b: Body, radius_km: float, period_days: float, day: float) -> Vector2:
	var angle: float = _epoch_angle_rad[b] + TAU * day / period_days
	return radius_km * Vector2(cos(angle), sin(angle))
