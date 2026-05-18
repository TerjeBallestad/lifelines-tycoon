extends GutTest

func test_diagnostic_defaults() -> void:
	var d := Diagnostic.new()
	d.id = &"diag_test"
	d.label = "Test Diag"
	d.caseworker_cost = 2.5
	d.overskudd_cost = 15.0
	d.gate_tags = [&"mtg:blue"]
	assert_eq(d.id, &"diag_test")
	assert_eq(d.gate_tags, [&"mtg:blue"])
	assert_eq(d.yields, [])

func test_intervention_defaults() -> void:
	var i := Intervention.new()
	i.id = &"int_test"
	i.label = "Test Int"
	i.caseworker_cost = 1.0
	i.overskudd_cost = 10.0
	i.needs_effects = {&"energy": 0.2}
	i.skill_effects = {&"phone": 1}
	assert_eq(i.id, &"int_test")
	assert_eq(i.needs_effects[&"energy"], 0.2)
	assert_eq(i.skill_effects[&"phone"], 1)
