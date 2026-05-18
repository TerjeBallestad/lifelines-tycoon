extends Node

const ELLING_INIT_PATH := "res://features/client/elling_init.tres"

var client: ClientState
var case_file: CaseFile
var economy: EconomyState
var decay: ClientDecay

func _ready() -> void:
    reset_for_test()

func reset_for_test() -> void:
    client = ClientState.new()
    var init: ClientInitData = load(ELLING_INIT_PATH) as ClientInitData
    if init != null:
        client.apply_init_data(init)
    else:
        # fallback for tests that run before content lands
        client.id = &"elling"
        client.display_name = "Elling Pettersen"
    case_file = CaseFile.new()
    economy = EconomyState.new()
    decay = ClientDecay.new()

func try_run_diagnostic(id: StringName) -> bool:
    var d: Diagnostic = Catalog.diagnostics.get(id)
    if d == null:
        EventBus.action_failed.emit(&"unknown_id")
        return false
    return _run_diagnostic_impl(d)

func _run_diagnostic_impl(d: Diagnostic) -> bool:
    if not case_file.has_all_tags(d.gate_tags):
        EventBus.action_failed.emit(&"locked")
        return false
    if not economy.can_spend(d.caseworker_cost):
        EventBus.action_failed.emit(&"no_capacity")
        return false
    if client.overskudd < d.overskudd_cost:
        EventBus.action_failed.emit(&"client_refuses")
        return false
    economy.spend(d.caseworker_cost)
    client.overskudd = max(0.0, client.overskudd - d.overskudd_cost)
    for entry: CaseEntry in d.yields:
        case_file.add_entry(entry)
        EventBus.case_file_updated.emit(entry.id)
    EventBus.diagnostic_completed.emit(d.id)
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    EventBus.overskudd_changed.emit(client.id, client.overskudd)
    return true

func try_assign_intervention(id: StringName) -> bool:
    var i: Intervention = Catalog.interventions.get(id)
    if i == null:
        EventBus.action_failed.emit(&"unknown_id")
        return false
    return _run_intervention_impl(i)

func _run_intervention_impl(i: Intervention) -> bool:
    if not case_file.has_all_tags(i.gate_tags):
        EventBus.action_failed.emit(&"locked")
        return false
    if not economy.can_spend(i.caseworker_cost):
        EventBus.action_failed.emit(&"no_capacity")
        return false
    if client.overskudd < i.overskudd_cost:
        EventBus.action_failed.emit(&"client_refuses")
        return false
    economy.spend(i.caseworker_cost)
    client.overskudd = max(0.0, client.overskudd - i.overskudd_cost)
    for k: StringName in i.needs_effects.keys():
        var cur: float = client.needs.get(k, 0.0)
        client.needs[k] = clamp(cur + float(i.needs_effects[k]), 0.0, 1.0)
    for k: StringName in i.skill_effects.keys():
        client.skills[k] = int(client.skills.get(k, 0)) + int(i.skill_effects[k])
    EventBus.intervention_completed.emit(i.id)
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    EventBus.overskudd_changed.emit(client.id, client.overskudd)
    return true

func start_new_day(day: int) -> void:
    economy.refill_to_max()
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    EventBus.day_started.emit(day)

func try_surface_observation() -> CaseEntry:
    var candidates: Array[CaseEntry] = Catalog.observation_candidates(client, case_file)
    if candidates.is_empty(): return null
    var pick: CaseEntry = candidates[randi() % candidates.size()]
    case_file.add_entry(pick)
    EventBus.case_file_updated.emit(pick.id)
    return pick
