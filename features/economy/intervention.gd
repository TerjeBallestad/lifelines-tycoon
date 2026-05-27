class_name Intervention extends Resource

@export var id: StringName
@export var label: String
@export_multiline var description: String
@export var caseworker_cost: float = 1.0
@export var overskudd_cost: float = 15.0
@export var gate_tags: Array[StringName] = []
@export var needs_effects: Dictionary = {}
@export var skill_effects: Dictionary = {}
@export var cognitive_effects: Dictionary = {}
@export var resource_costs: Dictionary = {}
@export var resource_effects: Dictionary = {}
@export var hidden_resource_subsidies: Dictionary = {}
@export var hidden_resource_effects: Dictionary = {}
