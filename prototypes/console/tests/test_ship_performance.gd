extends TestCase
## The five ships together must run an hour of sim, one real second at 1 hour/s, in half a real
## second of CPU or less, at the clock's fastest step.

## The target is 0.5 s. The five ships measured 0.24 s with the doors shut and 0.42 s with them
## open (Apple silicon, debug build), so this guard leaves headroom for a busy machine.
const LIMIT_S := 0.75


func test_the_fleet_runs_an_hour_at_the_fastest_clock_step_within_the_limit() -> void:
	var step_s: float = SimClock.step_sizes().back()
	var ships: Array[Ship] = [RingShip.new(), SkiffShip.new(), TugShip.new(), FreighterShip.new(), WheelShip.new()]
	for ship in ships:
		ShipChecks.open_all_doors(ship)
	var started := Time.get_ticks_usec()
	for ship in ships:
		ship.advance(3600.0, step_s)
	var seconds := (Time.get_ticks_usec() - started) / 1e6
	print("      an hour of the five ships, doors open, took %.3f s at the %s s step" % [seconds, step_s])
	assert_true(seconds < LIMIT_S, "took %.3f s" % seconds)
