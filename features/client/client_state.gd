class_name ClientState extends RefCounted

var id: StringName
var display_name: String
var mtg_primary: StringName
var mtg_secondary: StringName

var needs: Dictionary = {
	&"energy":   1.0,
	&"hunger":   1.0,
	&"bladder":  1.0,
	&"social":   1.0,
	&"security": 1.0,
}

var cognitive: Dictionary = {
	&"attention": 1.0,
	&"willpower": 1.0,
}

var overskudd: float = 100.0
var overskudd_regen_rate: float = 8.0

var skills: Dictionary = {}
var mastery: Dictionary = {}

func mood() -> float:
	if needs.is_empty(): return 0.0
	var sum := 0.0
	for v: float in needs.values(): sum += v
	return sum / needs.size()

func cognitive_pool() -> float:
	if cognitive.is_empty(): return 0.0
	var sum := 0.0
	for v: float in cognitive.values(): sum += v
	return sum / cognitive.size()

func overskudd_ceiling() -> float:
	return clamp(100.0 * sqrt(mood() * cognitive_pool()), 0.0, 100.0)

func tick_overskudd(game_hours: float) -> void:
	var ceiling := overskudd_ceiling()
	if overskudd > ceiling:
		overskudd = ceiling
	else:
		overskudd = min(overskudd + overskudd_regen_rate * game_hours, ceiling)
