extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON

var _ship := Transport.parked_at("Test Ship", EARTH)
var _other := Transport.parked_at("Other Ship", EARTH)


func _trip(ship: Transport, depart: float, arrive: float) -> Trip:
	return Trip.new(ship, EARTH, MOON, depart, arrive, 20, Trip.Kind.SERVICE)


## Departures 1, 3, 3, 8 and 20, the last a long one that is still flying on day 30.
func _schedule() -> Schedule:
	var schedule := Schedule.new()
	for trip in [_trip(_ship, 8.0, 9.0), _trip(_ship, 1.0, 2.0), _trip(_other, 3.0, 4.0), _trip(_ship, 3.0, 5.0), _trip(_other, 20.0, 40.0)]:
		schedule.add(trip)
	return schedule


func _departures(trips: Array[Trip]) -> Array:
	var days := []
	for trip in trips:
		days.append(trip.depart_day)
	return days


func test_departing_after_skips_a_trip_leaving_that_day() -> void:
	var schedule := _schedule()
	assert_true(_departures(schedule.departing_after(3.0)) == [8.0, 20.0],"only later departures")
	assert_true(_departures(schedule.departing_after(-1000.0)).size() == 5, "everything after a day before the schedule")
	assert_true(schedule.departing_after(20.0).is_empty(), "nothing after the last departure")


func test_next_trip_of_is_the_ships_first_later_departure() -> void:
	var schedule := _schedule()
	assert_true(schedule.next_trip_of(_ship, 1.0).depart_day == 3.0, "the ship's own trip after day 1")
	assert_true(schedule.next_trip_of(_other, 3.0).depart_day == 20.0, "after, not at, day 3")
	assert_true(schedule.next_trip_of(_other, 20.0) == null, "none after its last")


func test_has_departure_of_counts_a_trip_leaving_that_day() -> void:
	var schedule := _schedule()
	assert_true(schedule.has_departure_of(_ship, 8.0), "the ship leaves on day 8")
	assert_true(not schedule.has_departure_of(_ship, 8.5), "but has nothing from day 8.5")
	assert_true(schedule.has_departure_of(_other, 4.0), "the other ship has the long trip")


func test_arriving_from_includes_trips_already_flying() -> void:
	var schedule := _schedule()
	assert_true(_departures(schedule.arriving_from(30.0)) == [20.0],"the day-20 trip arrives on day 40")
	assert_true(_departures(schedule.arriving_from(4.0)) == [3.0, 3.0, 8.0, 20.0],"arriving on day 4 counts")
	assert_true(schedule.arriving_from(41.0).is_empty(), "nothing is left to arrive")
