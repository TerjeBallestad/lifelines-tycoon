## Task 15: the redacted blind-read snapshot mode.
## In blind-read mode build_snapshot must (a) strip the player-visible raw numbers
## from client (needs/cognitive/overskudd) so the blind reader cannot cheat by
## reading them, and (b) filter case_file.entries to provenance==&"derived" only,
## so authored scheduled-consequence facts are never surfaced. The normal snapshot
## is unchanged. blind_read is independent of reveal_hidden.
## Verified red-green: 2026-06-24
extends GutTest

var bridge: Node

func before_each() -> void:
	bridge = get_node("/root/AgentBridge")
	World.reset_for_test()
	bridge.reveal_hidden = false
	bridge.blind_read = false

func after_each() -> void:
	# Defensive: leave global flags off for other tests in the session.
	bridge.blind_read = false
	bridge.reveal_hidden = false

func _seed_mixed_case_file() -> void:
	# Authored consequence entry (baked provenance) — must be EXCLUDED in blind-read.
	var authored := CaseEntry.new()
	authored.id = &"con_authored_eviction"
	authored.source = 0
	authored.provenance = &"authored"
	authored.title = "Authored consequence: eviction notice"
	authored.tags = [&"housing"]
	World.case_file.add_entry(authored)

	# Derived (CA-emergent) trace fact — must be INCLUDED in blind-read.
	var derived := CaseEntry.new()
	derived.id = &"trace_isolation"
	derived.source = 0
	derived.provenance = &"derived"
	derived.title = "Derived trace: prolonged isolation"
	derived.tags = [&"social"]
	World.case_file.add_entry(derived)

func test_blind_read_client_omits_raw_numbers() -> void:
	bridge.blind_read = true
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_false(c.has("needs"), "blind-read client must NOT expose raw needs")
	assert_false(c.has("cognitive"), "blind-read client must NOT expose raw cognitive")
	assert_false(c.has("overskudd"), "blind-read client must NOT expose raw overskudd")
	assert_false(c.has("overskudd_ceiling"), "blind-read client must NOT expose overskudd_ceiling")
	# Non-redacted identity fields stay so the reader knows who it is reading.
	assert_true(c.has("id"))
	assert_true(c.has("display_name"))

func test_blind_read_case_file_returns_derived_only() -> void:
	_seed_mixed_case_file()
	bridge.blind_read = true
	var snap: Dictionary = bridge.build_snapshot()
	var entries: Array = snap["case_file"]["entries"]
	assert_eq(entries.size(), 1, "blind-read must surface ONLY the derived entry")
	var ids: Array = []
	for e: Dictionary in entries:
		ids.append(String(e.get("id", "")))
		assert_eq(String(e.get("provenance", "")), "derived",
			"every blind-read entry must be derived-provenance")
	assert_true(ids.has("trace_isolation"), "derived entry must be present")
	assert_false(ids.has("con_authored_eviction"), "authored entry must be excluded")

func test_normal_snapshot_unchanged_keeps_raw_numbers_and_all_entries() -> void:
	_seed_mixed_case_file()
	bridge.blind_read = false
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_true(c.has("needs"), "normal snapshot keeps needs")
	assert_true(c.has("cognitive"), "normal snapshot keeps cognitive")
	assert_true(c.has("overskudd"), "normal snapshot keeps overskudd")
	assert_true(c.has("overskudd_ceiling"), "normal snapshot keeps overskudd_ceiling")
	var entries: Array = snap["case_file"]["entries"]
	assert_eq(entries.size(), 2, "normal snapshot surfaces both authored and derived")

func test_provenance_serialised_on_every_entry() -> void:
	_seed_mixed_case_file()
	bridge.blind_read = false
	var snap: Dictionary = bridge.build_snapshot()
	var entries: Array = snap["case_file"]["entries"]
	for e: Dictionary in entries:
		assert_true(e.has("provenance"),
			"every serialised entry must carry provenance (Task 15/16)")
	# id/title/tags still serialised — Option B keeps the existing shape intact.
	for e: Dictionary in entries:
		assert_true(e.has("id"))
		assert_true(e.has("title"))
		assert_true(e.has("tags"))

func test_blind_read_independent_of_reveal_hidden() -> void:
	# The gate redacts the player-visible numbers (blind_read) while separately
	# using reveal_hidden (colors) for ground truth. They must not interfere.
	bridge.blind_read = true
	bridge.reveal_hidden = true
	var snap: Dictionary = bridge.build_snapshot()
	var c: Dictionary = snap["client"]
	assert_false(c.has("needs"), "blind-read still redacts numbers even with reveal_hidden on")
	assert_true(c.has("colors"), "reveal_hidden still surfaces colors ground truth")
