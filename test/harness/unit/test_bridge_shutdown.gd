extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	bridge.shutdown_requested = false   # cleared each test

func test_shutdown_op_sets_flag_only() -> void:
	# Bridge should not actually quit the engine during a GUT run — it sets
	# `shutdown_requested = true` and the comms loop (Task 12) acts on it.
	var reply: Dictionary = bridge.handle_command({"op": "shutdown"})
	assert_eq(reply.get("ok"), true)
	assert_true(bridge.shutdown_requested)
