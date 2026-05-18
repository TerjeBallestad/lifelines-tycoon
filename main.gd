extends Node

func _ready() -> void:
	var ui: PackedScene = load("res://features/ui/main_ui.tscn")
	add_child(ui.instantiate())
	EventBus.day_started.emit(Clock.day)
	Sim.start()  # Sim.start() also starts Clock
