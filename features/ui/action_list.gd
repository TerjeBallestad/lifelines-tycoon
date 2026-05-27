class_name ActionList extends VBoxContainer

func _ready() -> void:
	EventBus.case_file_updated.connect(func(_id: StringName) -> void: _rebuild())
	EventBus.caseworker_capacity_changed.connect(func(_c: float, _m: float) -> void: _rebuild())
	EventBus.overskudd_changed.connect(func(_id: StringName, _v: float) -> void: _rebuild())
	EventBus.economy_resources_changed.connect(func(_resources: Dictionary, _delta: Dictionary, _source_id: StringName) -> void: _rebuild())
	EventBus.day_started.connect(func(_d: int) -> void: _rebuild())
	_rebuild()

func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	if World.case_file == null or World.economy == null or World.client == null:
		return
	add_child(_section_label("Away actions"))
	for a: AwayAction in Catalog.away_actions.values():
		add_child(_build_away_button(a))
	add_child(_build_return_button())
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

func _build_away_button(a: AwayAction) -> Button:
	var b := Button.new()
	if not World.economy.can_spend(a.caseworker_cost):
		b.text = "%s  %.1fh / %.1fh away (short %.1fh)" % [a.label, a.caseworker_cost, a.away_hours, a.caseworker_cost - World.economy.capacity_current]
		b.disabled = true
	else:
		b.text = "%s  %.1fh / %.1fh away" % [a.label, a.caseworker_cost, a.away_hours]
		b.pressed.connect(func() -> void: World.try_run_away_action(a.id))
	b.tooltip_text = a.description
	return b

func _build_return_button() -> Button:
	var b := Button.new()
	b.text = "Return to apartment"
	b.pressed.connect(func() -> void: World.return_to_apartment())
	return b

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
	var resource_text := _resource_text(i.resource_costs, i.resource_effects)
	var base_text := "%s  %.1fh %d⚡%s" % [i.label, i.caseworker_cost, int(i.overskudd_cost), resource_text]
	if not World.case_file.has_all_tags(i.gate_tags):
		b.text = "🔒 %s — missing %s" % [base_text, _first_missing_tag(i.gate_tags)]
		b.disabled = true
	elif not World.economy.can_spend(i.caseworker_cost):
		b.text = "%s (short %.1fh)" % [base_text, i.caseworker_cost - World.economy.capacity_current]
		b.disabled = true
	elif World.client.overskudd < i.overskudd_cost:
		b.text = "%s (Elling refuses)" % base_text
		b.disabled = true
	elif not World.economy.can_spend_resources(i.resource_costs, i.hidden_resource_subsidies):
		b.text = "%s (short resources)" % base_text
		b.disabled = true
	else:
		b.text = base_text
		b.pressed.connect(func() -> void: World.try_assign_intervention(i.id))
	b.tooltip_text = i.description
	return b

func _first_missing_tag(required: Array[StringName]) -> StringName:
	for t: StringName in required:
		if not World.case_file.tags.has(t): return t
	return &""

func _resource_text(costs: Dictionary, effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key: StringName in [&"trust", &"dice", &"knowledge"]:
		var cost := float(costs.get(key, 0.0))
		if cost != 0.0:
			parts.append("%s -%s" % [_resource_label(key), _fmt_amount(cost)])
		var effect := float(effects.get(key, 0.0))
		if effect != 0.0:
			parts.append("%s %s" % [_resource_label(key), _fmt_signed_amount(effect)])
	if parts.is_empty():
		return ""
	return "  [%s]" % ", ".join(parts)

func _resource_label(key: StringName) -> String:
	match key:
		&"trust": return "Trust"
		&"dice": return "Dice"
		&"knowledge": return "Knowledge"
		_: return String(key).capitalize()

func _fmt_signed_amount(value: float) -> String:
	var sign := "+" if value > 0.0 else ""
	return sign + _fmt_amount(value)

func _fmt_amount(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value
