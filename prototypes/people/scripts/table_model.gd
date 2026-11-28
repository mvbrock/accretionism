class_name TableModel
extends RefCounted
## Passengers -> table rows of [name, id, origin, location, destination, progress].

const NOT_APPLICABLE := "-"
const ARRIVED := "Arrived"
const PROGRESS_COLUMN := 5


static func row(sim: Sim, passenger: Passenger) -> PackedStringArray:
	var party := sim.parties[passenger.party_id]
	var destination := ARRIVED if party.state == Party.State.ARRIVED else Fleet.target_name(party.destination)
	var fraction := sim.progress(party)
	return PackedStringArray([
		passenger.full_name,
		passenger.id,
		Fleet.target_name(party.origin),
		sim.location_name(passenger),
		destination,
		NOT_APPLICABLE if fraction < 0.0 else percent(fraction),
	])


## Progress as a number and every other column as its text.
static func sort_key(sim: Sim, passenger: Passenger, column: int) -> Variant:
	if column == PROGRESS_COLUMN:
		return sim.progress(sim.parties[passenger.party_id])
	return row(sim, passenger)[column]


## To two decimals, rounded down, so 100.00% shows only on arrival.
static func percent(fraction: float) -> String:
	return "%.2f%%" % (floorf(fraction * 10000.0) / 100.0)
