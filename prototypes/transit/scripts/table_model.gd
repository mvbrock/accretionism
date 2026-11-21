class_name TableModel
extends RefCounted
## Fleet -> table rows of [ship, origin, progress, destination].

const NOT_APPLICABLE := "-"


## Cyclers first, then transports, each in fleet order.
static func rows(fleet: Fleet) -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	for cycler in fleet.cyclers:
		result.append(PackedStringArray([
			cycler.name,
			Orbits.body_name(cycler.last_flyby(fleet.day)),
			_percent(cycler.progress(fleet.day)),
			NOT_APPLICABLE,
		]))
	for transport in fleet.transports:
		result.append(_transport_row(fleet, transport))
	return result


static func _transport_row(fleet: Fleet, transport: Transport) -> PackedStringArray:
	match transport.state:
		Transport.State.AT_BODY:
			return PackedStringArray([transport.name, Orbits.body_name(transport.body), NOT_APPLICABLE, NOT_APPLICABLE])
		Transport.State.DOCKED:
			return PackedStringArray([transport.name, transport.host.name, NOT_APPLICABLE, NOT_APPLICABLE])
		_:
			return PackedStringArray([
				transport.name,
				transport.origin_name,
				_percent(fleet.progress(transport)),
				Fleet.target_name(transport.target),
			])


## Rounded down, so 100% shows only on arrival.
static func _percent(fraction: float) -> String:
	return "%d%%" % floori(fraction * 100.0)
