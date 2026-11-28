extends TestCase

const DAYS := 365
const NON_ROUTINE_CAUSES := ["change of mind", "medical emergency", "ship malfunction", "rescue"]


## A party's members all carry the same entries for what happens to it, so the first member stands for the party.
func test_rates_handful_per_day() -> void:
	var sim := Sim.new()
	sim.advance_to(float(DAYS))
	var entries := 0
	for party in sim.parties:
		for entry in party.members[0].history:
			if entry.day >= 0.0 and NON_ROUTINE_CAUSES.has(entry.cause):
				entries += 1
	var per_day := float(entries) / DAYS
	assert_true(per_day >= 0.3 and per_day <= 3.0, "%.2f non-routine entries a day is not a handful" % per_day)
