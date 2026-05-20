extends GutTest

func test_autoload_present() -> void:
	var bridge: Node = get_node_or_null("/root/AgentBridge")
	assert_not_null(bridge, "AgentBridge autoload should be present")

func test_dormant_by_default() -> void:
	var bridge: Node = get_node("/root/AgentBridge")
	assert_false(bridge.active, "AgentBridge.active should default to false")
