class_name ScheduledConsequence extends Resource

@export var id: StringName
@export var label: String
@export var domain: StringName = &"apartment"
@export var due_after_hours: float = 1.0
@export var needs_effects: Dictionary = {}
@export var observation_id: StringName
@export_multiline var summary: String = "Something changed while attention was elsewhere."
