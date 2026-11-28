extends TestCase


func _count_of(fleet: Fleet, service: Fleet.Service) -> int:
	return fleet.transports.filter(func(t: Transport) -> bool: return fleet.service_of[t] == service).size()


func test_world_counts() -> void:
	var fleet := World.build()
	assert_true(fleet.cyclers.size() == 6, "six cyclers")
	assert_true(fleet.transports.size() == 30, "thirty transports")
	var split := {Fleet.Service.SHUTTLE: 8, Fleet.Service.TENDER: 10, Fleet.Service.EXPRESS: 4, Fleet.Service.STANDBY: 6, Fleet.Service.SPARE: 2}
	for service in split:
		assert_true(_count_of(fleet, service) == split[service], "%d %s" % [split[service], Fleet.Service.find_key(service)])
	assert_near(fleet.day, Config.WARMUP_START, 1e-9, "starts at the warm-up day")


func test_standby_docked_to_its_cycler() -> void:
	var fleet := World.build()
	var hosts := {}
	for t in fleet.transports:
		if fleet.service_of[t] == Fleet.Service.STANDBY:
			assert_true(t.state == Transport.State.DOCKED, "%s starts docked" % t.name)
			hosts[t.host] = true
	assert_true(hosts.size() == 6, "one standby per cycler")


func test_other_services_start_parked_at_their_home() -> void:
	var fleet := World.build()
	var homes := {}
	for t in fleet.transports:
		if fleet.service_of[t] == Fleet.Service.STANDBY:
			continue
		assert_true(t.state == Transport.State.AT_BODY, "%s starts parked" % t.name)
		var key := "%s %s" % [Fleet.Service.find_key(fleet.service_of[t]), Orbits.body_name(t.body)]
		homes[key] = homes.get(key, 0) + 1
	var expected := {"SHUTTLE Earth": 4, "SHUTTLE Moon": 4, "TENDER Earth": 5, "TENDER Mars": 5,
		"EXPRESS Earth": 2, "EXPRESS Mars": 2, "SPARE Earth": 1, "SPARE Mars": 1}
	assert_true(homes == expected, "homes %s" % homes)


func test_world_applies_the_configured_timetable() -> void:
	World.build()
	assert_near(Cycler.cycle_days, Config.CYCLE_DAYS, 1e-9, "cycle length")
	assert_near(Cycler.short_leg_days, Config.SHORT_LEG_DAYS, 1e-9, "short leg")
