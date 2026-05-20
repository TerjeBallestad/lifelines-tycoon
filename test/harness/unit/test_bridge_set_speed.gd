extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")

func test_set_speed_changes_clock_time_scale() -> void:
	bridge.handle_command({"op": "set_speed", "scale": 4.0})
	assert_almost_eq(Clock.time_scale, 4.0, 0.01)
	# Reset for next tests
	bridge.handle_command({"op": "set_speed", "scale": 1.0})

func test_set_speed_zero_rejected() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "set_speed", "scale": 0.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "invalid_scale")

func test_set_speed_negative_rejected() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "set_speed", "scale": -1.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "invalid_scale")
