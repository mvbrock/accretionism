class_name Units
extends RefCounted
## Unit constants and display formatting. Internal units are km and days.
## Every number shown has two decimal places.

const AU_KM := 149597871.0
## 50 km/s.
const TRANSPORT_SPEED_KM_PER_DAY := 4320000.0
## 5 km/s, the speed of Earth–Moon trips.
const LOCAL_SPEED_KM_PER_DAY := 432000.0

const _MILLION_KM := 1000000.0


static func format_distance(km: float) -> String:
	if km >= _MILLION_KM:
		return "%.2f M km" % (km / _MILLION_KM)
	var hundredths := roundi(km * 100.0)
	@warning_ignore("integer_division")
	return "%s.%02d km" % [_with_thousands_separators(hundredths / 100), hundredths % 100]


## In days, such as "31.17 d".
static func format_duration(days: float) -> String:
	return "%.2f d" % days


static func _with_thousands_separators(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-" if value < 0 else "") + grouped
