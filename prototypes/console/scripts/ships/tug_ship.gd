class_name TugShip
extends DeckShip
## A deck ship with two decks.


func _init(overrides := {}) -> void:
	super._init(2, overrides)
