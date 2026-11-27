class_name Dispatcher
extends RefCounted
## Plans every service trip ahead of time. It only computes trips; replaying
## them on the fleet is up to the caller. Each ship is planned from where its
## previous planned trip left it.

const _SHUTTLE_BODIES := [Orbits.Body.EARTH, Orbits.Body.MOON]
const _EXPRESS_BODIES := [Orbits.Body.EARTH, Orbits.Body.MARS]

## Where a ship will be once its planned trips are done, and from when.
class Plan:
	var location: Variant
	var free_day: float
	## Tenders only: flybys whose departure is on or before this day are handled.
	var flybys_handled_to: float


var _fleet: Fleet
var _schedule: Schedule
var _plans: Dictionary[Transport, Plan] = {}


func _init(fleet: Fleet, schedule: Schedule) -> void:
	_fleet = fleet
	_schedule = schedule
	var ships_started_at := {}
	for ship in fleet.transports:
		var plan := Plan.new()
		plan.location = ship.host if ship.state == Transport.State.DOCKED else ship.body
		var service := fleet.service_of[ship]
		var home_key := "%s %s" % [service, Fleet.target_name(plan.location)]
		var place_in_line: int = ships_started_at.get(home_key, 0)
		ships_started_at[home_key] = place_in_line + 1
		plan.free_day = fleet.day + place_in_line * _first_departure_stagger(service)
		plan.flybys_handled_to = fleet.day
		_plans[ship] = plan


## Ships of one service at the same body leave this many days apart at the start.
func _first_departure_stagger(service: String) -> float:
	match service:
		"shuttle":
			return Config.SHUTTLE_STAGGER_DAYS
		"express":
			return Config.EXPRESS_STAGGER_DAYS
	return 0.0


## Plans each service's trips that depart on or before `day`.
func extend_to(day: float) -> void:
	for ship in _fleet.transports:
		match _fleet.service_of[ship]:
			"shuttle":
				_plan_round_trips(ship, day, _SHUTTLE_BODIES, Config.SHUTTLE_TURNAROUND_DAYS)
			"express":
				_plan_round_trips(ship, day, _EXPRESS_BODIES, Config.EXPRESS_TURNAROUND_DAYS)
			"tender":
				_plan_tender_trips(ship, day)


## Trips departing on or after `day_from` and before `day_to`.
func transport_trips_due(day_from: float, day_to: float) -> Array[Trip]:
	return _schedule.trips.filter(
		func(trip: Trip) -> bool: return trip.depart_day >= day_from and trip.depart_day < day_to)


## The ship flies between the two `bodies`, waiting `turnaround` days after
## each arrival.
func _plan_round_trips(ship: Transport, day: float, bodies: Array, turnaround: float) -> void:
	var plan := _plans[ship]
	while plan.free_day <= day:
		var destination: Orbits.Body = bodies[1] if plan.location == bodies[0] else bodies[0]
		var trip := _plan_trip(ship, destination, plan.free_day)
		plan.free_day = trip.arrive_day + turnaround


## For each flyby at its planet the tender flies out to the cycler and back,
## unless it is still away.
func _plan_tender_trips(ship: Transport, day: float) -> void:
	var plan := _plans[ship]
	var planet: Orbits.Body = plan.location
	var handled_from := plan.flybys_handled_to
	plan.flybys_handled_to = day
	for flyby in _flybys_at(planet, handled_from + Config.TENDER_LEAD_DAYS, day + Config.TENDER_LEAD_DAYS):
		var depart_day: float = flyby.day - Config.TENDER_LEAD_DAYS
		if plan.free_day > depart_day:
			continue
		var out_trip := _plan_trip(ship, flyby.cycler, depart_day)
		var leave_day := maxf(flyby.day + Config.TENDER_LINGER_DAYS, out_trip.arrive_day)
		var back_trip := _plan_trip(ship, planet, leave_day)
		plan.free_day = back_trip.arrive_day


## Flybys at `planet` falling in (`after_day`, `to_day`], as {day, cycler} in time order.
func _flybys_at(planet: Orbits.Body, after_day: float, to_day: float) -> Array:
	var flybys := []
	for cycler in _fleet.cyclers:
		var probe_day := after_day
		while probe_day <= to_day:
			var leg := cycler.leg_at(probe_day)
			if leg.to == planet and leg.end_day > after_day and leg.end_day <= to_day:
				flybys.append({day = leg.end_day, cycler = cycler})
			probe_day = leg.end_day + 1e-6
	flybys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.day < b.day)
	return flybys


## Plans and schedules one trip from where the ship will be, and leaves it there.
func _plan_trip(ship: Transport, destination: Variant, depart_day: float) -> Trip:
	var plan := _plans[ship]
	var solution := _fleet.solve_trip(plan.location, depart_day, destination)
	assert(solution.ok, "%s has no route to %s" % [ship.name, Fleet.target_name(destination)])
	var trip := Trip.new(ship, plan.location, destination, depart_day, solution.t_arrive,
		Config.SEATS[_fleet.service_of[ship]], "service")
	_schedule.add(trip)
	plan.location = destination
	plan.free_day = trip.arrive_day
	return trip
