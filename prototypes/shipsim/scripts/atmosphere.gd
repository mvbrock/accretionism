class_name Atmosphere
extends RefCounted
## Gas flow between rooms, venting through the hatch, and heat. Stateless.


static func flow_through_door(a: Room, b: Room, door: Opening, dt: float) -> void:
	if not door.passes():
		return
	var mix_a_to_b := {}
	var mix_b_to_a := {}
	for gas in Units.GASES:
		mix_a_to_b[gas] = a.mol[gas] * door.mixing * door.fraction * dt / a.volume
		mix_b_to_a[gas] = b.mol[gas] * door.mixing * door.fraction * dt / b.volume
	_bulk_flow(a, b, door, dt)
	for gas in Units.GASES:
		a.mol[gas] += mix_b_to_a[gas] - mix_a_to_b[gas]
		b.mol[gas] += mix_a_to_b[gas] - mix_b_to_a[gas]
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


static func _bulk_flow(a: Room, b: Room, door: Opening, dt: float) -> void:
	var delta := a.pressure() - b.pressure()
	var source := a if delta > 0.0 else b
	var sink := b if delta > 0.0 else a
	var per_pa := 1.0 / (Units.R * source.temperature)
	var moles := door.conductance * door.fraction * absf(delta) * per_pa * dt
	var equalizing := absf(delta) * per_pa / (1.0 / a.volume + 1.0 / b.volume)
	moles = minf(moles, equalizing)
	var total := source.total_mol()
	if total == 0.0:
		return
	var moved := {}
	for gas in Units.GASES:
		moved[gas] = moles * source.mol[gas] / total
	for gas in Units.GASES:
		source.mol[gas] -= moved[gas]
		sink.mol[gas] += moved[gas]
