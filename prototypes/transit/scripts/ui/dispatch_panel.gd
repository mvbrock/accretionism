class_name DispatchPanel
extends VBoxContainer
## Side panel: the selected ship's name and, for a transport, its valid
## targets, the travel-time estimate and the Depart button.

signal depart_requested(transport: Transport, target: Variant)

const NOTHING_SELECTED := "Select a ship"
const CYCLER_NOTE := "Cyclers keep to their timetable."

@onready var ship_label: Label = %ShipName
@onready var note_label: Label = %Note
@onready var targets: OptionButton = %Targets
@onready var estimate_label: Label = %Estimate
@onready var depart_button: Button = %Depart

var _fleet: Fleet
var _ship: Variant = null
## The targets behind `targets`' items, in the same order.
var _target_list: Array = []


func _ready() -> void:
	targets.item_selected.connect(func(_index: int) -> void: refresh())
	depart_button.pressed.connect(_on_depart_pressed)
	show_ship(null, null)


func show_ship(fleet: Fleet, ship: Variant) -> void:
	_fleet = fleet
	_ship = ship
	_target_list = []
	targets.clear()
	ship_label.text = NOTHING_SELECTED if ship == null else ship.name
	note_label.text = CYCLER_NOTE if ship is Cycler else ""
	note_label.visible = ship is Cycler
	for control in [targets, estimate_label, depart_button]:
		control.visible = ship is Transport
	refresh()


## Keeps the targets and the estimate current; the clock moves both.
func refresh() -> void:
	if not _ship is Transport:
		return
	var valid := _fleet.valid_targets(_ship)
	if valid != _target_list:
		_set_targets(valid)
	show_estimate(_fleet.estimate_days(_ship, selected_target()))


func selected_target() -> Variant:
	if targets.selected < 0:
		return null
	return _target_list[targets.selected]


func show_estimate(days: float) -> void:
	var reachable := days >= 0.0
	estimate_label.text = "Est. travel time: %s" % (Units.format_duration(days) if reachable else "unreachable")
	depart_button.disabled = not reachable


## Refills the list, keeping the current choice when it is still valid.
func _set_targets(valid: Array) -> void:
	var previous: Variant = selected_target()
	_target_list = valid
	targets.clear()
	for target in valid:
		targets.add_item(Fleet.target_name(target))
	targets.select(maxi(0, valid.find(previous)) if not valid.is_empty() else -1)


func _on_depart_pressed() -> void:
	var target: Variant = selected_target()
	if _ship is Transport and target != null:
		depart_requested.emit(_ship, target)
