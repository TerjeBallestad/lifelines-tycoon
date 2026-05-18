extends GutTest

var w: Node

func _make_entry(id: StringName, tags: Array[StringName]) -> CaseEntry:
	var e := CaseEntry.new()
	e.id = id
	e.tags = tags
	return e

func _make_diag(id: StringName, cw_cost: float, ov_cost: float, gate: Array[StringName], yields_: Array[CaseEntry]) -> Diagnostic:
	var d := Diagnostic.new()
	d.id = id
	d.caseworker_cost = cw_cost
	d.overskudd_cost = ov_cost
	d.gate_tags = gate
	d.yields = yields_
	return d

func _make_int(id: StringName, cw: float, ov: float, gate: Array[StringName], n_eff: Dictionary, s_eff: Dictionary) -> Intervention:
	var i := Intervention.new()
	i.id = id
	i.caseworker_cost = cw
	i.overskudd_cost = ov
	i.gate_tags = gate
	i.needs_effects = n_eff
	i.skill_effects = s_eff
	return i

func before_each() -> void:
	w = get_node("/root/World")
	w.reset_for_test()
	w.client.needs = {&"energy": 1.0, &"hunger": 1.0, &"bladder": 1.0, &"social": 1.0, &"security": 1.0}
	w.client.cognitive = {&"attention": 1.0, &"willpower": 1.0}
	w.client.overskudd = 100.0
	w.economy.capacity_max = 6.0
	w.economy.capacity_current = 6.0

func test_diagnostic_locked_fails_and_emits() -> void:
	watch_signals(EventBus)
	var d := _make_diag(&"d_locked", 1.0, 10.0, [&"need:never_seen"], [])
	var ok: bool = w._run_diagnostic_impl(d)
	assert_false(ok)
	assert_signal_emitted_with_parameters(EventBus, "action_failed", [&"locked"])

func test_diagnostic_no_capacity_fails() -> void:
	watch_signals(EventBus)
	w.economy.capacity_current = 0.5
	var d := _make_diag(&"d", 2.0, 10.0, [], [])
	assert_false(w._run_diagnostic_impl(d))
	assert_signal_emitted_with_parameters(EventBus, "action_failed", [&"no_capacity"])

func test_diagnostic_client_refuses_when_overskudd_short() -> void:
	watch_signals(EventBus)
	w.client.overskudd = 5.0
	var d := _make_diag(&"d", 1.0, 10.0, [], [])
	assert_false(w._run_diagnostic_impl(d))
	assert_signal_emitted_with_parameters(EventBus, "action_failed", [&"client_refuses"])

func test_diagnostic_success_deducts_and_emits() -> void:
	watch_signals(EventBus)
	var yield_entry := _make_entry(&"obs_from_diag", [&"mtg:blue"])
	var d := _make_diag(&"d_ok", 2.0, 15.0, [], [yield_entry])
	var ok: bool = w._run_diagnostic_impl(d)
	assert_true(ok)
	assert_almost_eq(w.economy.capacity_current, 4.0, 0.0001)
	assert_almost_eq(w.client.overskudd, 85.0, 0.0001)
	assert_true(w.case_file.has_entry(&"obs_from_diag"))
	assert_signal_emitted_with_parameters(EventBus, "diagnostic_completed", [&"d_ok"])
	assert_signal_emitted_with_parameters(EventBus, "case_file_updated", [&"obs_from_diag"])

func test_intervention_applies_needs_effects() -> void:
	var i := _make_int(&"i_walk", 1.0, 10.0, [], {&"energy": 0.2}, {})
	w.client.needs[&"energy"] = 0.5
	var ok: bool = w._run_intervention_impl(i)
	assert_true(ok)
	assert_almost_eq(w.client.needs[&"energy"], 0.7, 0.0001)

func test_intervention_applies_skill_effects_with_default_zero() -> void:
	var i := _make_int(&"i_phone", 1.0, 10.0, [], {}, {&"phone": 1})
	assert_eq(w.client.skills.get(&"phone", 0), 0)
	assert_true(w._run_intervention_impl(i))
	assert_eq(w.client.skills[&"phone"], 1)
	assert_true(w._run_intervention_impl(i))
	assert_eq(w.client.skills[&"phone"], 2)

func test_intervention_needs_effect_clamped_to_unit_interval() -> void:
	var i := _make_int(&"i_big", 1.0, 5.0, [], {&"energy": 5.0}, {})
	assert_true(w._run_intervention_impl(i))
	assert_almost_eq(w.client.needs[&"energy"], 1.0, 0.0001)

func test_intervention_emits_capacity_overskudd_and_completion() -> void:
	watch_signals(EventBus)
	var i := _make_int(&"i_ok", 1.0, 10.0, [], {}, {})
	assert_true(w._run_intervention_impl(i))
	assert_signal_emitted_with_parameters(EventBus, "intervention_completed", [&"i_ok"])
	assert_signal_emitted(EventBus, "caseworker_capacity_changed")
	assert_signal_emitted(EventBus, "overskudd_changed")

func test_intervention_applies_cognitive_effects() -> void:
	var i := Intervention.new()
	i.id = &"i_cog"
	i.caseworker_cost = 0.5
	i.overskudd_cost = 5.0
	i.cognitive_effects = {&"willpower": 0.1}
	w.client.cognitive[&"willpower"] = 0.5
	assert_true(w._run_intervention_impl(i))
	assert_almost_eq(w.client.cognitive[&"willpower"], 0.6, 0.0001)
