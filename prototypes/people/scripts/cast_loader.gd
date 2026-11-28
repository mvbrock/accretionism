class_name CastLoader
extends RefCounted

const INVERSE_KIND := {
	"SPOUSE": "SPOUSE", "PARENT": "CHILD", "CHILD": "PARENT",
	"SIBLING": "SIBLING", "FRIEND": "FRIEND", "COLLEAGUE": "COLLEAGUE",
}


static func load() -> Array[Party]:
	var passengers := _passengers()
	_link_relationships(passengers)
	var parties: Array[Party] = []
	for index in Cast.PARTIES.size():
		parties.append(_party(index, Cast.PARTIES[index], passengers))
	return parties


static func _passengers() -> Dictionary[String, Passenger]:
	var passengers: Dictionary[String, Passenger] = {}
	for entry in Cast.PASSENGERS:
		var passenger := Passenger.new()
		passenger.id = entry.id
		passenger.full_name = entry.name
		passenger.age = entry.age
		passenger.birthplace = entry.birthplace
		passenger.occupation = entry.occupation
		passenger.note = entry.note
		passenger.reason = Passenger.Reason[entry.reason]
		passenger.conditions.assign(entry.conditions)
		passengers[passenger.id] = passenger
	return passengers


static func _link_relationships(passengers: Dictionary[String, Passenger]) -> void:
	for entry in Cast.RELATIONSHIPS:
		passengers[entry.a].relationships.append({"other": entry.b, "kind": Passenger.Kind[entry.kind]})
		passengers[entry.b].relationships.append({"other": entry.a, "kind": Passenger.Kind[INVERSE_KIND[entry.kind]]})


static func _party(index: int, entry: Dictionary, passengers: Dictionary[String, Passenger]) -> Party:
	var party := Party.new()
	party.id = index
	party.origin = _body(entry.start_body)
	party.destination = _body(entry.destination)
	party.journey_start = entry.start_day
	party.place = party.origin
	for member_id in entry.members:
		var member := passengers[member_id]
		member.party_id = party.id
		party.members.append(member)
	return party


static func _body(body_name: String) -> Orbits.Body:
	for body in Orbits.Body.values():
		if Orbits.body_name(body) == body_name:
			return body
	push_error("Unknown body: %s" % body_name)
	return Orbits.Body.EARTH
