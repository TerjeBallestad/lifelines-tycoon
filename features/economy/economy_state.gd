class_name EconomyState extends RefCounted

var capacity_max: float = 6.0
var capacity_current: float = 6.0
var resources: Dictionary = {
    &"trust": 1.0,
    &"dice": 1.0,
    &"knowledge": 0.0,
}

func can_spend(hours: float) -> bool:
    return capacity_current >= hours

func spend(hours: float) -> bool:
    if not can_spend(hours): return false
    capacity_current -= hours
    return true

func refill_to_max() -> void:
    capacity_current = capacity_max

func can_spend_resources(costs: Dictionary, subsidies: Dictionary = {}) -> bool:
    for k: Variant in costs.keys():
        var key := _resource_key(k)
        var required: float = max(0.0, float(costs[k]) - float(subsidies.get(key, subsidies.get(String(key), 0.0))))
        if float(resources.get(key, 0.0)) < required:
            return false
    return true

func spend_resources(costs: Dictionary, subsidies: Dictionary = {}) -> Dictionary:
    var delta: Dictionary = {}
    if not can_spend_resources(costs, subsidies):
        return delta
    for k: Variant in costs.keys():
        var key := _resource_key(k)
        var required: float = max(0.0, float(costs[k]) - float(subsidies.get(key, subsidies.get(String(key), 0.0))))
        if required == 0.0:
            continue
        resources[key] = max(0.0, float(resources.get(key, 0.0)) - required)
        delta[key] = float(delta.get(key, 0.0)) - required
    return delta

func add_resources(effects: Dictionary) -> Dictionary:
    var delta: Dictionary = {}
    for k: Variant in effects.keys():
        var key := _resource_key(k)
        var amount: float = float(effects[k])
        if amount == 0.0:
            continue
        var before: float = float(resources.get(key, 0.0))
        resources[key] = max(0.0, before + amount)
        delta[key] = float(delta.get(key, 0.0)) + (float(resources[key]) - before)
    return delta

func apply_resource_delta(costs: Dictionary, effects: Dictionary, subsidies: Dictionary = {}, hidden_effects: Dictionary = {}) -> Dictionary:
    var delta := spend_resources(costs, subsidies)
    _merge_delta(delta, add_resources(effects))
    _merge_delta(delta, add_resources(hidden_effects))
    return delta

func _merge_delta(into: Dictionary, from: Dictionary) -> void:
    for k: Variant in from.keys():
        var key := _resource_key(k)
        into[key] = float(into.get(key, 0.0)) + float(from[k])

func _resource_key(key: Variant) -> StringName:
    return key if typeof(key) == TYPE_STRING_NAME else StringName(String(key))
