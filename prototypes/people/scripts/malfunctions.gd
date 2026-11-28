class_name Malfunctions
extends RefCounted
## The daily rolls for docking failures and life-support faults, and what they do
## to the parties they strike. A malfunction never changes a ship's course, only
## its passengers' plans.

const DOCKING_FAILURE := "docking failure"
const LIFE_SUPPORT_FAULT := "life-support fault"
const CAUSE := "ship malfunction"


static func install(sim: Sim) -> void:
	sim.on_daily.append(_roll_ships)


## What a party aboard `trip` reads when it rides past the stop its ship cannot dock at.
static func ride_on_text(trip: Trip) -> String:
	var failed: Variant = trip.docking_failure_on
	if failed is Cycler:
		return "Docking failure on %s; staying aboard %s past %s" % [failed.name, trip.ship.name, failed.name]
	return "Docking failure on %s; staying aboard past %s" % [failed.name, Fleet.target_name(trip.to)]


## Strikes `ship`, a Cycler or a Transport, with a malfunction of `kind`.
static func strike(sim: Sim, ship: Variant, kind: String) -> void:
	match kind:
		DOCKING_FAILURE:
			if ship is Cycler:
				_fail_cycler_docking(sim, ship)
			else:
				_fail_transport_docking(sim, ship)
		LIFE_SUPPORT_FAULT:
			if ship is Cycler:
				_fault_cycler_life_support(sim, ship)
			else:
				_fault_transport_life_support(sim, ship)
		_:
			push_error("Nothing handles the %s malfunction" % kind)


## The trips off `cycler` after today that have not been blocked, a group for each
## flyby, soonest flyby first.
static func exit_groups(sim: Sim, cycler: Cycler) -> Array[Array]:
	var groups: Array[Array] = []
	var group_of_flyby := {}
	for trip in sim.schedule.trips:
		if not is_same(trip.from, cycler) or trip.blocked or trip.depart_day <= sim.day:
			continue
		var flyby: float = cycler.leg_at(trip.depart_day).start_day
		if not group_of_flyby.has(flyby):
			group_of_flyby[flyby] = []
			groups.append(group_of_flyby[flyby])
		group_of_flyby[flyby].append(trip)
	return groups


## The trips off `cycler` at its next flyby, or none.
static func next_exit_group(sim: Sim, cycler: Cycler) -> Array:
	var groups := exit_groups(sim, cycler)
	return [] if groups.is_empty() else groups[0]


## Tries again to leave the cycler, after a flyby with no room.
static func resume_exit(sim: Sim, party: Party) -> void:
	var is_waiting := party.state == Party.State.HELD and party.route.is_empty() and party.aboard == null \
			and party.place is Cycler and not party.is_on_medical_route(sim.day)
	if is_waiting:
		_leave_cycler(sim, party, party.place)


static func _roll_ships(sim: Sim, _day: int) -> void:
	for ship in sim.fleet.ships():
		if sim.docking_failure_until.has(ship):
			continue
		var roll := sim.rng.randf()
		if roll < Config.DOCKING_FAILURE_CHANCE:
			strike(sim, ship, DOCKING_FAILURE)
		elif roll < Config.DOCKING_FAILURE_CHANCE + Config.LIFE_SUPPORT_CHANCE:
			strike(sim, ship, LIFE_SUPPORT_FAULT)


## The ship's current or next trip cannot dock where it arrives, and neither can the
## trip after it. Parties aboard ride on to the end of that one.
static func _fail_transport_docking(sim: Sim, ship: Transport) -> void:
	var arriving := sim.trip_in_flight(ship)
	if arriving == null:
		arriving = sim.schedule.next_trip_of(ship, sim.day)
	if arriving == null:
		return
	var following := sim.schedule.next_trip_of(ship, arriving.arrive_day)
	var closed: Array[Trip] = [arriving]
	var ends_on := arriving.arrive_day
	if following != null:
		closed.append(following)
		ends_on = following.depart_day
	if arriving.docking_failure_on == null:
		arriving.docking_failure_on = ship
	sim.docking_failure_until[ship] = ends_on
	_close_and_replan(sim, ship, closed)


