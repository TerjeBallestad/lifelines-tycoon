extends GutTest

func after_each() -> void:
	var bridge: Node = get_node("/root/AgentBridge")
	bridge.active = false
	bridge.comms_dir = ""
	bridge.reveal_hidden = false

func test_activate_sets_state() -> void:
	var bridge: Node = get_node("/root/AgentBridge")
	bridge.active = false
	bridge.comms_dir = ""
	bridge.reveal_hidden = false

	BridgeTestHelpers.activate(bridge, "user://run1", true)

	assert_true(bridge.active)
	assert_eq(bridge.comms_dir, "user://run1")
	assert_true(bridge.reveal_hidden)
