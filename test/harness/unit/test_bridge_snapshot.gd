extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()

func test_snapshot_returns_required_top_level_keys() -> void:
	var snap: Dictionary = bridge.build_snapshot()

	assert_true(snap.has("time"))
	assert_true(snap.has("client"))
	assert_true(snap.has("case_file"))
	assert_true(snap.has("economy"))
	assert_true(snap.has("catalog"))

func test_snapshot_client_includes_needs_and_overskudd() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]

	assert_true(c.has("needs"))
	assert_true(c.has("cognitive"))
	assert_true(c.has("overskudd"))
	assert_true(c.has("overskudd_ceiling"))
	assert_eq(typeof(c["overskudd"]), TYPE_FLOAT)

func test_snapshot_time_includes_day_hour() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var t: Dictionary = snap["time"]
	assert_true(t.has("day"))
	assert_true(t.has("hour"))
	assert_true(t.has("scale"))
	assert_true(t.has("paused"))

func test_snapshot_economy_capacity() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var e: Dictionary = snap["economy"]
	assert_true(e.has("capacity_current"))
	assert_true(e.has("capacity_max"))

func test_snapshot_catalog_has_available_lists() -> void:
	var snap: Dictionary = bridge.build_snapshot()
	var cat: Dictionary = snap["catalog"]
	assert_true(cat.has("diagnostics_available"))
	assert_true(cat.has("interventions_available"))
	assert_true(cat.has("away_actions_available"))
	assert_true(cat.has("schedule_pending"))
	assert_eq(typeof(cat["diagnostics_available"]), TYPE_ARRAY)
	assert_eq(typeof(cat["away_actions_available"]), TYPE_ARRAY)
	assert_eq(typeof(cat["schedule_pending"]), TYPE_ARRAY)