## Every trip to or from the cycler, from now to its next flyby and the tenders' linger after it.
static func _fail_cycler_docking(sim: Sim, cycler: Cycler) -> void:
	var until: float = cycler.leg_at(sim.day).end_day + Config.TENDER_LINGER_DAYS
	var closed: Array[Trip] = []
	for trip in sim.schedule.trips:
		var arrives: bool = is_same(trip.to, cycler) and trip.arrive_day >= sim.day and trip.depart_day <= until
		var leaves: bool = is_same(trip.from, cycler) and trip.depart_day >= sim.day and trip.depart_day <= until
		if arrives and trip.docking_failure_on == null:
			trip.docking_failure_on = cycler
		if arrives or leaves:
			closed.append(trip)
	sim.docking_failure_until[cycler] = until
	_close_and_replan(sim, cycler, closed)


## Closes the trips to planning and re-plans every party booked on one. Parties aboard
## a trip that cannot dock ride on; the sim moves them at the stop.
static func _close_and_replan(sim: Sim, ship: Variant, closed: Array[Trip]) -> void:
	for trip in closed:
		trip.blocked = true
	for party in sim.parties:
		var rides_on := party.aboard != null and party.aboard.docking_failure_on != null
		if not rides_on and party.route.any(func(trip: Trip) -> bool: return closed.has(trip)):
			party.write(sim.day, "Docking failure on %s; re-planning" % ship.name, CAUSE)
			sim.replan(party, party.destination, sim.day, CAUSE)


## Everyone aboard gets off at the trip's stop, then plans from there.
static func _fault_transport_life_support(sim: Sim, ship: Transport) -> void:
	var trip := sim.trip_in_flight(ship)
	if trip == null:
		return
	for party in sim.parties:
		if party.aboard == trip and party.stable_until < sim.day:
			Planner.cancel(party)
			party.route = [trip] as Array[Trip]
			party.state = Party.State.TRAVELLING
			party.write(sim.day, "Life-support fault on %s; getting off at %s" % [ship.name, Fleet.target_name(trip.to)], CAUSE)


static func _fault_cycler_life_support(sim: Sim, cycler: Cycler) -> void:
	for party in sim.parties:
		if party.aboard == null and is_same(party.place, cycler) and party.stable_until < sim.day:
			# TASK 8: swap in Rescues.request here for a party that cannot wait for a flyby.
			_leave_cycler(sim, party, cycler)


## Plans the party off the cycler by the next trip with seats for it, to the body
## reached soonest. When the next flyby has no room it stays aboard and tries again at the flyby after.
static func _leave_cycler(sim: Sim, party: Party, cycler: Cycler) -> void:
	party.must_leave = cycler
	Planner.cancel(party)
	var groups := exit_groups(sim, cycler)
	if groups.is_empty():
		sim.replan(party, party.destination, sim.day, CAUSE)
		return
	var next_group := groups[0]
	if not next_group.any(func(trip: Trip) -> bool: return trip.seats_left() >= party.size()):
		_stay_aboard(sim, party, cycler, groups)
		return
	var via: Variant = Planner.soonest_body(sim.schedule, cycler, sim.day, party.size(), null, Orbits.Body.values())
	if via != null:
		party.write(sim.day, "Life-support fault on %s; leaving via %s" % [cycler.name, Fleet.target_name(via)], CAUSE)
	sim.replan(party, party.destination, sim.day, CAUSE, via)


static func _stay_aboard(sim: Sim, party: Party, cycler: Cycler, groups: Array[Array]) -> void:
	var flyby_planet: Orbits.Body = cycler.leg_at(groups[0][0].depart_day).from
	party.state = Party.State.HELD
	party.write(sim.day, "Tenders full at %s; staying aboard %s" % [Fleet.target_name(flyby_planet), cycler.name], CAUSE)
	if groups.size() > 1:
		party.exit_retry_at = cycler.leg_at(groups[1][0].depart_day).start_day
	else:
		party.exit_retry_at = groups[0].back().depart_day
