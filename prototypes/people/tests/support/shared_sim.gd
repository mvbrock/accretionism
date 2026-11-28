class_name SharedSim
extends RefCounted
## One warmed-up sim for the UI tests, since building one takes seconds. Tests
## that advance it only move it forward.

static var _sim: Sim


static func get_sim() -> Sim:
	if _sim == null:
		_sim = Sim.new()
	# Orbit tests reconfigure static settings; the sim must run on its own.
	World.apply_settings()
	return _sim
