class_name LinkStatus
extends VBoxContainer
## Two labelled bars showing a command's progress: the uplink as it travels to the
## ship, the downlink as the reply travels back. Both read idle when nothing is in flight.

const BAR_HEIGHT_PX := 8

var uplink_label: Label
var uplink_bar: ProgressBar
var downlink_label: Label
var downlink_bar: ProgressBar


func _init() -> void:
	uplink_label = _add_label()
	uplink_bar = _add_bar()
	downlink_label = _add_label()
	downlink_bar = _add_bar()


func show_link(link: ShipLink) -> void:
	var line := link.line()
	uplink_label.text = uplink_text(link.uplink_active(), link.downlink_active(), line, link.uplink_left_s())
	downlink_label.text = downlink_text(link.uplink_active(), link.downlink_active(), line, link.downlink_left_s())
	uplink_bar.value = link.uplink_fraction()
	downlink_bar.value = link.downlink_fraction()


static func uplink_text(uplink_active: bool, downlink_active: bool, line: String, left_s: float) -> String:
	if uplink_active:
		return "uplink: %s — %s left" % [line, Units.duration_text(left_s)]
	if downlink_active:
		return "uplink: %s — sent" % line
	return "uplink: idle"


static func downlink_text(uplink_active: bool, downlink_active: bool, line: String, left_s: float) -> String:
	if downlink_active:
		return "downlink: %s — %s left" % [line, Units.duration_text(left_s)]
	if uplink_active:
		return "downlink: waiting"
	return "downlink: idle"


func _add_label() -> Label:
	var label := Label.new()
	add_child(label)
	return label


func _add_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT_PX)
	add_child(bar)
	return bar
