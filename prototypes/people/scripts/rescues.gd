class_name Rescues
extends RefCounted
## Standby transports and rescues. A party on a cycler that cannot wait for the
## next flyby joins that cycler's queue. A transport docked there flies the queue
## to the body reached soonest, then flies back. With none docked, the nearest
## spare flies out to take its place. A rescue changes a transport's plans, never
## a cycler's course.

const MEDICAL := "medical"
const LIFE_SUPPORT := "life_support"
const RESCUE_CAUSE := "rescue"

const _STANDING_SERVICES := ["standby", "spare"]


static func install(sim: Sim) -> void:
	for cycler in sim.fleet.cyclers:
		sim.standby_gap[cycler] = 0.0
	sim.on_daily.append(_count_gaps)


static func request(sim: Sim, party: Party, reason: String) -> void:
	assert(party.aboard == null and party.place is Cycler, "only a party on a cycler is rescued")
	var cycler: Cycler = party.place
	var target := nearest_body(sim, cycler, Orbits.Body.values())
	Planner.cancel(party)
	party.exit_retry_at = -INF
	party.state = Party.State.HELD
	party.awaiting_rescue = true
	if reason == MEDICAL:
		party.destination = target
	var queue := _queue(sim, cycler)
	var queued := queue.filter(func(entry: Dictionary) -> bool: return entry.party == party)
	if queued.is_empty():
		queue.append({party = party, target = target, reason = reason})
	else:
		queued[0].target = target
		queued[0].reason = reason
	_mark_due(sim, cycler)


static func nearest_body(sim: Sim, cycler: Cycler, bodies: Array) -> Orbits.Body:
	var nearest: Orbits.Body = bodies[0]
	var earliest := INF
	for body in bodies:
		var solution := sim.fleet.solve_trip(cycler, sim.day, body)
		if solution.ok and solution.t_arrive < earliest:
			nearest = body
			earliest = solution.t_arrive
	return nearest


static func can_serve(sim: Sim, cycler: Cycler) -> bool:
	return _free_ship_at(sim, cycler) != null or _cover_on_its_way_to(sim, cycler) or _cover_ship_for(sim, cycler) != null


static func serve_due(sim: Sim) -> void:
	var due := sim.rescues_due.duplicate()
	sim.rescues_due.clear()
	for cycler in due:
		_serve(sim, cycler)


## A transport docking at a cycler may be the one its queue is waiting for, or
## the standby that sends a covering transport home.
static func on_arrival(sim: Sim, trip: Trip) -> void:
	if trip.to is Cycler:
		_mark_due(sim, trip.to)


static func _count_gaps(sim: Sim, _day: int) -> void:
	for cycler in sim.fleet.cyclers:
		if not _is_standing_by_at(sim, cycler):
			sim.standby_gap[cycler] += 1.0
		_mark_due(sim, cycler)


static func _queue(sim: Sim, cycler: Cycler) -> Array:
	if not sim.rescue_queues.has(cycler):
		sim.rescue_queues[cycler] = []
	return sim.rescue_queues[cycler]


static func _mark_due(sim: Sim, cycler: Cycler) -> void:
	if not sim.rescues_due.has(cycler):
		sim.rescues_due.append(cycler)


static func _serve(sim: Sim, cycler: Cycler) -> void:
	var queue := _queue(sim, cycler)
	var ship := _free_ship_at(sim, cycler)
	while not queue.is_empty() and ship != null:
		if not _fly_queue(sim, cycler, ship, queue):
			break
		ship = _free_ship_at(sim, cycler)
	_send_loans_home(sim, cycler)
	if ship == null and not _cover_on_its_way_to(sim, cycler):
		_send_cover(sim, cycler)


static func _fly_queue(sim: Sim, cycler: Cycler, ship: Transport, queue: Array) -> bool:
	var target: Orbits.Body = queue[0].target
	var seats: int = Config.SEATS[sim.fleet.service_of[ship]]
	var boarding: Array[Dictionary] = []
	var seats_taken := 0
	for entry in queue:
		if seats_taken + entry.party.size() <= seats:
			boarding.append(entry)
			seats_taken += entry.party.size()
	if boarding.is_empty():
		push_error("%s has too few seats for the party first in the %s queue" % [ship.name, cycler.name])
		return false
	var trip := sim.dispatcher.add_rescue(ship, cycler, target, sim.day)
	sim.dispatcher.add_return(ship, cycler, trip.arrive_day + Config.RESCUE_TURNAROUND_DAYS)
	for entry in boarding:
		queue.erase(entry)
		var party: Party = entry.party
		party.awaiting_rescue = false
		if entry.reason == MEDICAL:
			if not is_same(party.destination, target):
				party.write(sim.day, "Rescue heading to %s; re-routed there" % Fleet.target_name(target), RESCUE_CAUSE)
			party.destination = target
		party.state = Party.State.TRAVELLING
		Planner.book(party, [trip] as Array[Trip])
	return true


