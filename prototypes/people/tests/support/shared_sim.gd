class_name SharedSim
extends RefCounted
## One warmed-up sim for the UI tests, since building one takes seconds. Tests
## that advance it only move it forward.

static var _sim: Sim


static func get_sim() -> Sim:
	if _sim == null:
		_sim = Sim.new()
	return _sim
