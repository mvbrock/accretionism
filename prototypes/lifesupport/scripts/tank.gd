class_name Tank
extends RefCounted
## A pressurised store of one gas. It can be drawn down to empty and filled up to capacity.

var gas: String
var capacity: float  # mol
var mol: float


func _init(tank_gas: String, tank_capacity: float, tank_mol: float) -> void:
	gas = tank_gas
	capacity = tank_capacity
	mol = tank_mol


## Takes up to `want` mol out and returns what it actually gave.
func draw(want: float) -> float:
	var given := clampf(want, 0.0, mol)
	mol -= given
	return given


## Puts up to `amount` mol in and returns what it accepted, never past capacity.
func fill(amount: float) -> float:
	var accepted := clampf(amount, 0.0, maxf(0.0, capacity - mol))
	mol += accepted
	return accepted


func fraction() -> float:
	return 0.0 if capacity == 0.0 else mol / capacity
