class_name ActionList extends VBoxContainer

func _ready() -> void:
	EventBus.case_file_updated.connect(func(_id: StringName) -> void: _rebuild())
	EventBus.caseworker_capacity_changed.connect(func(_c: float, _m: float) -> void: _rebuild())
	EventBus.overskudd_changed.connect(func(_id: StringName, _v: float) -> void: _rebuild())
	EventBus.day_started.connect(func(_d: int) -> void: _rebuild())
	_rebuild()

func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	if World.case_file == null or World.economy == null or World.client == null:
		return
	add_child(_section_label("Diagnostics"))
	for d: Diagnostic in Catalog.diagnostics.values():
		add_child(_build_diag_button(d))
	add_child(_section_label("Interventions"))
	for i: Intervention in Catalog.interventions.values():
		add_child(_build_int_button(i))

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	return l

func _build_diag_button(d: Diagnostic) -> Button:
	var b := Button.new()
	if not World.case_file.has_all_tags(d.gate_tags):
		b.text = "🔒 %s — missing %s" % [d.label, _first_missing_tag(d.gate_tags)]
		b.disabled = true
	elif not World.economy.can_spend(d.caseworker_cost):
		b.text = "%s  %.1fh %d⚡ (short %.1fh)" % [d.label, d.caseworker_cost, int(d.overskudd_cost), d.caseworker_cost - World.economy.capacity_current]
		b.disabled = true
	elif World.client.overskudd < d.overskudd_cost:
		b.text = "%s  %.1fh %d⚡ (Elling refuses)" % [d.label, d.caseworker_cost, int(d.overskudd_cost)]
		b.disabled = true
	else:
		b.text = "%s  %.1fh %d⚡" % [d.label, d.caseworker_cost, int(d.overskudd_cost)]
		b.pressed.connect(func() -> void: World.try_run_diagnostic(d.id))
	b.tooltip_text = d.description
	return b

func _build_int_button(i: Intervention) -> Button:
	var b := Button.new()
	if not World.case_file.has_all_tags(i.gate_tags):
		b.text = "🔒 %s — missing %s" % [i.label, _first_missing_tag(i.gate_tags)]
		b.disabled = true
	elif not World.economy.can_spend(i.caseworker_cost):
		b.text = "%s  %.1fh %d⚡ (short %.1fh)" % [i.label, i.caseworker_cost, int(i.overskudd_cost), i.caseworker_cost - World.economy.capacity_current]
		b.disabled = true
	elif World.client.overskudd < i.overskudd_cost:
		b.text = "%s  %.1fh %d⚡ (Elling refuses)" % [i.label, i.caseworker_cost, int(i.overskudd_cost)]
		b.disabled = true
	else:
		b.text = "%s  %.1fh %d⚡" % [i.label, i.caseworker_cost, int(i.overskudd_cost)]
		b.pressed.connect(func() -> void: World.try_assign_intervention(i.id))
	b.tooltip_text = i.description
	return b

func _first_missing_tag(required: Array[StringName]) -> StringName:
	for t: StringName in required:
		if not World.case_file.tags.has(t): return t
	return &""
