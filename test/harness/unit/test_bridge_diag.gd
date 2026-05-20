extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	World.client.overskudd = 100.0
	World.economy.capacity_max = 6.0
	World.economy.capacity_current = 6.0

func test_diag_unknown_id_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "diag", "id": "does_not_exist"})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "unknown_id")

func test_diag_known_id_succeeds() -> void:
	# Pick the first diagnostic from the catalog.
	var keys: Array = Catalog.diagnostics.keys()
	assert_gt(keys.size(), 0, "Catalog should have at least one diagnostic")
	var first_id: StringName = keys[0]
	var d: Diagnostic = Catalog.diagnostics[first_id]
	# Force gate clear by setting case-file tags to whatever the diag needs.
	for t: StringName in d.gate_tags:
		World.case_file.tags[t] = true

	var reply: Dictionary = bridge.handle_command({"op": "diag", "id": String(first_id)})
	assert_eq(reply.get("ok"), true)
	# Capacity should have decreased.
	assert_lt(World.economy.capacity_current, 6.0)
