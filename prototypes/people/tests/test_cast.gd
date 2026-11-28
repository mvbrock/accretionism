extends TestCase


func _loaded_parties() -> Array[Party]:
	return CastLoader.load()


func _passenger_by_id(parties: Array[Party], id: String) -> Passenger:
	for party in parties:
		for member in party.members:
			if member.id == id:
				return member
	return null


func test_three_hundred_unique_ids() -> void:
	assert_true(Cast.PASSENGERS.size() == 300, "300 passengers")
	var ids := {}
	for entry in Cast.PASSENGERS:
		ids[entry.id] = true
	assert_true(ids.size() == 300, "ids are unique")
	assert_true(ids.has("P-00001") and ids.has("P-00300"), "ids run P-00001 to P-00300")


func test_cast_fits_a_cycler() -> void:
	assert_true(Cast.PASSENGERS.size() <= Config.SEATS.cycler, "the whole cast fits aboard one cycler")


func test_every_passenger_is_in_exactly_one_party() -> void:
	var seen := {}
	for entry in Cast.PARTIES:
		assert_true(entry.members.size() >= 1 and entry.members.size() <= 5, "party of 1 to 5")
		for member_id in entry.members:
			assert_true(not seen.has(member_id), "%s is in one party" % member_id)
			seen[member_id] = true
	assert_true(seen.size() == 300, "every passenger travels in a party")


func test_every_relationship_names_a_real_passenger() -> void:
	var ids := {}
	for entry in Cast.PASSENGERS:
		ids[entry.id] = true
	for entry in Cast.RELATIONSHIPS:
		assert_true(ids.has(entry.a) and ids.has(entry.b), "%s -> %s names real passengers" % [entry.a, entry.b])
		assert_true(entry.a != entry.b, "%s is not related to themselves" % entry.a)
		assert_true(Passenger.Kind.has(entry.kind), "%s is a known kind" % entry.kind)


func test_colleagues_are_both_working() -> void:
	var reason_of := {}
	for entry in Cast.PASSENGERS:
		reason_of[entry.id] = entry.reason
	for entry in Cast.RELATIONSHIPS:
		if entry.kind == "COLLEAGUE":
			assert_true(reason_of[entry.a] == "WORK" and reason_of[entry.b] == "WORK", "colleagues %s, %s both work" % [entry.a, entry.b])


func test_children_travel_with_a_parent() -> void:
	for party in _loaded_parties():
		for member in party.members:
			if member.age >= 16:
				continue
			var has_parent_aboard := party.members.any(func(other: Passenger) -> bool:
				return member.relationships.any(func(relationship: Dictionary) -> bool:
					return relationship.other == other.id and relationship.kind == Passenger.Kind.PARENT))
			assert_true(has_parent_aboard, "%s is under 16 and travels with a parent" % member.id)


func test_party_members_share_a_family_name() -> void:
	for party in _loaded_parties():
		var family_names := {}
		for member in party.members:
			family_names[member.full_name.split(" ")[-1]] = true
		assert_true(family_names.size() == 1, "party %d shares a family name" % party.id)


func test_ages_and_conditions_are_in_range() -> void:
	var with_conditions := 0
	for entry in Cast.PASSENGERS:
		assert_true(entry.age >= 1 and entry.age <= 85, "%s age %d" % [entry.id, entry.age])
		for condition in entry.conditions:
			assert_true(condition.chance >= 0.001 and condition.chance <= 0.003, "%s chance" % condition.name)
		if not entry.conditions.is_empty():
			with_conditions += 1
	assert_true(with_conditions >= 60 and with_conditions <= 120, "about 30%% have a condition, got %d" % with_conditions)


func test_every_reason_is_used() -> void:
	var reasons := {}
	for entry in Cast.PASSENGERS:
		reasons[entry.reason] = true
	assert_true(reasons.size() == Passenger.Reason.size(), "all five reasons appear")


func test_start_days_in_warmup() -> void:
	for entry in Cast.PARTIES:
		assert_true(entry.start_day >= Config.WARMUP_START and entry.start_day <= 0, "start day %d in [-400, 0]" % entry.start_day)


func test_destination_differs_from_start() -> void:
	for party in _loaded_parties():
		assert_true(party.destination != party.origin, "party %d goes somewhere else" % party.id)


func test_parties_wait_at_their_start_body() -> void:
	var parties := _loaded_parties()
	assert_true(parties.size() == Cast.PARTIES.size(), "one party per entry")
	for party in parties:
		assert_true(party.id == parties.find(party), "id is the index")
		assert_true(party.place == party.origin, "waits at its origin")
		assert_true(party.state == Party.State.HELD and party.route.is_empty(), "held with no route")
		assert_true(party.aboard == null, "not aboard")
		for member in party.members:
			assert_true(member.party_id == party.id, "member records its party id")


func test_inverse_relationships_added() -> void:
	var parties := _loaded_parties()
	var inverse := {Passenger.Kind.SPOUSE: Passenger.Kind.SPOUSE, Passenger.Kind.PARENT: Passenger.Kind.CHILD,
		Passenger.Kind.CHILD: Passenger.Kind.PARENT, Passenger.Kind.SIBLING: Passenger.Kind.SIBLING,
		Passenger.Kind.FRIEND: Passenger.Kind.FRIEND, Passenger.Kind.COLLEAGUE: Passenger.Kind.COLLEAGUE}
	var total := 0
	for party in parties:
		for member in party.members:
			total += member.relationships.size()
			for relationship in member.relationships:
				var other := _passenger_by_id(parties, relationship.other)
				var back := other.relationships.filter(func(r: Dictionary) -> bool: return r.other == member.id)
				assert_true(back.size() == 1 and back[0].kind == inverse[relationship.kind], "%s has the inverse of %s" % [other.id, member.id])
	assert_true(total == 2 * Cast.RELATIONSHIPS.size(), "each relationship is listed on both sides")


func test_each_relationship_reads_from_the_passengers_side() -> void:
	var parties := _loaded_parties()
	var inverse := {"SPOUSE": "SPOUSE", "PARENT": "CHILD", "CHILD": "PARENT", "SIBLING": "SIBLING", "FRIEND": "FRIEND", "COLLEAGUE": "COLLEAGUE"}
	var seen := {}
	for entry in Cast.RELATIONSHIPS:
		seen[entry.kind] = true
		var a := _passenger_by_id(parties, entry.a)
		var b := _passenger_by_id(parties, entry.b)
		var b_sees: Array = b.relationships.filter(func(r: Dictionary) -> bool: return r.other == a.id)
		var a_sees: Array = a.relationships.filter(func(r: Dictionary) -> bool: return r.other == b.id)
		assert_true(b_sees.size() == 1 and b_sees[0].kind == Passenger.Kind[entry.kind], "%s sees %s as their %s" % [b.id, a.id, entry.kind])
		assert_true(a_sees.size() == 1 and a_sees[0].kind == Passenger.Kind[inverse[entry.kind]], "%s sees %s as their %s" % [a.id, b.id, inverse[entry.kind]])
	assert_true(seen.size() == 5, "the cast uses spouse, parent, sibling, friend and colleague")


func test_party_write_reaches_every_member() -> void:
	var party: Party = _loaded_parties().filter(func(p: Party) -> bool: return p.size() >= 3)[0]
	party.write(-12.0, "Set off for the Moon", "Journey start")
	for member in party.members:
		assert_true(member.history == [{"day": -12.0, "text": "Set off for the Moon", "cause": "Journey start"}], "%s history" % member.id)
