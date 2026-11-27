class_name FreighterShip
extends DeckShip
## A deck ship with four decks.


func _init(overrides := {}) -> void:
	super._init(4, overrides)
