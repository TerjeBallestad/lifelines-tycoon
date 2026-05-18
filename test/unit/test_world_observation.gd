extends GutTest

var w: Node
var _saved_observations: Dictionary

func _entry(id: StringName, tags: Array[StringName]) -> CaseEntry:
	var e := CaseEntry.new()
	e.id = id
	e.tags = tags
	return e

func before_each() -> void:
	w = get_node("/root/World")
	w.reset_for_test()
	_saved_observations = Catalog.observations.duplicate()
	Catalog.observations.clear()
	Catalog.observations[&"obs_a"] = _entry(&"obs_a", [&"t1"])
	Catalog.observations[&"obs_b"] = _entry(&"obs_b", [&"t2"])

func after_each() -> void:
	Catalog.observations = _saved_observations

func test_no_candidates_returns_null() -> void:
	Catalog.observations.clear()
	var picked: CaseEntry = w.try_surface_observation()
	assert_null(picked)

func test_pick_adds_to_case_file_and_emits() -> void:
	watch_signals(EventBus)
	seed(42)
	var picked: CaseEntry = w.try_surface_observation()
	assert_not_null(picked)
	assert_true(w.case_file.has_entry(picked.id))
	assert_signal_emitted_with_parameters(EventBus, "case_file_updated", [picked.id])

func test_does_not_repick_existing_entry() -> void:
	seed(1)
	w.try_surface_observation()
	w.try_surface_observation()
	if Catalog.observations.size() >= 2:
		assert_eq(w.case_file.entries.size(), 2)
	else:
		assert_lte(w.case_file.entries.size(), Catalog.observations.size())
