class_name DeckShip
extends Ship
## Square decks stacked under thrust, joined by a ladder pipe in one corner, one pipe segment per
## deck. Deck k is `deckK` and its segment `pipeK`, numbered from the bottom. A doorway at floor
## level joins each deck to its segment, and the segments join ceiling to floor. The hatch is in the
## bottom deck's floor. One crew member on each deck.

const DECK_SIZE_M := Vector3(12.0, 4.0, 12.0)
## Floor to floor: the deck's height plus a 0.4 m slab.
const PITCH_M := 4.4
## The pipe's interior is 1.4 m square; it stands just past the deck's +z wall.
const PIPE_SIZE_M := Vector3(1.4, 4.4, 1.4)
const PIPE_X := 3.5
const PIPE_Z := 6.7
const PIPE_DOORWAY_M := Vector2(1.4, 2.6)
const PIPE_JOINT_M := Vector2(1.4, 1.4)

var deck_count := 2


## `count` decks; `overrides` are the params to change, as for `Ship`.
func _init(count: int, overrides := {}) -> void:
	deck_count = count
	super._init(overrides)


func _build() -> void:
	for k in range(1, deck_count + 1):
		var floor_y := PITCH_M * (k - 1)
		add_room("deck%d" % k, DECK_SIZE_M, Vector3(0, floor_y + DECK_SIZE_M.y / 2.0, 0), Basis.IDENTITY, 1)
	for k in range(1, deck_count + 1):
		var floor_y := PITCH_M * (k - 1)
		add_room("pipe%d" % k, PIPE_SIZE_M, Vector3(PIPE_X, floor_y + PIPE_SIZE_M.y / 2.0, PIPE_Z))
	for k in range(1, deck_count + 1):
		var floor_y := PITCH_M * (k - 1)
		add_door("deck%d-pipe%d" % [k, k], "deck%d" % k, Room.Face.PLUS_Z, "pipe%d" % k, Room.Face.MINUS_Z,
				PIPE_DOORWAY_M, Vector3(PIPE_X, floor_y + PIPE_DOORWAY_M.y / 2.0, PIPE_Z - PIPE_SIZE_M.z / 2.0))
	for k in range(1, deck_count):
		add_door("pipe%d-pipe%d" % [k, k + 1], "pipe%d" % k, Room.Face.PLUS_Y, "pipe%d" % (k + 1), Room.Face.MINUS_Y,
				PIPE_JOINT_M, Vector3(PIPE_X, PITCH_M * k, PIPE_Z))
	add_hatch("hatch", "deck1", Room.Face.MINUS_Y)
