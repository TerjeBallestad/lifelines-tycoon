extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	World.client.overskudd = 100.0
	World.economy.capacity_max = 6.0
	World.economy.capacity_current = 6.0

func test_interv_unknown_id_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "interv", "id": "nope"})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "unknown_id")

func test_interv_known_id_succeeds() -> void:
	var keys: Array = Catalog.interventions.keys()
	assert_gt(keys.size(), 0, "Catalog should have at least one intervention")
	var first_id: StringName = keys[0]
	var i: Intervention = Catalog.interventions[first_id]
	for t: StringName in i.gate_tags:
		World.case_file.tags[t] = true

	var reply: Dictionary = bridge.handle_command({"op": "interv", "id": String(first_id)})
	assert_eq(reply.get("ok"), true)
