class_name Console
extends VBoxContainer
## The command line: scrollback, the link's progress bars, then one input line. Up and down recall
## earlier lines.

signal line_submitted(line: String)

const MAX_LINES := 200

var input: LineEdit
var scrollback: RichTextLabel
var link_status: LinkStatus

var _history: Array[String] = []
## Index into _history while recalling; _history.size() means a fresh line.
var _recall := 0


func _init() -> void:
	scrollback = RichTextLabel.new()
	scrollback.scroll_following = true
	scrollback.selection_enabled = true
	scrollback.custom_minimum_size = Vector2(0, 90)
	scrollback.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scrollback)
	link_status = LinkStatus.new()
	add_child(link_status)
	input = LineEdit.new()
	input.keep_editing_on_text_submit = true
	input.placeholder_text = "type 'help' for commands"
	input.text_submitted.connect(_on_text_submitted)
	input.gui_input.connect(_on_input_gui_input)
	add_child(input)


func print_line(text: String) -> void:
	scrollback.add_text(text + "\n")
	while scrollback.get_paragraph_count() > MAX_LINES:
		scrollback.remove_paragraph(0)


func _on_text_submitted(line: String) -> void:
	input.clear()
	if line.strip_edges().is_empty():
		return
	_history.append(line)
	_recall = _history.size()
	line_submitted.emit(line)


func _on_input_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_UP:
		_recall_to(maxi(_recall - 1, 0))
	elif event.keycode == KEY_DOWN:
		_recall_to(mini(_recall + 1, _history.size()))
	else:
		return
	input.accept_event()


func _recall_to(index: int) -> void:
	_recall = index
	input.text = _history[index] if index < _history.size() else ""
	input.caret_column = input.text.length()
