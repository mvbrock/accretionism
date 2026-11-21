class_name Units
extends RefCounted
## Unit constants and display formatting. Internal units are km and days.

const AU_KM := 149597871.0
## 50 km/s.
const TRANSPORT_SPEED_KM_PER_DAY := 4320000.0
## 5 km/s, the speed of Earth–Moon trips.
const LOCAL_SPEED_KM_PER_DAY := 432000.0

const _HOURS_PER_DAY := 24
const _MILLION_KM := 1000000.0


static func format_distance(km: float) -> String:
	if km >= _MILLION_KM:
		return "%.1f M km" % (km / _MILLION_KM)
	return "%s km" % _with_thousands_separators(roundi(km))


## "31 d 4 h", "2 h" or "5 d". Rounded to the nearest hour.
static func format_duration(days: float) -> String:
	var total_hours := roundi(days * _HOURS_PER_DAY)
	@warning_ignore("integer_division")
	var whole_days := total_hours / _HOURS_PER_DAY
	var hours := total_hours % _HOURS_PER_DAY
	if whole_days == 0:
		return "%d h" % hours
	if hours == 0:
		return "%d d" % whole_days
	return "%d d %d h" % [whole_days, hours]


static func _with_thousands_separators(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-" if value < 0 else "") + grouped
