class_name MainUI extends Control

@onready var header_label: Label = %HeaderLabel
@onready var overskudd_bar: OverskuddBar = %OverskuddBar
@onready var capacity_label: CapacityLabel = %CapacityLabel
@onready var action_log: RichTextLabel = %ActionLog
@onready var case_file_panel: CaseFilePanel = %CaseFilePanel
@onready var action_list: ActionList = %ActionList

func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)
	EventBus.day_ended.connect(_on_day_ended)
	EventBus.diagnostic_completed.connect(func(id: StringName) -> void: _log("✓ Diagnostic: %s" % id))
	EventBus.intervention_completed.connect(func(id: StringName) -> void: _log("✓ Intervention: %s" % id))
	EventBus.case_file_updated.connect(func(id: StringName) -> void: _log("📓 Case file: %s" % id))
	EventBus.action_failed.connect(func(reason: StringName) -> void: _log("⚠ Action failed: %s" % reason))
	_refresh_header()
	set_process(true)

func _process(_delta: float) -> void:
	_refresh_header()

func _refresh_header() -> void:
	var time_str := "%02d:%02d" % [int(Clock.hour_of_day), int(fmod(Clock.hour_of_day, 1.0) * 60.0)]
	var speed := "⏸" if Clock.paused else "▶%d×" % int(Clock.time_scale)
	header_label.text = "Day %d  %s  %s" % [Clock.day, time_str, speed]

func _on_day_started(day: int) -> void:
	_log("— Day %d —" % day)

func _on_day_ended(day: int) -> void:
	_log("— End of day %d —" % day)

func _log(line: String) -> void:
	action_log.append_text(line + "\n")

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
