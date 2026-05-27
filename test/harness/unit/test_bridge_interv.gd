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

func test_phone_interv_emits_resource_trace_event() -> void:
	World.case_file.tags[&"skill_gap:phone"] = true
	World.case_file.tags[&"trauma:strangers"] = true
	bridge.start_event_capture()

	var reply: Dictionary = bridge.handle_command({"op": "interv", "id": "int_phone_practice"})
	var events: Array = bridge.drain_events()
	bridge.stop_event_capture()

	assert_eq(reply.get("ok"), true)
	var resource_event := _find_event(events, "economy_resources_changed")
	assert_false(resource_event.is_empty())
	assert_eq(resource_event.get("source_id"), "int_phone_practice")
	assert_eq(resource_event["resources"].get("trust"), 0.0)
	assert_eq(resource_event["resources"].get("dice"), 0.0)
	assert_eq(resource_event["resources"].get("knowledge"), 2.0)
	assert_eq(resource_event["delta"].get("trust"), -1.0)
	assert_eq(resource_event["delta"].get("knowledge"), 2.0)

func _find_event(events: Array, ev_name: String) -> Dictionary:
	for event: Dictionary in events:
		if String(event.get("ev", "")) == ev_name:
			return event
	return {}
