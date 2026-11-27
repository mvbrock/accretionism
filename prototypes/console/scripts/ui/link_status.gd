class_name LinkStatus
extends VBoxContainer
## Two labelled bars showing a command's progress: the uplink as it travels to the
## ship, the downlink as the reply travels back. Both read idle when nothing is in flight.

const BAR_HEIGHT_PX := 8
const TRACK_COLOR := Color(1, 1, 1, 0.18)

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
	var phase := link.phase()
	var line := link.line()
	var left_s := link.leg_left_s()
	var fraction := link.leg_fraction()
	uplink_label.text = uplink_text(phase, line, left_s)
	downlink_label.text = downlink_text(phase, line, left_s)
	match phase:
		ShipLink.Phase.UPLINK:
			uplink_bar.value = fraction
			downlink_bar.value = 0.0
		ShipLink.Phase.DOWNLINK:
			uplink_bar.value = 1.0
			downlink_bar.value = fraction
		_:
			uplink_bar.value = 0.0
			downlink_bar.value = 0.0


static func uplink_text(phase: ShipLink.Phase, line: String, left_s: float) -> String:
	match phase:
		ShipLink.Phase.UPLINK:
			return "uplink: %s — %s left" % [line, Units.duration_text(left_s)]
		ShipLink.Phase.DOWNLINK:
			return "uplink: %s — sent" % line
	return "uplink: idle"


static func downlink_text(phase: ShipLink.Phase, line: String, left_s: float) -> String:
	match phase:
		ShipLink.Phase.DOWNLINK:
			return "downlink: %s — %s left" % [line, Units.duration_text(left_s)]
		ShipLink.Phase.UPLINK:
			return "downlink: waiting"
	return "downlink: idle"


func _add_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _add_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT_PX)
	bar.add_theme_stylebox_override("background", _flat(TRACK_COLOR))
	bar.add_theme_stylebox_override("fill", _flat(DashboardView.GREEN))
	add_child(bar)
	return bar


func _flat(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
