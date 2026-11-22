class_name EventLog
extends RefCounted
## The most recent ship events, oldest first.

const CAPACITY := 50

enum Level { INFO, WARNING, DANGER }

var entries: Array[Dictionary] = []


func add(time_s: float, text: String, level := Level.INFO) -> void:
	entries.append({"time_s": time_s, "text": text, "level": level})
	if entries.size() > CAPACITY:
		entries.pop_front()


func has_text(substring: String) -> bool:
	for entry in entries:
		if entry.text.contains(substring):
			return true
	return false
