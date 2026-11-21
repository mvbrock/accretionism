class_name FleetTable
extends Tree
## The Table tab: one row per ship. Rows are built once and their text is
## updated in place, so the selection holds while the clock runs.

signal ship_selected(ship: Variant)

const COLUMN_TITLES := ["Ship", "Origin", "Progress", "Destination"]

var _items: Array[TreeItem] = []


func _ready() -> void:
	columns = COLUMN_TITLES.size()
	column_titles_visible = true
	hide_root = true
	select_mode = Tree.SELECT_ROW
	for column in COLUMN_TITLES.size():
		set_column_title(column, COLUMN_TITLES[column])
		set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
	item_selected.connect(func() -> void: ship_selected.emit(get_selected().get_metadata(0)))


## `ships[i]` is the ship behind `rows[i]`.
func show_fleet(ships: Array, rows: Array[PackedStringArray]) -> void:
	clear()
	_items.clear()
	var root := create_item()
	for i in ships.size():
		var item := create_item(root)
		item.set_metadata(0, ships[i])
		_items.append(item)
	refresh(rows)


func refresh(rows: Array[PackedStringArray]) -> void:
	for i in _items.size():
		for column in COLUMN_TITLES.size():
			if _items[i].get_text(column) != rows[i][column]:
				_items[i].set_text(column, rows[i][column])


## Highlights `ship`'s row, or clears the highlight for null. Doesn't emit ship_selected.
func show_selected(ship: Variant) -> void:
	set_block_signals(true)
	deselect_all()
	for item in _items:
		if item.get_metadata(0) == ship:
			item.select(0)
			scroll_to_item(item)
	set_block_signals(false)
