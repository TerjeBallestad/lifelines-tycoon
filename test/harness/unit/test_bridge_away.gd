extends GutTest

var bridge: Node

func before_each() -> void:
	Clock.reset()
	Sim.reset_for_test()
	World.reset_for_test()
	bridge = get_node("/root/AgentBridge")
	bridge.start_event_capture()

func after_each() -> void:
	bridge.stop_event_capture()
	bridge.drain_events()

func test_away_unknown_id_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "away", "id": "does_not_exist"})
	assert_false(reply["ok"])
	assert_eq(reply["err"], "unknown_id")

func test_away_action_and_return_are_bridge_reachable() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "away", "id": "desk_nav_backlog"})
	assert_true(reply["ok"])
	assert_almost_eq(Clock.total_game_hours, 3.0, 0.001)
	var events: Array = bridge.drain_events()
	assert_true(_has_event(events, "away_action_completed"))
	assert_true(_has_event(events, "case_file_updated"))

	var ret: Dictionary = bridge.handle_command({"op": "return"})
	assert_true(ret["ok"])
	assert_true(bool(ret["report"].get("has_delta", false)))
	assert_eq(ret["report"].get("events", []).size(), 1)
	events = bridge.drain_events()
	assert_true(_has_event(events, "return_report_ready"))

func _has_event(events: Array, name: String) -> bool:
	for event: Dictionary in events:
		if String(event.get("ev", "")) == name:
			return true
	return false
