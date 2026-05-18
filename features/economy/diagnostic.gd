class_name Diagnostic extends Resource

@export var id: StringName
@export var label: String
@export_multiline var description: String
@export var caseworker_cost: float = 2.0
@export var overskudd_cost: float = 20.0
@export var gate_tags: Array[StringName] = []
@export var yields: Array[CaseEntry] = []
