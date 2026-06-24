extends GutTest

## Guards World's append-only activity history — the stable seam between the
## living sim and the Lens. CAEngine/Sim WRITE via append_activity_record();
## PatternDeriver READS via get_activity_history(). The read query MUST return
## an isolated deep copy so the Lens (or any caller) cannot mutate the internal
## records and corrupt the canonical history. reset_for_test() must clear it.
##
## Verified red-green: 2026-06-24

func _world() -> Node:
	return get_node("/root/World")

func _record(day: int, step: int, activity: StringName) -> Dictionary:
	return {
		"day": day,
		"step": step,
		"activity_id": activity,
		"needs_snapshot": {&"energy": 0.5, &"hunger": 0.2},
		"mastery_snapshot": {activity: 1},
	}

func test_append_then_read_returns_records_in_order() -> void:
	var w := _world()
	w.reset_for_test()
	w.append_activity_record(_record(1, 0, &"rest"))
	w.append_activity_record(_record(1, 1, &"eat"))
	w.append_activity_record(_record(1, 2, &"rest"))
	var history: Array = w.get_activity_history()
	assert_eq(history.size(), 3)
	assert_eq(StringName(history[0]["activity_id"]), &"rest")
	assert_eq(StringName(history[1]["activity_id"]), &"eat")
	assert_eq(int(history[2]["step"]), 2)

func test_returned_array_mutation_does_not_affect_internal_history() -> void:
	# Proves read-only isolation: clearing / appending to the returned array, and
	# mutating a returned record's nested snapshot, must NOT change what a
	# subsequent read sees. If get_activity_history() leaked the internal array,
	# these assertions fail (this is the red-green target).
	var w := _world()
	w.reset_for_test()
	w.append_activity_record(_record(1, 0, &"rest"))
	w.append_activity_record(_record(1, 1, &"eat"))

	var leaked: Array = w.get_activity_history()
	leaked.append(_record(9, 9, &"injected"))
	leaked[0]["activity_id"] = &"tampered"
	leaked[0]["needs_snapshot"][&"energy"] = 999.0

	var fresh: Array = w.get_activity_history()
	assert_eq(fresh.size(), 2, "internal history size must be unchanged by external append")
	assert_eq(StringName(fresh[0]["activity_id"]), &"rest", "internal record must be unchanged by external mutation")
	assert_almost_eq(float(fresh[0]["needs_snapshot"][&"energy"]), 0.5, 0.0001, "nested snapshot must be deep-isolated")

func test_append_does_not_alias_caller_record() -> void:
	# The write seam deep-copies on the way in: mutating the record AFTER passing
	# it must not change the stored history either.
	var w := _world()
	w.reset_for_test()
	var rec := _record(2, 0, &"rest")
	w.append_activity_record(rec)
	rec["activity_id"] = &"after_the_fact"
	rec["needs_snapshot"][&"energy"] = -1.0
	var history: Array = w.get_activity_history()
	assert_eq(StringName(history[0]["activity_id"]), &"rest")
	assert_almost_eq(float(history[0]["needs_snapshot"][&"energy"]), 0.5, 0.0001)

func test_reset_for_test_clears_history() -> void:
	var w := _world()
	w.reset_for_test()
	w.append_activity_record(_record(1, 0, &"rest"))
	w.append_activity_record(_record(1, 1, &"eat"))
	assert_eq(w.get_activity_history().size(), 2)
	w.reset_for_test()
	assert_eq(w.get_activity_history().size(), 0, "reset_for_test must clear the activity history")
