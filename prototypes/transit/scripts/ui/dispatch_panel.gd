class_name DispatchPanel
extends VBoxContainer
## Side panel: the selected ship's icon and name and, for a transport waiting
## at a body or cycler, its valid targets (each cycler with its icon), the
## travel-time estimate and the Depart button.

signal depart_requested(transport: Transport, target: Variant)

const NOTHING_SELECTED := "Select a ship"
const CYCLER_NOTE := "Cyclers keep to their timetable."
const IN_FLIGHT_NOTE := "In flight to %s."
const NO_DESTINATION_CHOSEN := "Pick a destination"
## Logical px. ShipIcons textures have TEXTURE_SCALE times as many pixels, for HiDPI.
const TARGET_ICON_WIDTH := roundi(ShipIcons.SQUARE_SIZE)

@onready var ship_icon: TextureRect = %ShipIcon
@onready var ship_label: Label = %ShipName
@onready var note_label: Label = %Note
@onready var targets: OptionButton = %Targets
@onready var estimate_label: Label = %Estimate
@onready var depart_button: Button = %Depart

## Set by Main.
var icons: ShipIcons
var _fleet: Fleet
var _ship: Variant = null
## The targets behind `targets`' items, in the same order.
var _target_list: Array = []


func _ready() -> void:
	targets.item_selected.connect(func(_index: int) -> void: refresh())
	depart_button.pressed.connect(_on_depart_pressed)
	# The list's popup is its own window, so it needs its own override.
	for control in [targets, targets.get_popup()]:
		control.add_theme_constant_override("icon_max_width", TARGET_ICON_WIDTH)
	show_ship(null, null)


func show_ship(fleet: Fleet, ship: Variant) -> void:
	_fleet = fleet
	_ship = ship
	_target_list = []
	targets.clear()
	ship_label.text = NOTHING_SELECTED if ship == null else ship.name
	ship_icon.visible = ship != null
	ship_icon.texture = null if ship == null else icons.texture(ship)
	if ship is Transport:
		_set_targets(fleet.valid_targets(ship))
		if not _target_list.is_empty():
			targets.select(0) # a newly shown transport starts on its first target
	refresh()


## Keeps the note, the targets and the estimate current; the clock moves all
## three. A transport in flight keeps its destination, so it shows that
## instead of the dispatch controls until it arrives.
func refresh() -> void:
	var in_flight: bool = _ship is Transport and _ship.state == Transport.State.IN_TRANSIT
	var note := ""
	if _ship is Cycler:
		note = CYCLER_NOTE
	elif in_flight:
		note = IN_FLIGHT_NOTE % Fleet.target_name(_ship.target)
	if note_label.text != note:
		note_label.text = note
	note_label.visible = not note.is_empty()
	var can_dispatch: bool = _ship is Transport and not in_flight
	for control in [targets, estimate_label, depart_button]:
		control.visible = can_dispatch
	if not _ship is Transport:
		return
	var valid := _fleet.valid_targets(_ship)
	if valid != _target_list:
		_set_targets(valid)
	var target: Variant = selected_target()
	if target == null:
		show_no_destination()
	else:
		show_estimate(_fleet.estimate_days(_ship, target))


func selected_target() -> Variant:
	if targets.selected < 0:
		return null
	return _target_list[targets.selected]


func show_estimate(days: float) -> void:
	var reachable := days >= 0.0
	estimate_label.text = "Est. travel time: %s" % (Units.format_duration(days) if reachable else "unreachable")
	depart_button.disabled = not reachable


func show_no_destination() -> void:
	estimate_label.text = NO_DESTINATION_CHOSEN
	depart_button.disabled = true


## Refills the list, keeping the current choice if it is still valid and
## otherwise choosing nothing, so Depart never sends a ship somewhere the
## player didn't pick.
func _set_targets(valid: Array) -> void:
	var previous: Variant = selected_target()
	_target_list = valid
	targets.clear()
	for target in valid:
		if target is Cycler:
			targets.add_icon_item(icons.texture(target), Fleet.target_name(target))
		else:
			targets.add_item(Fleet.target_name(target))
	targets.select(valid.find(previous))


func _on_depart_pressed() -> void:
	var target: Variant = selected_target()
	if _ship is Transport and target != null:
		depart_requested.emit(_ship, target)
