class_name Room
extends RefCounted
## One sealed room's gas, temperature and passengers. Gas is held as moles per gas.

var id: String
var volume: float  # m3
var temperature: float  # K
var passengers: int
var mol: Dictionary = {}  # gas -> mol, every gas in Units.GASES present
var heat_capacity := 0.0  # J/K, set by the loader
var hull_conductance := 0.0  # W/K, set by the loader


func _init(room_id: String, room_volume: float, room_temperature: float, room_passengers: int) -> void:
	id = room_id
	volume = room_volume
	temperature = room_temperature
	passengers = room_passengers
	for gas in Units.GASES:
		mol[gas] = 0.0


static func mol_for(pa: float, volume: float, temperature: float) -> float:
	return pa * volume / (Units.R * temperature)


func partial_pressure(gas: String) -> float:
	return mol[gas] * Units.R * temperature / volume


func pressure() -> float:
	return total_mol() * Units.R * temperature / volume


func share(gas: String) -> float:
	var total := total_mol()
	return 0.0 if total == 0.0 else mol[gas] / total


func total_mol() -> float:
	var total := 0.0
	for gas in Units.GASES:
		total += mol[gas]
	return total


func set_partial_pressure(gas: String, pa: float) -> void:
	mol[gas] = mol_for(pa, volume, temperature)
