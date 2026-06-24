extends GutTest

## Guards the Lens — PatternDeriver. It reads World.get_activity_history() (the stable
## seam, never CAEngine internals), evaluates authored PatternRule predicates against a
## hand-built history, and on a newly-true predicate emits a DERIVED CaseEntry
## (provenance=&"derived") onto World.case_file with an EventBus.case_file_updated signal.
##
## Asserts: (a) a rule fires exactly when its predicate holds and NOT when it doesn't;
## (b) the emitted CaseEntry carries provenance==&"derived"; (c) firing is idempotent
## (same rule never emitted twice across two evaluate() calls); (d) get_uncovered_summary
## is non-empty when history contains categories no rule matched.
##
## Rules + history are built IN-TEST (no dependency on Task 11 authored content). We
## inject hand-built rules into the live Catalog.pattern_rules dictionary for the
## duration of each test and restore it in teardown, so the deriver's real
## Catalog.pattern_rules.values() iteration is exercised end-to-end.
##
## Verified red-green: 2026-06-24

var _saved_rules: Dictionary = {}

func before_each() -> void:
	_saved_rules = Catalog.pattern_rules
	Catalog.pattern_rules = {}
	_world().reset_for_test()

func after_each() -> void:
	Catalog.pattern_rules = _saved_rules

func _world() -> Node:
	return get_node("/root/World")

func _record(day: int, step: int, activity: StringName, needs: Dictionary) -> Dictionary:
	return {
		"day": day,
		"step": step,
		"activity_id": activity,
		"needs_snapshot": needs,
		"mastery_snapshot": {},
	}

func _fixation_rule(rule_id: StringName, activity: StringName, min_count: int) -> PatternRule:
	var entry := CaseEntry.new()
	entry.id = StringName("trace_%s" % rule_id)
	entry.source = 0
	entry.provenance = &"authored"
	entry.title = "Repeated %s" % activity
	entry.body = "Client returned to %s again and again." % activity
	var rule := PatternRule.new()
	rule.id = rule_id
	rule.predicate_type = &"activity_fixation"
	rule.need_key = activity
	rule.min_count = min_count
	rule.window_days = 0
	rule.trace_fact = entry
	return rule

func _need_rule(rule_id: StringName, need: StringName, min_count: int, window: int) -> PatternRule:
	var entry := CaseEntry.new()
	entry.id = StringName("trace_%s" % rule_id)
	entry.title = "%s pressure" % need
	entry.body = "%s read high across repeated steps." % need
	var rule := PatternRule.new()
	rule.id = rule_id
	rule.predicate_type = &"need_deficit_over_window"
	rule.need_key = need
	rule.min_count = min_count
	rule.window_days = window
	rule.trace_fact = entry
	return rule

# --- (a) fires when predicate holds ---------------------------------------------------

func test_rule_fires_when_predicate_holds() -> void:
	var w := _world()
	var rule := _fixation_rule(&"fix_isolate", &"isolate", 2)
	Catalog.pattern_rules = {rule.id: rule}
	var history: Array = [
		_record(1, 0, &"isolate", {}),
		_record(1, 1, &"isolate", {}),
		_record(1, 2, &"eat", {}),
	]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	assert_true(w.case_file.has_entry(&"trace_fix_isolate"), "rule with satisfied predicate must emit its trace fact")
	assert_true(deriver.has_fired(&"fix_isolate"), "fired rule must be marked")

# --- (a-negative) does NOT fire when predicate fails (red-green target) ----------------

func test_rule_does_not_fire_when_predicate_fails() -> void:
	var w := _world()
	var rule := _fixation_rule(&"fix_isolate", &"isolate", 3)
	Catalog.pattern_rules = {rule.id: rule}
	# Only TWO isolate records, min_count is 3 -> predicate is FALSE.
	var history: Array = [
		_record(1, 0, &"isolate", {}),
		_record(1, 1, &"isolate", {}),
		_record(1, 2, &"eat", {}),
	]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	assert_false(w.case_file.has_entry(&"trace_fix_isolate"), "rule whose predicate is false must NOT emit a fact")
	assert_false(deriver.has_fired(&"fix_isolate"), "unfired rule must not be marked")

