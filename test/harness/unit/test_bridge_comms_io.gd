extends GutTest

var bridge: Node
var tmp_dir: String

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	# Quiesce Sim so it doesn't background-tick between assertions.
	Sim.reset_for_test()
	Clock.reset()
	World.reset_for_test()
	tmp_dir = BridgeTestHelpers.make_tmp_comms_dir()
	bridge.shutdown_requested = false
	bridge.active = false
	bridge.start_event_capture()
	# Drain ONCE here, and again right before each test asserts —
	# any cascading capacity_changed signals from World.reset_for_test() etc
	# need to be cleared.
	bridge.drain_events()
	bridge.bind_comms(tmp_dir)
	# Final drain: in case bind_comms or anything above buffered events,
	# clear before tests start.
	bridge.drain_events()
	# Yield a process frame so any deferred signals from setup have fired
	# before we drain and hand off to the test body.
	await get_tree().process_frame
	bridge.drain_events()

func after_each() -> void:
	bridge.stop_event_capture()
	bridge.unbind_comms()

func _write_cmd_line(line: String) -> void:
	var path := tmp_dir + "/cmd.jsonl"
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()

func _read_events_lines() -> Array:
	var path := tmp_dir + "/events.jsonl"
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() != "":
			lines.append(JSON.parse_string(line))
	f.close()
	return lines

func test_pump_processes_pending_commands() -> void:
	# Stop capture, drain any stray buffered events that may have been enqueued
	# by GUT's internal frame yields between before_each and this test body,
	# then restart capture clean before exercising pump.
	bridge.stop_event_capture()
	bridge.drain_events()
	bridge.start_event_capture()
	_write_cmd_line(JSON.stringify({"op": "snapshot"}))
	bridge.pump()
	var events := _read_events_lines()
	# Snapshot reply is the only output of a snapshot command (no event-bus signal involved).
	assert_eq(events.size(), 1)
	assert_eq(events[0]["reply"]["ok"], true)
	assert_true(events[0]["reply"].has("snapshot"))

func test_pump_appends_eventbus_events() -> void:
	_write_cmd_line(JSON.stringify({"op": "advance", "game_hours": 0.0}))
	EventBus.day_started.emit(2)
	bridge.pump()
	var events := _read_events_lines()
	# At least one "ev":"day_started" appears
	var found := false
	for e in events:
		if e.get("ev", "") == "day_started":
			found = true
	assert_true(found, "day_started event must be flushed to events.jsonl")

func test_ready_sentinel_written_after_each_command() -> void:
	_write_cmd_line(JSON.stringify({"op": "snapshot"}))
	bridge.pump()
	assert_true(FileAccess.file_exists(tmp_dir + "/ready"))

func test_shutdown_op_stops_pump() -> void:
	_write_cmd_line(JSON.stringify({"op": "shutdown"}))
	bridge.pump()
	assert_true(bridge.shutdown_requested)
