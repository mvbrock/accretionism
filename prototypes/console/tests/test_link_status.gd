extends TestCase


func test_idle_texts() -> void:
	assert_true(LinkStatus.uplink_text(false, false, "", 0.0) == "uplink: idle", "uplink")
	assert_true(LinkStatus.downlink_text(false, false, "", 0.0) == "downlink: idle", "downlink")


func test_uplink_text_counts_down() -> void:
	var text := LinkStatus.uplink_text(true, false, "door open hatch", 192.0)
	assert_true(text == "uplink: door open hatch — 3:12 left", "got '%s'" % text)
	assert_true(LinkStatus.downlink_text(false, true, "door open hatch", 192.0) == "downlink: door open hatch — 3:12 left", "downlink")


func test_the_waiting_and_sent_states() -> void:
	assert_true(LinkStatus.downlink_text(true, false, "x", 5.0) == "downlink: waiting", "waiting while sending")
	assert_true(LinkStatus.uplink_text(false, true, "door open hatch", 5.0) == "uplink: door open hatch — sent", "sent while answering")
