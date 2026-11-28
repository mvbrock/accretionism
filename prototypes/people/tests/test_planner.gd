extends TestCase

const EARTH := Orbits.Body.EARTH
const MOON := Orbits.Body.MOON
const MARS := Orbits.Body.MARS

var _ship := Transport.parked_at("Test Ship", EARTH)


func _trip(from: Variant, to: Variant, depart: float, arrive: float, seats := 20) -> Trip:
	return Trip.new(_ship, from, to, depart, arrive, seats, "service")


func _schedule(trips: Array[Trip]) -> Schedule:
	var schedule := Schedule.new()
	for trip in trips:
		schedule.add(trip)
	return schedule


func _party(size: int) -> Party:
	var party := Party.new()
	for i in size:
		party.members.append(Passenger.new())
	return party


func test_soonest_arrival_over_two_hops() -> void:
	var to_moon := _trip(EARTH, MOON, 1.0, 2.0)
	var moon_to_mars := _trip(MOON, MARS, 3.0, 8.0)
	var slow_direct := _trip(EARTH, MARS, 1.0, 20.0)
	var route := Planner.plan(_schedule([to_moon, moon_to_mars, slow_direct]), EARTH, 0.0, MARS, 1)
	assert_true(route == [to_moon, moon_to_mars], "two hops arrive before the slow direct trip")


func test_full_trip_skipped() -> void:
	var full := _trip(EARTH, MARS, 1.0, 5.0)
	full.booked = 20
	var later := _trip(EARTH, MARS, 2.0, 9.0)
	assert_true(Planner.plan(_schedule([full, later]), EARTH, 0.0, MARS, 1) == [later], "the full trip is passed over")


func test_connection_time_enforced() -> void:
	var first := _trip(EARTH, MOON, 1.0, 2.0)
	var too_soon := _trip(MOON, MARS, 2.1, 6.0)
	var late_enough := _trip(MOON, MARS, 2.0 + Config.CONNECTION_DAYS, 7.0)
	var route := Planner.plan(_schedule([first, too_soon, late_enough]), EARTH, 0.0, MARS, 1)
	assert_true(route == [first, late_enough], "a connection needs the minimum time")


func test_first_boarding_skips_connection_time() -> void:
	var soon := _trip(EARTH, MARS, 0.01, 5.0)
	assert_true(Planner.plan(_schedule([soon]), EARTH, 0.0, MARS, 1) == [soon], "boarding at the start needs no connection time")


func test_party_needs_all_seats() -> void:
	var nearly_full := _trip(EARTH, MARS, 1.0, 5.0)
	nearly_full.booked = 18
	var roomy := _trip(EARTH, MARS, 2.0, 9.0)
	var schedule := _schedule([nearly_full, roomy])
	assert_true(Planner.plan(schedule, EARTH, 0.0, MARS, 3) == [roomy], "three do not fit in two seats")
	assert_true(Planner.plan(schedule, EARTH, 0.0, MARS, 2) == [nearly_full], "two fit in two seats")


func test_no_route_returns_empty() -> void:
	var schedule := _schedule([_trip(EARTH, MOON, 1.0, 2.0)])
	assert_true(Planner.plan(schedule, EARTH, 0.0, MARS, 1).is_empty(), "Mars is unreachable")
	assert_true(Planner.plan(schedule, EARTH, 5.0, MOON, 1).is_empty(), "the only trip has left")


func test_blocked_trip_skipped() -> void:
	var blocked := _trip(EARTH, MARS, 1.0, 5.0)
	blocked.blocked = true
	var later := _trip(EARTH, MARS, 2.0, 9.0)
	assert_true(Planner.plan(_schedule([blocked, later]), EARTH, 0.0, MARS, 1) == [later], "the blocked trip is passed over")


func test_first_trip_kept() -> void:
	var aboard := _trip(EARTH, MOON, 1.0, 4.0)
	var moon_to_mars := _trip(MOON, MARS, 5.0, 9.0)
	var direct := _trip(EARTH, MARS, 2.0, 6.0)
	var schedule := _schedule([aboard, moon_to_mars, direct])
	assert_true(Planner.plan(schedule, EARTH, 1.5, MARS, 1, aboard) == [aboard, moon_to_mars], "the route starts with the trip the party is on")
	assert_true(Planner.plan(schedule, EARTH, 1.5, MOON, 1, aboard) == [aboard], "the first trip can reach the destination")
	var too_soon := _trip(MOON, MARS, 4.1, 6.0)
	schedule.add(too_soon)
	assert_true(Planner.plan(schedule, EARTH, 1.5, MARS, 1, aboard) == [aboard, moon_to_mars], "connection time applies after the first trip")


