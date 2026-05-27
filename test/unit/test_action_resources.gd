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

func test_away_action_defaults() -> void:
	var a := AwayAction.new()
	a.id = &"away_test"
	a.label = "Away Test"
	a.caseworker_cost = 1.0
	a.away_hours = 3.0
	assert_eq(a.id, &"away_test")
	assert_eq(a.domain, &"apartment")
	assert_eq(a.away_hours, 3.0)

func test_scheduled_consequence_defaults() -> void:
	var c := ScheduledConsequence.new()
	c.id = &"consequence_test"
	c.label = "Consequence Test"
	c.due_after_hours = 2.0
	c.needs_effects = {&"security": -0.1}
	c.observation_id = &"obs_test"
	assert_eq(c.id, &"consequence_test")
	assert_eq(c.domain, &"apartment")
	assert_eq(c.needs_effects[&"security"], -0.1)

func test_schedule_queue_returns_due_items_without_frame_process() -> void:
	var c := ScheduledConsequence.new()
	c.id = &"consequence_test"
	c.domain = &"apartment"
	c.due_after_hours = 2.0

	var queue := ScheduleQueue.new()
	var item := queue.schedule_consequence_after(10.0, c, &"test_source")
	assert_eq(item.consequence_id, &"consequence_test")
	assert_eq(item.source_id, &"test_source")
	assert_almost_eq(item.due_at_hours, 12.0, 0.001)
	assert_eq(queue.pending_count(&"apartment"), 1)
	assert_eq(queue.due_between(&"apartment", 10.0, 11.9).size(), 0)
	assert_eq(queue.pending_count(&"apartment"), 1)
	var due := queue.due_between(&"apartment", 10.0, 12.0)
	assert_eq(due.size(), 1)
	assert_eq(due[0].id, item.id)
	assert_eq(queue.pending_count(&"apartment"), 0)
