extends Node

signal day_started(day: int)
signal day_ended(day: int)
signal overskudd_changed(client_id: StringName, value: float)
signal caseworker_capacity_changed(current: float, max: float)
signal economy_resources_changed(resources: Dictionary, delta: Dictionary, source_id: StringName)
signal case_file_updated(entry_id: StringName)
signal diagnostic_completed(id: StringName)
signal intervention_completed(id: StringName)
signal away_action_completed(id: StringName)
signal return_report_ready(report: Dictionary)
signal action_failed(reason: StringName)
## Day-end Lens pass result: the uncovered-behaviour summary (activity_id -> count of
## history records no PatternRule matched). Emitted once per day rollover by
## World.evaluate_patterns_for_day_end; agent_bridge streams it to events.jsonl for the
## standalone blind-read gate. Designer/gate-facing only — no live UI consumer.
signal patterns_evaluated(uncovered: Dictionary)
signal tick(game_hours: float)
signal speed_changed(scale: float)
signal pause_changed(paused: bool)