static func _send_cover(sim: Sim, cycler: Cycler) -> void:
	var ship := _cover_ship_for(sim, cycler)
	if ship != null:
		var from: Variant = ship.body if ship.state == Transport.State.AT_BODY else ship.host
		sim.dispatcher.add_rescue(ship, from, cycler, sim.day)


## The transport that covers the cycler: the spare at a body that arrives soonest,
## or else an idle one from a cycler that keeps another after it goes.
static func _cover_ship_for(sim: Sim, cycler: Cycler) -> Transport:
	var spare := _nearest_idle_spare(sim, cycler)
	if spare != null:
		return spare
	var lender: Transport = null
	var earliest := INF
	for other in sim.fleet.cyclers:
		var free := _free_ships_at(sim, other)
		if is_same(other, cycler) or free.size() < 2:
			continue
		var solution := sim.fleet.solve_trip(other, sim.day, cycler)
		if solution.ok and solution.t_arrive < earliest:
			lender = _most_borrowable(sim, free, other)
			earliest = solution.t_arrive
	return lender


## Prefers a loaned transport, so the cycler's own standby stays.
static func _most_borrowable(sim: Sim, free: Array[Transport], cycler: Cycler) -> Transport:
	for ship in free:
		if not is_same(sim.fleet.home_of[ship], cycler):
			return ship
	return free[0]


## A covering spare stays as a second standby rather than flying home: flights to and
## from a cycler far out on its leg can take 80 days each way, so a spare sent home is
## often still on its way when the next cover is needed. Docked here, it can be lent onward.
static func _send_loans_home(sim: Sim, cycler: Cycler) -> void:
	var free := _free_ships_at(sim, cycler)
	var own_is_back := free.any(func(ship: Transport) -> bool:
		return sim.fleet.service_of[ship] == "standby" and is_same(sim.fleet.home_of[ship], cycler))
	if not own_is_back:
		return
	for ship in free:
		if sim.fleet.service_of[ship] == "standby" and not is_same(sim.fleet.home_of[ship], cycler):
			sim.dispatcher.add_return(ship, sim.fleet.home_of[ship], sim.day)


static func _is_standing_by_at(sim: Sim, cycler: Cycler) -> bool:
	return sim.fleet.transports.any(func(ship: Transport) -> bool: return _is_standing_docked(sim, ship, cycler))


static func _is_standing_docked(sim: Sim, ship: Transport, cycler: Cycler) -> bool:
	return _STANDING_SERVICES.has(sim.fleet.service_of[ship]) and ship.state == Transport.State.DOCKED and is_same(ship.host, cycler)


static func _free_ship_at(sim: Sim, cycler: Cycler) -> Transport:
	var free := _free_ships_at(sim, cycler)
	return free[0] if not free.is_empty() else null


static func _free_ships_at(sim: Sim, cycler: Cycler) -> Array[Transport]:
	return sim.fleet.transports.filter(func(ship: Transport) -> bool:
		return _is_standing_docked(sim, ship, cycler) and not _has_trip_to_fly(sim, ship))


static func _nearest_idle_spare(sim: Sim, cycler: Cycler) -> Transport:
	var nearest: Transport = null
	var earliest := INF
	for ship in sim.fleet.transports:
		if sim.fleet.service_of[ship] != "spare" or ship.state != Transport.State.AT_BODY or _has_trip_to_fly(sim, ship):
			continue
		var solution := sim.fleet.solve_trip(ship.body, sim.day, cycler)
		if solution.ok and solution.t_arrive < earliest:
			nearest = ship
			earliest = solution.t_arrive
	return nearest


static func _cover_on_its_way_to(sim: Sim, cycler: Cycler) -> bool:
	return sim.schedule.arriving_from(sim.day).any(func(trip: Trip) -> bool:
		var is_cover := trip.kind == "rescue" and trip.booked == 0 and _STANDING_SERVICES.has(sim.fleet.service_of[trip.ship])
		return is_cover and is_same(trip.to, cycler))


## A trip departing at this very instant still counts as yet to leave.
static func _has_trip_to_fly(sim: Sim, ship: Transport) -> bool:
	return sim.schedule.has_departure_of(ship, sim.day)
