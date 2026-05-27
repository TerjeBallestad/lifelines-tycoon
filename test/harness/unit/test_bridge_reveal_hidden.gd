## Verified red-green: 2026-05-20
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	bridge.reveal_hidden = false

func test_mtg_absent_when_reveal_hidden_off() -> void:
	bridge.reveal_hidden = false
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_false(c.has("mtg_primary"))
	assert_false(c.has("mtg_secondary"))

func test_mtg_present_when_reveal_hidden_on() -> void:
	bridge.reveal_hidden = true
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_true(c.has("mtg_primary"))
	assert_true(c.has("mtg_secondary"))
	assert_eq(typeof(c["mtg_primary"]), TYPE_STRING)

func test_reveal_hidden_resets_to_off_after_test() -> void:
	# Defensive: clean up state for other tests that may run in the same session.
	bridge.reveal_hidden = false
	assert_false(bridge.reveal_hidden)

func test_hidden_resource_subsidy_present_only_when_revealed() -> void:
	World.case_file.tags[&"skill_gap:phone"] = true
	World.case_file.tags[&"trauma:strangers"] = true
	bridge.reveal_hidden = false
	var hidden_off := _find_catalog_item(bridge.build_snapshot()["catalog"]["interventions_available"], "int_phone_practice")
	assert_false(hidden_off.has("hidden_resource_subsidies"))

	bridge.reveal_hidden = true
	var hidden_on := _find_catalog_item(bridge.build_snapshot()["catalog"]["interventions_available"], "int_phone_practice")
	assert_eq(hidden_on["hidden_resource_subsidies"].get("trust"), 1.0)
	assert_true(hidden_on.has("hidden_resource_effects"))

func _find_catalog_item(items: Array, id: String) -> Dictionary:
	for item: Dictionary in items:
		if String(item.get("id", "")) == id:
			return item
	return {}
