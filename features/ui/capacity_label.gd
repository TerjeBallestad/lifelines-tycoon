class_name CapacityLabel extends Label

func _ready() -> void:
	EventBus.caseworker_capacity_changed.connect(_on_changed)
	EventBus.day_started.connect(func(_d: int) -> void: _refresh())
	_refresh()

func _on_changed(current: float, capacity_max: float) -> void:
	text = "Capacity %.1f / %.1fh" % [current, capacity_max]

func _refresh() -> void:
	if World.economy == null: return
	_on_changed(World.economy.capacity_current, World.economy.capacity_max)
