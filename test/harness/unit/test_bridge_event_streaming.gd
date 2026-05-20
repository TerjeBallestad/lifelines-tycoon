extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	Clock.reset()
	Clock.day = 2        # align Sim._last_seen_day with the day value tests emit
	Sim.reset_for_test()
	Clock.day = 1        # restore Clock for other tests
	bridge.start_event_capture()
	bridge.drain_events()   # clear any pre-existing buffered events

func after_each() -> void:
	bridge.stop_event_capture()

func test_overskudd_changed_buffered() -> void:
	EventBus.overskudd_changed.emit(&"elling", 42.0)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "overskudd_changed")
	assert_eq(events[0]["client"], "elling")
	assert_almost_eq(events[0]["v"], 42.0, 0.01)

func test_case_file_updated_buffered() -> void:
	EventBus.case_file_updated.emit(&"obs_alphabetizes")
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "case_file_updated")
	assert_eq(events[0]["entry"], "obs_alphabetizes")

func test_day_started_buffered() -> void:
	EventBus.day_started.emit(2)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["ev"], "day_started")
	assert_eq(events[0]["day"], 2)

func test_drain_clears_buffer() -> void:
	EventBus.overskudd_changed.emit(&"elling", 10.0)
	var first: Array = bridge.drain_events()
	assert_eq(first.size(), 1)
	var second: Array = bridge.drain_events()
	assert_eq(second.size(), 0)

func test_events_include_time_field() -> void:
	EventBus.overskudd_changed.emit(&"elling", 10.0)
	var events: Array = bridge.drain_events()
	assert_eq(events.size(), 1)
	assert_true(events[0].has("t"))
	assert_true(events[0]["t"].has("d"))
	assert_true(events[0]["t"].has("h"))
