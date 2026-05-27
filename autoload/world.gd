extends Node

const ELLING_INIT_PATH := "res://features/client/elling_init.tres"
const CLIENT_DECAY_PATH := "res://features/client/client_decay.tres"

var client: ClientState
var case_file: CaseFile
var economy: EconomyState
var decay: ClientDecay
var _scheduled_consequences: Array[Dictionary] = []
var _pending_return_report: Dictionary = {}

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
    var loaded_decay := load(CLIENT_DECAY_PATH) as ClientDecay
    decay = loaded_decay if loaded_decay != null else ClientDecay.new()
    _pending_return_report = {}
    _scheduled_consequences = _instantiate_consequences()

func scheduled_consequence_count(domain: StringName = &"") -> int:
    if domain == &"":
        return _scheduled_consequences.size()
    var count := 0
    for scheduled: Dictionary in _scheduled_consequences:
        var consequence := scheduled.get("consequence") as ScheduledConsequence
        if consequence != null and consequence.domain == domain:
            count += 1
    return count

func try_process_desk_backlog() -> bool:
    return try_run_away_action(&"desk_nav_backlog")

func try_run_away_action(id: StringName) -> bool:
    var action := Catalog.away_actions.get(id) as AwayAction
    if action == null:
        EventBus.action_failed.emit(&"unknown_id")
        return false
    return _run_away_action_impl(action)

func _run_away_action_impl(action: AwayAction) -> bool:
    if not economy.can_spend(action.caseworker_cost):
        EventBus.action_failed.emit(&"no_capacity")
        return false
    var before := _snapshot_for_report()
    var start_hour := Clock.total_game_hours
    economy.spend(action.caseworker_cost)
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    Sim.advance_away_time(action.away_hours)
    var events := _resolve_due_consequences(action.domain, start_hour, Clock.total_game_hours)
    _pending_return_report = _build_return_report(action, before, _snapshot_for_report(), events)
    return true

func return_to_apartment() -> Dictionary:
    if _pending_return_report.is_empty():
        return {
            "has_delta": false,
            "changes": [],
            "events": [],
            "why": "No away-time action has changed the apartment since the last return.",
            "next_decision": "Choose a desk action or inspect Elling at home before spending capacity.",
        }
    var report := _pending_return_report.duplicate(true)
    _pending_return_report = {}
    return report

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
    for k: StringName in i.cognitive_effects.keys():
        var cur_c: float = client.cognitive.get(k, 0.0)
        client.cognitive[k] = clamp(cur_c + float(i.cognitive_effects[k]), 0.0, 1.0)
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

func _instantiate_consequences() -> Array[Dictionary]:
    var scheduled: Array[Dictionary] = []
    for consequence: ScheduledConsequence in Catalog.consequences.values():
        scheduled.append({
            "id": consequence.id,
            "due_at": Clock.total_game_hours + consequence.due_after_hours,
            "consequence": consequence,
        })
    return scheduled

func _resolve_due_consequences(domain: StringName, start_hour: float, end_hour: float) -> Array[Dictionary]:
    var resolved: Array[Dictionary] = []
    var remaining: Array[Dictionary] = []
    for scheduled: Dictionary in _scheduled_consequences:
        var consequence := scheduled.get("consequence") as ScheduledConsequence
        var due_at := float(scheduled.get("due_at", 0.0))
        if consequence != null and consequence.domain == domain and due_at > start_hour and due_at <= end_hour:
            resolved.append(_apply_consequence(consequence))
        else:
            remaining.append(scheduled)
    _scheduled_consequences = remaining
    return resolved

func _apply_consequence(consequence: ScheduledConsequence) -> Dictionary:
    for k: StringName in consequence.needs_effects.keys():
        var cur: float = client.needs.get(k, 0.0)
        client.needs[k] = clamp(cur + float(consequence.needs_effects[k]), 0.0, 1.0)
    var observation_id := consequence.observation_id
    var entry := Catalog.observations.get(observation_id) as CaseEntry
    if entry != null:
        case_file.add_entry(entry)
        EventBus.case_file_updated.emit(entry.id)
    return {
        "id": String(consequence.id),
        "title": consequence.label,
        "observation_id": String(observation_id),
        "summary": consequence.summary,
    }

func _build_return_report(action: AwayAction, before: Dictionary, after: Dictionary, events: Array[Dictionary]) -> Dictionary:
    var changes: Array[String] = [
        "Caseworker capacity %.1f -> %.1f." % [before.get("capacity", 0.0), after.get("capacity", 0.0)],
    ]
    for event: Dictionary in events:
        changes.append(String(event.get("summary", "A scheduled consequence resolved.")))
    return {
        "has_delta": true,
        "cause_id": String(action.id),
        "away_hours": action.away_hours,
        "domain": String(action.domain),
        "events": events.duplicate(true),
        "changes": changes,
        "why": action.report_why,
        "next_decision": action.next_decision_hint,
    }

func _snapshot_for_report() -> Dictionary:
    return {
        "capacity": economy.capacity_current,
    }
