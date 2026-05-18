class_name EconomyState extends RefCounted

var capacity_max: float = 6.0
var capacity_current: float = 6.0

func can_spend(hours: float) -> bool:
    return capacity_current >= hours

func spend(hours: float) -> bool:
    if not can_spend(hours): return false
    capacity_current -= hours
    return true

func refill_to_max() -> void:
    capacity_current = capacity_max