# --- (b) emitted CaseEntry carries provenance==derived --------------------------------

func test_emitted_fact_has_derived_provenance() -> void:
	var w := _world()
	var rule := _fixation_rule(&"fix_isolate", &"isolate", 1)
	Catalog.pattern_rules = {rule.id: rule}
	var history: Array = [_record(1, 0, &"isolate", {})]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	var emitted: CaseEntry = null
	for e: CaseEntry in w.case_file.entries:
		if e.id == &"trace_fix_isolate":
			emitted = e
	assert_not_null(emitted, "the derived fact must be present in the case file")
	assert_eq(emitted.provenance, &"derived", "derived fact must carry provenance=derived")
	# The shared .tres must NOT have been mutated to "derived".
	assert_eq(rule.trace_fact.provenance, &"authored", "shared trace_fact .tres must remain untouched")

# --- (c) firing is idempotent ---------------------------------------------------------

func test_firing_is_idempotent_across_evaluate_calls() -> void:
	var w := _world()
	var rule := _fixation_rule(&"fix_isolate", &"isolate", 1)
	Catalog.pattern_rules = {rule.id: rule}
	var history: Array = [_record(1, 0, &"isolate", {}), _record(1, 1, &"isolate", {})]
	var deriver := PatternDeriver.new(w)

	var emissions: Array = []
	var cb := func(entry_id: StringName) -> void:
		emissions.append(entry_id)
	EventBus.case_file_updated.connect(cb)
	deriver.evaluate(history)
	deriver.evaluate(history)
	EventBus.case_file_updated.disconnect(cb)

	var fires := 0
	for id: StringName in emissions:
		if id == &"trace_fix_isolate":
			fires += 1
	assert_eq(fires, 1, "an already-fired rule must not emit a second time")
	assert_eq(w.case_file.entries.size(), 1, "the derived fact must exist exactly once")

# --- (d) uncovered-behavior channel ---------------------------------------------------

func test_uncovered_summary_nonempty_when_categories_unmatched() -> void:
	var w := _world()
	# Rule only counts "isolate"; "eat" and "sleep" are uncovered.
	var rule := _fixation_rule(&"fix_isolate", &"isolate", 1)
	Catalog.pattern_rules = {rule.id: rule}
	var history: Array = [
		_record(1, 0, &"isolate", {}),
		_record(1, 1, &"eat", {}),
		_record(1, 2, &"sleep", {}),
		_record(1, 3, &"eat", {}),
	]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	var uncovered: Dictionary = deriver.get_uncovered_summary()
	assert_false(uncovered.is_empty(), "uncovered channel must be non-empty when history has unmatched categories")
	assert_true(uncovered.has(&"eat"), "unmatched activity 'eat' must be reported")
	assert_eq(int(uncovered.get(&"eat", 0)), 2, "uncovered count must reflect occurrences")
	assert_false(uncovered.has(&"isolate"), "an activity a rule fired on must NOT be reported as uncovered")

# --- need-deficit-over-window predicate -----------------------------------------------

func test_need_deficit_predicate_fires_over_window() -> void:
	var w := _world()
	var rule := _need_rule(&"social_deficit", &"social", 2, 2)
	Catalog.pattern_rules = {rule.id: rule}
	# Two recent records with high social pressure (>=0.7) within the 2-day window.
	var history: Array = [
		_record(1, 0, &"isolate", {&"social": 0.8}),
		_record(2, 0, &"isolate", {&"social": 0.9}),
	]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	assert_true(w.case_file.has_entry(&"trace_social_deficit"), "need-deficit rule must fire when need reads high enough often within window")

func test_need_deficit_predicate_silent_when_below_threshold() -> void:
	var w := _world()
	var rule := _need_rule(&"social_deficit", &"social", 2, 2)
	Catalog.pattern_rules = {rule.id: rule}
	var history: Array = [
		_record(1, 0, &"isolate", {&"social": 0.2}),
		_record(2, 0, &"isolate", {&"social": 0.3}),
	]
	var deriver := PatternDeriver.new(w)
	deriver.evaluate(history)
	assert_false(w.case_file.has_entry(&"trace_social_deficit"), "need-deficit rule must stay silent below threshold")
