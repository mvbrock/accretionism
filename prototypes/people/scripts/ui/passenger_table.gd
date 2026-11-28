class_name PassengerTable
extends Tree
## One row per passenger. Rows are built once; text is updated in place, and
## sorting and filtering reorder and hide them, so the selection and scroll hold.

signal passenger_selected(passenger: Passenger)

const COLUMN_TITLES := ["Name", "ID#", "Origin", "Current location", "Final destination", "Progress"]
const HIGHLIGHT_SECONDS := 3.0
const HIGHLIGHT_COLOR := Color(0.16, 0.34, 0.55)
## A change of sort or filter shows on the next refresh; otherwise the order
## follows the clock at most this often.
const REAPPLY_SECONDS := 0.5

var _items: Dictionary[Passenger, TreeItem] = {}
var _order: Array[TreeItem] = []
var _selected: Passenger = null
var _sort_column := 0
var _sort_ascending := true
var _filter := ""
var _seen_history: Dictionary[Passenger, int] = {}
var _highlight_until_msec: Dictionary[Passenger, int] = {}
var _last_reapply_msec := 0


func _ready() -> void:
	columns = COLUMN_TITLES.size()
	column_titles_visible = true
	hide_root = true
	select_mode = Tree.SELECT_ROW
	_show_titles()
	column_title_clicked.connect(_on_title_clicked)
	item_selected.connect(_on_item_selected)


func show_passengers(passengers: Array) -> void:
	clear()
	_items.clear()
	_order.clear()
	_seen_history.clear()
	_highlight_until_msec.clear()
	var root := create_item()
	for passenger: Passenger in passengers:
		var item := create_item(root)
		item.set_metadata(0, passenger)
		_items[passenger] = item
		_order.append(item)
		_seen_history[passenger] = passenger.history.size()


func refresh(sim: Sim) -> void:
	var now := Time.get_ticks_msec()
	for passenger in _items:
		var item := _items[passenger]
		var cells := TableModel.row(sim, passenger)
		for column in COLUMN_TITLES.size():
			if item.get_text(column) != cells[column]:
				item.set_text(column, cells[column])
		_update_highlight(passenger, item, now)
	if now - _last_reapply_msec >= REAPPLY_SECONDS * 1000.0:
		_reapply(sim)


func set_sort(column: int, ascending: bool) -> void:
	_sort_column = column
	_sort_ascending = ascending
	_show_titles()
	_last_reapply_msec = 0


## Matches any cell, ignoring case. A selected passenger the filter hides stays
## selected and shows again when the filter lets them back in.
func set_filter(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	_last_reapply_msec = 0


## Highlights `passenger`'s row, or clears the highlight for null. Doesn't emit passenger_selected.
func show_selected(passenger: Passenger) -> void:
	_selected = passenger
	_select_row()


func _reapply(sim: Sim) -> void:
	_last_reapply_msec = Time.get_ticks_msec()
	var passengers: Array = _items.keys()
	var keys := {}
	for passenger: Passenger in passengers:
		keys[passenger] = TableModel.sort_key(sim, passenger, _sort_column)
	passengers.sort_custom(func(a: Passenger, b: Passenger) -> bool:
		if keys[a] == keys[b]:
			return a.id < b.id
		return (keys[a] < keys[b]) == _sort_ascending)
	var sorted: Array[TreeItem] = []
	for passenger: Passenger in passengers:
		sorted.append(_items[passenger])
	if sorted != _order:
		_order = sorted
		var next: TreeItem = null
		for i in range(sorted.size() - 1, -1, -1):
			if next != null:
				sorted[i].move_before(next)
			next = sorted[i]
	for passenger in _items:
		_items[passenger].visible = _matches_filter(sim, passenger)
	_select_row()


func _matches_filter(sim: Sim, passenger: Passenger) -> bool:
	if _filter.is_empty():
		return true
	for cell in TableModel.row(sim, passenger):
		if cell.to_lower().contains(_filter):
			return true
	return false


func _select_row() -> void:
	set_block_signals(true)
	deselect_all()
	if _selected != null and _items.has(_selected) and _items[_selected].visible:
		_items[_selected].select(0)
		scroll_to_item(_items[_selected])
	set_block_signals(false)


func _update_highlight(passenger: Passenger, item: TreeItem, now: int) -> void:
	if passenger.history.size() > _seen_history[passenger]:
		_highlight_until_msec[passenger] = now + int(HIGHLIGHT_SECONDS * 1000.0)
		_set_row_color(item, HIGHLIGHT_COLOR)
	elif _highlight_until_msec.has(passenger) and now >= _highlight_until_msec[passenger]:
		_highlight_until_msec.erase(passenger)
		_clear_row_color(item)
	_seen_history[passenger] = passenger.history.size()


func _set_row_color(item: TreeItem, color: Color) -> void:
	for column in COLUMN_TITLES.size():
		item.set_custom_bg_color(column, color)


func _clear_row_color(item: TreeItem) -> void:
	for column in COLUMN_TITLES.size():
		item.clear_custom_bg_color(column)


func _show_titles() -> void:
	for column in COLUMN_TITLES.size():
		var arrow := ""
		if column == _sort_column:
			arrow = " ▲" if _sort_ascending else " ▼"
		set_column_title(column, COLUMN_TITLES[column] + arrow)
		set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)


func _on_title_clicked(column: int, _mouse_button: int) -> void:
	set_sort(column, not _sort_ascending if column == _sort_column else true)


func _on_item_selected() -> void:
	_selected = get_selected().get_metadata(0)
	passenger_selected.emit(_selected)
