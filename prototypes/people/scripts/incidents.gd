class_name Incidents
extends RefCounted
## The daily rolls for a change of mind and for medical emergencies, and what an
## emergency does to its party. The hospital stay itself runs in Sim.

enum Severity { SERIOUS, CRITICAL }

const _CAUSE := "medical emergency"
const _HOSPITAL_BODIES: Array[Orbits.Body] = [Orbits.Body.EARTH, Orbits.Body.MOON, Orbits.Body.MARS]


static func install(sim: Sim) -> void:
	sim.on_daily.append(_roll_change_of_mind)
	sim.on_daily.append(_roll_emergencies)


## A condition's name inside a sentence: "Heart condition" becomes "heart condition", "COPD" stays.
static func in_sentence(condition: String) -> String:
	if condition == condition.to_upper():
		return condition
	return condition.substr(0, 1).to_lower() + condition.substr(1)


## Gives the party a new destination, picked from the other bodies, and plans it.
static func change_mind(sim: Sim, party: Party) -> void:
	var options: Array = Orbits.Body.values().filter(func(body: Orbits.Body) -> bool:
		return body != party.destination and not (_is_at_body(party) and is_same(body, party.place)))
	var to: Orbits.Body = options[sim.rng.randi_range(0, options.size() - 1)]
	party.write(sim.day, "Changed plans: heading to %s instead" % Fleet.target_name(to), "change of mind")
	sim.replan(party, to, sim.day, "change of mind")


static func roll_severity(rng: RandomNumberGenerator, patient: Passenger) -> Severity:
	var critical_chance := Config.CRITICAL_BASE + _years_at_risk(patient) * Config.CRITICAL_PER_YEAR
	return Severity.CRITICAL if rng.randf() < critical_chance else Severity.SERIOUS


## Starts an emergency for `patient`, who has `condition`, and acts on the whole party.
static func start_emergency(sim: Sim, party: Party, patient: Passenger, condition: String, severity: Severity) -> void:
	party.medical_return = party.destination
	party.patient = patient
	party.patient_condition = condition
	if severity == Severity.CRITICAL and not _is_at_body(party):
		_stabilize(sim, party)
	else:
		send_to_hospital(sim, party)


## Re-routes the party to the hospital that is soonest reached. A party at a body
## is already at a hospital, so its stay starts at once.
static func send_to_hospital(sim: Sim, party: Party) -> void:
	var hospital: Orbits.Body = party.place if _is_at_body(party) else _nearest_hospital(sim, party)
	var body := Fleet.target_name(hospital)
	for member in party.members:
		if member == party.patient:
			member.add_history(sim.day, "%s emergency; re-routed to %s for treatment" % [party.patient_condition, body], _CAUSE)
		else:
			member.add_history(sim.day, "Re-routed to %s: %s's %s emergency" % [
				body, party.patient.full_name, in_sentence(party.patient_condition)], _CAUSE)
	if _is_at_body(party):
		sim.begin_hospital_stay(party)
	else:
		# TASK 8: a party on a cycler (aboard == null and place is a Cycler) is rescued, so call
		# Rescues.request here for it. Until then it plans normally and leaves by the next tender.
		sim.replan(party, hospital, sim.day, _CAUSE)


static func _roll_change_of_mind(sim: Sim, _day: int) -> void:
	for party in sim.parties:
		if _rolls_events(sim, party) and sim.rng.randf() < _change_of_mind_chance(party):
			change_mind(sim, party)


static func _roll_emergencies(sim: Sim, _day: int) -> void:
	for party in sim.parties:
		if _rolls_events(sim, party):
			_roll_party_emergency(sim, party)


## Rolls each member's conditions in order. The first to strike starts the emergency, and the rest are not rolled.
static func _roll_party_emergency(sim: Sim, party: Party) -> void:
	for member in party.members:
		for condition in member.conditions:
			var chance: float = condition.chance * (1.0 + _years_at_risk(member) * Config.AGE_RISK_PER_YEAR)
			if sim.rng.randf() < chance:
				start_emergency(sim, party, member, condition.name, roll_severity(sim.rng, member))
				return


## Whether the party can have a change of mind or an emergency today: it has set
## off, is not arrived and is not already on a medical route.
static func _rolls_events(sim: Sim, party: Party) -> bool:
	return party.state != Party.State.ARRIVED and party.journey_start <= sim.day and not party.is_on_medical_route(sim.day)


static func _change_of_mind_chance(party: Party) -> float:
	var chance := 0.0
	for member in party.members:
		chance = maxf(chance, Config.CHANGE_OF_MIND[Passenger.Reason.keys()[member.reason]])
	return chance


static func _years_at_risk(passenger: Passenger) -> int:
	return maxi(0, passenger.age - Config.AGE_RISK_START_YEAR)


## The party can't be moved: it stays where it is until the stable period ends.
static func _stabilize(sim: Sim, party: Party) -> void:
	Planner.cancel(party)
	party.state = Party.State.HELD
	party.stable_until = sim.day + sim.rng.randi_range(Config.STABLE_DAYS[0], Config.STABLE_DAYS[1])
	var where := "aboard %s" % party.aboard.ship.name if party.aboard != null else "in the infirmary"
	for member in party.members:
		if member == party.patient:
			member.add_history(sim.day, "%s emergency; stabilized %s" % [party.patient_condition, where], _CAUSE)
		else:
			member.add_history(sim.day, "%s's %s emergency; stabilized %s" % [
				party.patient.full_name, in_sentence(party.patient_condition), where], _CAUSE)


## The body of Earth, the Moon and Mars the party reaches soonest. With no route
## to any of them it picks the first, so the party waits for a route to open.
static func _nearest_hospital(sim: Sim, party: Party) -> Orbits.Body:
	var nearest: Variant = Planner.soonest_body(sim.schedule, party.place, sim.day, party.size(), party.aboard, _HOSPITAL_BODIES)
	return _HOSPITAL_BODIES[0] if nearest == null else nearest


static func _is_at_body(party: Party) -> bool:
	return party.aboard == null and not party.place is Cycler
