class_name MainUI extends Control

@onready var header_label: Label = %HeaderLabel
@onready var overskudd_bar: OverskuddBar = %OverskuddBar
@onready var capacity_label: CapacityLabel = %CapacityLabel
@onready var resource_label: Label = %ResourceLabel
@onready var action_log: RichTextLabel = %ActionLog
@onready var case_file_panel: CaseFilePanel = %CaseFilePanel
@onready var action_list: ActionList = %ActionList

func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.diagnostic_completed.connect(func(id: StringName) -> void: _log("✓ Diagnostic: %s" % id))
	EventBus.intervention_completed.connect(func(id: StringName) -> void: _log("✓ Intervention: %s" % id))
	EventBus.away_action_completed.connect(func(id: StringName) -> void: _log("↷ Away action: %s" % id))
	EventBus.return_report_ready.connect(_on_return_report_ready)
	EventBus.case_file_updated.connect(func(id: StringName) -> void: _log("📓 Case file: %s" % id))
	EventBus.action_failed.connect(func(reason: StringName) -> void: _log("⚠ Action failed: %s" % reason))
	EventBus.economy_resources_changed.connect(_on_economy_resources_changed)
	_refresh_header()
	_refresh_resources()
	set_process(true)

func _process(_delta: float) -> void:
	_refresh_header()

func _refresh_header() -> void:
	var time_str := "%02d:%02d" % [int(Clock.hour_of_day), int(fmod(Clock.hour_of_day, 1.0) * 60.0)]
	var speed := "⏸" if Clock.paused else "▶%d×" % int(Clock.time_scale)
	header_label.text = "Day %d  %s  %s" % [Clock.day, time_str, speed]

func _refresh_resources() -> void:
	if World.economy == null:
		return
	resource_label.text = "Trust %s  Dice %s  Knowledge %s" % [
		_fmt_amount(float(World.economy.resources.get(&"trust", 0.0))),
		_fmt_amount(float(World.economy.resources.get(&"dice", 0.0))),
		_fmt_amount(float(World.economy.resources.get(&"knowledge", 0.0))),
	]

func _on_economy_resources_changed(_resources: Dictionary, delta: Dictionary, _source_id: StringName) -> void:
	_refresh_resources()
	_log("◇ Resources: %s" % _format_resource_delta(delta))

func _on_day_started(day: int) -> void:
	_log("— Day %d —" % day)

func _on_day_ended(day: int) -> void:
	_log("— End of day %d —" % day)

func _on_return_report_ready(report: Dictionary) -> void:
	_log("⌂ Return report")
	for change: Variant in report.get("changes", []):
		_log("  - %s" % String(change))
	var next_decision := String(report.get("next_decision", ""))
	if next_decision != "":
		_log("  → %s" % next_decision)

func _log(line: String) -> void:
	action_log.append_text(line + "\n")

func _format_resource_delta(delta: Dictionary) -> String:
	var parts: Array[String] = []
	for key: StringName in [&"trust", &"dice", &"knowledge"]:
		var amount := float(delta.get(key, 0.0))
		if amount != 0.0:
			parts.append("%s %s" % [_resource_label(key), _fmt_signed_amount(amount)])
	return ", ".join(parts)

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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Clock.paused = not Clock.paused
		accept_event()
	elif event.is_action_pressed("speed_1"):
		Clock.time_scale = 1.0
	elif event.is_action_pressed("speed_2"):
		Clock.time_scale = 2.0
	elif event.is_action_pressed("speed_3"):
		Clock.time_scale = 4.0
