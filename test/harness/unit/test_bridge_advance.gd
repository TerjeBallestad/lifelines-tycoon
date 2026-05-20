extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	Clock.reset()
	Sim.reset_for_test()
	World.client.overskudd = 100.0

func test_advance_moves_clock() -> void:
	var hour_before: float = Clock.hour_of_day
	var day_before: int = Clock.day
	bridge.handle_command({"op": "advance", "game_hours": 3.0})
	# 3 hours later (no day wrap in this case)
	assert_almost_eq(Clock.hour_of_day, hour_before + 3.0, 0.01)
	assert_eq(Clock.day, day_before)

func test_advance_zero_hours_is_no_op() -> void:
	var hour_before: float = Clock.hour_of_day
	var reply: Dictionary = bridge.handle_command({"op": "advance", "game_hours": 0.0})
	assert_eq(reply.get("ok"), true)
	assert_almost_eq(Clock.hour_of_day, hour_before, 0.01)

func test_advance_negative_hours_returns_error() -> void:
	var reply: Dictionary = bridge.handle_command({"op": "advance", "game_hours": -1.0})
	assert_eq(reply.get("ok"), false)
	assert_eq(reply.get("err"), "negative_hours")
