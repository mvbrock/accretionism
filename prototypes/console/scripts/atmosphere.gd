class_name Atmosphere
extends RefCounted
## Gas flow between rooms, venting through the hatch, and heat. Stateless.


static func flow_through_door(a: Room, b: Room, door: Opening, dt: float) -> void:
	if not door.passes():
		return
	# Mixing and bulk flow both work from the gas as it was before this door, one gas at a time.
	var delta := a.pressure() - b.pressure()
	var source := a if delta > 0.0 else b
	var sink := b if delta > 0.0 else a
	var per_pa := 1.0 / (Units.R * source.temperature)
	var moles := door.conductance * door.fraction * absf(delta) * per_pa * dt
	var equalizing := absf(delta) * per_pa / (1.0 / a.volume + 1.0 / b.volume)
	moles = minf(moles, equalizing)
	var total := source.total_mol()
	for gas in Units.GASES:
		var mix_a_to_b: float = a.mol[gas] * door.mixing * door.fraction * dt / a.volume
		var mix_b_to_a: float = b.mol[gas] * door.mixing * door.fraction * dt / b.volume
		if total != 0.0:
			var moved: float = moles * source.mol[gas] / total
			source.mol[gas] -= moved
			sink.mol[gas] += moved
		a.mol[gas] += mix_b_to_a - mix_a_to_b
		b.mol[gas] += mix_a_to_b - mix_b_to_a
	var heat := door.heat_conductance * door.fraction * (a.temperature - b.temperature) * dt
	a.temperature -= heat / a.heat_capacity
	b.temperature += heat / b.heat_capacity


static func vent_through_hatch(room: Room, hatch: Opening, dt: float) -> float:
	var before := room.total_mol()
	var keep := exp(-hatch.conductance * hatch.fraction * dt / room.volume)
	for gas in Units.GASES:
		room.mol[gas] *= keep
	return before - room.total_mol()


static func add_heat(room: Room, joules: float) -> void:
	room.temperature += joules / room.heat_capacity


static func hull_loss(room: Room, hull_temperature: float, dt: float) -> void:
	add_heat(room, -room.hull_conductance * (room.temperature - hull_temperature) * dt)
