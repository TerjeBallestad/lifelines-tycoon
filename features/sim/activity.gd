class_name Activity extends Resource

## A CA (cellular-automaton living-sim) activity, mirroring the sandbox ACTIVITIES table
## (prototypes / playgrounds/full_ca_sandbox.html). Pure content type — no behavior.
##
## EFFECT UNITS: effects are stored in NATIVE 0-1 units, NOT the sandbox's raw /100
## scale. The sandbox stored e.g. `hunger: 60`; here that is `hunger: 0.6`. The /100
## conversion is absorbed into the authored data. Effects may be negative for drains
## (sandbox `energy: -3` → `energy: -0.03`).
##
## COLOR VECTOR: `colors` is a 5-float MTG-style identity vector. Index order is fixed:
##   [0] White, [1] Blue, [2] Black, [3] Red, [4] Green.

@export var id: StringName
@export var display_name: String

## 5 floats, index order [White, Blue, Black, Red, Green].
@export var colors: Array = []

## need StringName -> float effect, in NATIVE 0-1 units (may be negative for drains).
@export var effects: Dictionary = {}

@export var difficulty: float = 0.0

## One of &"FLOW", &"TASK", &"NEED".
@export var model: StringName

@export var start_mastery: float = 0.0
