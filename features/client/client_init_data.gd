class_name ClientInitData extends Resource

@export var id: StringName
@export var display_name: String
@export var mtg_primary: StringName
@export var mtg_secondary: StringName
@export var needs: Dictionary = {}
@export var cognitive: Dictionary = {}
@export var overskudd: float = 100.0
@export var overskudd_regen_rate: float = 8.0
@export var skills: Dictionary = {}

## FROZEN Elling starting mastery: activity-id StringName -> float [0,1].
## Per-activity overrides authored here; the CAEngine init (Task 6) reads this and
## falls back to each Activity's own start_mastery (NEED-model activities → 0.9) for
## any activity not listed. Keys are the Activity .tres ids (e.g. &"act_use_telescope").
@export var mastery: Dictionary = {}

## 5-float MTG-style color-identity vector, index order [White, Blue, Black, Red, Green].
## This is the hidden truth of the client (Task 14 re-points it). Elling = [0,0.8,0,0,0.4].
@export var colors: Array = []
