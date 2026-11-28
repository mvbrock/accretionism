class_name Passenger
extends RefCounted
## One person in the cast. Journey state lives on the party; a passenger keeps
## their own attributes, conditions, relationships and history.

enum Reason { WORK, EMIGRATION, VISIT, MEDICAL, RETURNING }
enum Kind { SPOUSE, PARENT, CHILD, SIBLING, FRIEND, COLLEAGUE }

var id: String
var full_name: String
var age: int
var birthplace: String
var occupation: String
var note: String
var reason: Reason
var party_id: int
## Each is {name, chance}, the chance being the daily chance of an emergency.
var conditions: Array[Dictionary] = []
## Each is {other, kind}: `other` is a passenger id, `kind` is what this
## passenger is to them.
var relationships: Array[Dictionary] = []
var history: Array[Dictionary] = []


func add_history(day: float, text: String, cause: String) -> void:
	history.append({"day": day, "text": text, "cause": cause})
