class_name Exposure
extends RefCounted
## Which rooms are open to space.


## Room id -> true when a chain of openings that pass leads from it to outside.
static func exposed(room_ids: Array[String], openings: Array[Opening]) -> Dictionary:
	var reached := {Opening.OUTSIDE: true}
	var frontier: Array[String] = [Opening.OUTSIDE]
	while not frontier.is_empty():
		var here: String = frontier.pop_front()
		for opening in openings:
			if not opening.passes():
				continue
			var other := ""
			if opening.room_a == here:
				other = opening.room_b
			elif opening.room_b == here:
				other = opening.room_a
			if other != "" and not reached.has(other):
				reached[other] = true
				frontier.append(other)
	var result := {}
	for room_id in room_ids:
		result[room_id] = reached.has(room_id)
	return result
