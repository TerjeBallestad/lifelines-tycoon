class_name ClientDecay extends Resource

@export var needs_per_hour: Dictionary = {
    &"energy":   -0.003,
    &"hunger":   -0.005,
    &"bladder":  -0.004,
    &"social":   -0.001,
    &"security": -0.002,
}

@export var cognitive_per_hour: Dictionary = {
    &"attention":  0.02,
    &"willpower": -0.003,
}
