extends TestCase

func test_power_loss_and_boot() -> void:
	var unit := SystemUnit.new("hvac", 1.0)
	assert_true(unit.state == SystemUnit.State.RUNNING, "starts running")
	assert_true(not unit.step(0.1, true), "no change while powered")
	assert_true(unit.step(0.1, false), "power loss changes state")
	assert_true(unit.state == SystemUnit.State.NO_POWER, "no power")
	assert_true(unit.step(0.1, true), "power back changes state")
	assert_true(unit.state == SystemUnit.State.BOOTING, "booting")
	assert_near(unit.boot_left_s, 1.0, 1e-9, "full boot time")
	var changed := false
	for i in 10:
		changed = unit.step(0.1, true)
	assert_true(changed, "final step changes state")
	assert_true(unit.state == SystemUnit.State.RUNNING, "running after boot_s")
	assert_true(unit.is_running(), "is_running")

func test_restart_clears_fault() -> void:
	var unit := SystemUnit.new("hvac", 1.0)
	assert_true(unit.fault(), "fault accepted")
	assert_true(unit.state == SystemUnit.State.FAULT, "in fault")
	assert_true(not unit.fault(), "second fault refused")
	assert_true(not unit.step(0.1, true), "fault persists while powered")
	assert_true(unit.state == SystemUnit.State.FAULT, "still fault")
	assert_true(unit.restart(true) == SystemUnit.RestartResult.REBOOTING, "rebooting")
	assert_true(unit.state == SystemUnit.State.BOOTING, "booting")
	unit.step(0.5, true)
	unit.restart(true)
	assert_near(unit.boot_left_s, 1.0, 1e-9, "restart while booting resets countdown")

func test_restart_without_power() -> void:
	var unit := SystemUnit.new("hvac", 1.0)
	assert_true(unit.restart(false) == SystemUnit.RestartResult.NO_POWER, "no power result")
	assert_true(unit.state == SystemUnit.State.RUNNING, "state unchanged")

func test_fault_without_power_refused() -> void:
	var unit := SystemUnit.new("hvac", 1.0)
	unit.step(0.1, false)
	assert_true(not unit.fault(), "fault refused without power")
	assert_true(unit.state == SystemUnit.State.NO_POWER, "still no power")
