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
	assert_true(e.has("resources"))
	assert_eq(e["resources"].get("trust"), 1.0)
	assert_eq(e["resources"].get("dice"), 1.0)
	assert_eq(e["resources"].get("knowledge"), 0.0)

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

func test_phone_practice_catalog_exposes_visible_resource_arbitrage() -> void:
	World.case_file.tags[&"skill_gap:phone"] = true
	World.case_file.tags[&"trauma:strangers"] = true
	bridge.reveal_hidden = false
	var snap: Dictionary = bridge.build_snapshot()
	var phone := _find_catalog_item(snap["catalog"]["interventions_available"], "int_phone_practice")
	assert_false(phone.is_empty())
	assert_eq(phone["resource_costs"].get("trust"), 2.0)
	assert_eq(phone["resource_costs"].get("dice"), 1.0)
	assert_eq(phone["resource_effects"].get("knowledge"), 2.0)
	assert_true(bool(phone.get("affordable", false)))
	assert_false(phone.has("hidden_resource_subsidies"))

func _find_catalog_item(items: Array, id: String) -> Dictionary:
	for item: Dictionary in items:
		if String(item.get("id", "")) == id:
			return item
	return {}

func _find_entry(entries: Array, id: String) -> Dictionary:
	for e: Dictionary in entries:
		if String(e.get("id", "")) == id:
			return e
	return {}

## Task 16: provenance must be OBSERVABLE in the NORMAL (non-blind) snapshot with the
## CORRECT value per entry, so the desk can tell derived (CA-emergent) facts from
## authored (scheduled-consequence) facts. test_bridge_redacted covers blind mode +
## presence; this asserts value-correctness in normal mode. No production change was
## needed: Task 15 already serialises "provenance": String(e.provenance) on every entry.
##
## summarize_traces note: the EVENT stream's case_file_updated carries only the entry
## StringName (Option B), so harness/lib/summarize_traces.py (obj.get("entry"), ~L74)
## needs NO change — provenance lives in the snapshot, not the trace. A provenance
## pass-through into summarize_traces is OUT OF SCOPE this slice.
##
## Verified red-green: 2026-06-24
func test_normal_snapshot_provenance_value_correct_per_entry() -> void:
	var authored := CaseEntry.new()
	authored.id = &"con_authored_eviction"
	authored.provenance = &"authored"
	authored.title = "Authored consequence: eviction notice"
	authored.tags = [&"housing"]
	World.case_file.add_entry(authored)

	var derived := CaseEntry.new()
	derived.id = &"trace_isolation"
	derived.provenance = &"derived"
	derived.title = "Derived trace: prolonged isolation"
	derived.tags = [&"social"]
	World.case_file.add_entry(derived)

	bridge.blind_read = false
	var snap: Dictionary = bridge.build_snapshot()
	var entries: Array = snap["case_file"]["entries"]

	var a := _find_entry(entries, "con_authored_eviction")
	var d := _find_entry(entries, "trace_isolation")
	assert_false(a.is_empty(), "authored entry must be surfaced in normal mode")
	assert_false(d.is_empty(), "derived entry must be surfaced in normal mode")
	assert_eq(String(a.get("provenance", "")), "authored",
		"authored entry must report provenance == authored")
	assert_eq(String(d.get("provenance", "")), "derived",
		"derived entry must report provenance == derived")
