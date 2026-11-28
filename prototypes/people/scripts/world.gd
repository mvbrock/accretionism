class_name World
extends RefCounted
## Builds the fleet from Config, with every ship at its home on the warm-up's
## first day.


static func build() -> Fleet:
	apply_settings()
	var fleet := Fleet.new()
	fleet.day = Config.WARMUP_START
	for entry in Config.CYCLERS:
		fleet.cyclers.append(Cycler.new(entry.name, Cycler.Direction[entry.direction], entry.phase_day))
	for entry in Config.TRANSPORTS:
		var transport := _transport_at(entry.name, entry.home, fleet.cyclers)
		fleet.transports.append(transport)
		fleet.service_of[transport] = entry.service
		fleet.home_of[transport] = transport.host if transport.state == Transport.State.DOCKED else transport.body
	return fleet


static func apply_settings() -> void:
	var angles := {}
	for body in Orbits.Body.values():
		angles[body] = Config.EPOCH_ANGLES_DEG[Orbits.body_name(body)]
	Orbits.configure(angles)
	Cycler.cycle_days = Config.CYCLE_DAYS
	Cycler.short_leg_days = Config.SHORT_LEG_DAYS


static func _transport_at(transport_name: String, home: String, cyclers: Array[Cycler]) -> Transport:
	for body in Orbits.Body.values():
		if Orbits.body_name(body) == home:
			return Transport.parked_at(transport_name, body)
	for cycler in cyclers:
		if cycler.name == home:
			return Transport.docked_to(transport_name, cycler)
	assert(false, "home '%s' matches no body or cycler" % home)
	return null
