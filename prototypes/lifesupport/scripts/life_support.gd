class_name LifeSupport
extends RefCounted
## What crew, pressure control, HVAC and the CO2 recycler do to one room in one step.


## The crew breathe: O2 in, CO2 out, both scaled by crew. With too little O2 they use what
## there is and make CO2 in the same proportion.
static func breathe(room: Room, o2_mol_s: float, co2_mol_s: float, dt: float) -> void:
	var o2_wanted := o2_mol_s * room.crew * dt
	if o2_wanted <= 0.0:
		return
	# CO2 is tied to the O2 actually used, so a starved crew makes proportionally less.
	var ratio := minf(1.0, room.mol["O2"] / o2_wanted)
	room.mol["O2"] -= o2_wanted * ratio
	room.mol["CO2"] += co2_mol_s * room.crew * dt * ratio


## Tops O2 and N2 up toward their setpoints from the tanks, each limited to `max_mol_s`.
## An exposed room is left alone.
static func pressure_control(room: Room, exposed: bool, tanks: Dictionary, setpoints_pa: Dictionary,
		max_mol_s: float, dt: float) -> void:
	if exposed:
		return
	for gas in ["O2", "N2"]:
		var missing: float = Room.mol_for(setpoints_pa[gas], room.volume, room.temperature) - room.mol[gas]
		var wanted := minf(missing, max_mol_s * dt)
		if wanted > 0.0:
			room.mol[gas] += tanks[gas].draw(wanted)


## Heating power in W (negative cools), proportional to the gap from the setpoint.
static func hvac_heat_w(room: Room, setpoint_k: float, gain_w_per_k: float, max_w: float) -> float:
	return clampf(gain_w_per_k * (setpoint_k - room.temperature), -max_w, max_w)


## Scrubs CO2 above `max_co2_pa` and returns the same moles as O2 to the tank. It skips an
## exposed room and one below `min_pressure_pa`. Returns the moles of CO2 removed.
static func recycle(room: Room, exposed: bool, o2_tank: Tank, max_co2_pa: float, min_pressure_pa: float,
		max_mol_s: float, dt: float) -> float:
	if exposed or room.pressure() < min_pressure_pa:
		return 0.0
	var excess: float = room.mol["CO2"] - Room.mol_for(max_co2_pa, room.volume, room.temperature)
	var removed := clampf(minf(excess, max_mol_s * dt), 0.0, room.mol["CO2"])
	room.mol["CO2"] -= removed
	o2_tank.fill(removed)
	return removed