func test_cycler_ride_via_tenders() -> void:
	var cycler := Cycler.new("Aldrin T", Cycler.Direction.UP, 0.0)
	var out := _trip(EARTH, cycler, 10.0, 11.0)
	var back := _trip(cycler, MARS, 100.0, 101.0)
	var route := Planner.plan(_schedule([out, back]), EARTH, 0.0, MARS, 1)
	assert_true(route == [out, back], "Earth tender, cycler, Mars tender")


func test_book_then_cancel_restores_seats() -> void:
	var first := _trip(EARTH, MOON, 1.0, 2.0)
	var second := _trip(MOON, MARS, 3.0, 8.0)
	var party := _party(3)
	for round in 3:
		Planner.book(party, [first, second])
		assert_true(first.booked == 3 and second.booked == 3, "booking takes a seat per member")
		Planner.cancel(party)
		assert_true(first.booked == 0 and second.booked == 0, "cancel frees them")
		assert_true(party.route.is_empty(), "cancel clears the route")
	Planner.book(party, [first, second])
	Planner.cancel(party)
	var booked_after_first_cancel := [first.booked, second.booked]
	Planner.cancel(party)
	assert_true([first.booked, second.booked] == booked_after_first_cancel, "a second cancel changes nothing")
	assert_true(first.booked >= 0 and second.booked >= 0, "booked never goes negative")


func test_cancel_keeps_the_trip_the_party_is_aboard() -> void:
	var first := _trip(EARTH, MOON, 1.0, 2.0)
	var second := _trip(MOON, MARS, 3.0, 8.0)
	var party := _party(2)
	Planner.book(party, [first, second])
	party.aboard = first
	Planner.cancel(party)
	assert_true(first.booked == 2, "the trip underway keeps its seats")
	assert_true(second.booked == 0, "the unboarded trip is freed")


func test_legs_mark_cycler_ride() -> void:
	var cycler := Cycler.new("Aldrin T", Cycler.Direction.UP, 0.0)
	var done := _trip(EARTH, MOON, 1.0, 2.0)
	var out := _trip(MOON, cycler, 3.0, 4.0)
	var back := _trip(cycler, MARS, 100.0, 101.0)
	var party := _party(1)
	party.done_trips = [done]
	Planner.book(party, [out, back])
	var legs := Planner.legs(party)
	assert_true(legs.size() == 4, "done trip, tender out, cycler ride, tender back")
	assert_true(legs[0].status == "done" and legs[1].status == "next", "before boarding")
	assert_true(legs[2].ship_name == "Aldrin T" and legs[2].from_name == "Moon" and legs[2].to_name == "Mars", "the ride is a leg of the cycler")
	assert_near(legs[2].start, 4.0, 1e-9, "the ride starts when the tender docks")
	assert_near(legs[2].end, 100.0, 1e-9, "the ride ends when the next tender leaves")
	assert_true(legs[2].status == "next", "not yet riding")
	party.done_trips = [done, out]
	party.place = cycler
	var riding := Planner.legs(party)
	assert_true(riding[1].status == "done" and riding[2].status == "current" and riding[3].status == "next", "riding the cycler")
	party.place = MARS
	party.aboard = back
	party.done_trips = [done, out]
	var aboard := Planner.legs(party)
	assert_true(aboard[2].status == "done" and aboard[3].status == "current", "aboard the last tender")


func test_legs_show_riding_party_aboard_with_no_route() -> void:
	var party := _party(1)
	var ridden := _trip(EARTH, MOON, 1.0, 2.0)
	var riding := _trip(MOON, EARTH, 3.0, 4.0)
	party.done_trips = [ridden]
	party.aboard = riding
	var legs := Planner.legs(party)
	assert_true(legs.size() == 2, "the trip it is aboard shows even though no route holds it")
	assert_true(legs[0].status == "done" and legs[1].status == "current", "and is the current leg")
	assert_true(legs[1].from_name == "Moon" and legs[1].to_name == "Earth", "with its stops")
