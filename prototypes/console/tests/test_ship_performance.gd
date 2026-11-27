extends TestCase
## The five ships together must run an hour of sim, one real second at 1 hour/s, in well under a
## real second of CPU (the target is 0.5 s).

## Not the target: a regression guard, generous so a busy machine does not fail the suite. The
## five ships measured 1.2 s here (Apple silicon, debug build) after the first optimisation pass.
const LIMIT_S := 2.0


func test_the_fleet_runs_an_hour_at_the_1_s_step_in_under_two_seconds() -> void:
	var ships: Array[Ship] = [RingShip.new(), SkiffShip.new(), TugShip.new(), FreighterShip.new(), WheelShip.new()]
	var started := Time.get_ticks_usec()
	for ship in ships:
		ship.advance(3600.0, 1.0)
	var seconds := (Time.get_ticks_usec() - started) / 1e6
	print("      an hour of the five ships took %.3f s" % seconds)
	assert_true(seconds < LIMIT_S, "took %.3f s" % seconds)
