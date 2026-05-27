class_name AwayAction extends Resource

@export var id: StringName
@export var label: String
@export_multiline var description: String
@export var caseworker_cost: float = 1.0
@export var away_hours: float = 1.0
@export var domain: StringName = &"apartment"
@export_multiline var report_why: String = "Time passed away from the apartment."
@export_multiline var next_decision_hint: String = "Return home, or spend more attention elsewhere."
