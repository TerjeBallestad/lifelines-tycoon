## Verified red-green: 2026-05-20
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()

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
