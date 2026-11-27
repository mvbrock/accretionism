extends TestCase


func test_idle_texts() -> void:
	var up := LinkStatus.uplink_text(false, false, "", 0.0)
	var down := LinkStatus.downlink_text(false, false, "", 0.0)
	assert_true(up == "uplink: idle", "got '%s'" % up)
	assert_true(down == "downlink: idle", "got '%s'" % down)


func test_uplink_text_counts_down() -> void:
	var text := LinkStatus.uplink_text(true, false, "door open hatch", 192.0)
	assert_true(text == "uplink: door open hatch — 3:12 left", "got '%s'" % text)
	text = LinkStatus.downlink_text(false, true, "door open hatch", 192.0)
	assert_true(text == "downlink: door open hatch — 3:12 left", "got '%s'" % text)


func test_the_waiting_and_sent_states() -> void:
	var waiting := LinkStatus.downlink_text(true, false, "x", 5.0)
	var sent := LinkStatus.uplink_text(false, true, "door open hatch", 5.0)
	assert_true(waiting == "downlink: waiting", "got '%s'" % waiting)
	assert_true(sent == "uplink: door open hatch — sent", "got '%s'" % sent)
