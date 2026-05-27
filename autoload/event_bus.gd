extends Node

signal day_started(day: int)
signal day_ended(day: int)
signal overskudd_changed(client_id: StringName, value: float)
signal caseworker_capacity_changed(current: float, max: float)
signal case_file_updated(entry_id: StringName)
signal diagnostic_completed(id: StringName)
signal intervention_completed(id: StringName)
signal away_action_completed(id: StringName)
signal return_report_ready(report: Dictionary)
signal action_failed(reason: StringName)
signal tick(game_hours: float)
