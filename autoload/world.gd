extends Node

const ELLING_INIT_PATH := "res://features/client/elling_init.tres"
const CLIENT_DECAY_PATH := "res://features/client/client_decay.tres"
const DESK_BACKLOG_ACTION_ID := &"desk_nav_backlog"
const DESK_BACKLOG_AWAY_HOURS := 3.0
const DESK_BACKLOG_CAPACITY_COST := 1.0
const APARTMENT_PHONE_EVENT_ID := &"apt_phone_window"
const APARTMENT_PHONE_EVENT_DELAY_HOURS := 2.0
const APARTMENT_PHONE_OBSERVATION_ID := &"obs_phone_unanswered"

var client: ClientState
var case_file: CaseFile
var economy: EconomyState
var decay: ClientDecay
var _apartment_events: Array[Dictionary] = []
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
    _apartment_events = [{
        "id": APARTMENT_PHONE_EVENT_ID,
        "due_at": Clock.total_game_hours + APARTMENT_PHONE_EVENT_DELAY_HOURS,
        "observation_id": APARTMENT_PHONE_OBSERVATION_ID,
    }]

func scheduled_apartment_event_count() -> int:
    return _apartment_events.size()

func try_process_desk_backlog() -> bool:
    if not economy.can_spend(DESK_BACKLOG_CAPACITY_COST):
        EventBus.action_failed.emit(&"no_capacity")
        return false
    var before := _snapshot_for_report()
    var start_hour := Clock.total_game_hours
    economy.spend(DESK_BACKLOG_CAPACITY_COST)
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    Sim.advance_away_time(DESK_BACKLOG_AWAY_HOURS)
    var events := _resolve_due_apartment_events(start_hour, Clock.total_game_hours)
    _pending_return_report = _build_return_report(before, _snapshot_for_report(), events)
    return true

func return_to_apartment() -> Dictionary:
    if _pending_return_report.is_empty():
        return {
            "has_delta": false,
            "changes": [],
            "events": [],
            "why": "No away-time desk action has changed the apartment since the last return.",
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

func _resolve_due_apartment_events(start_hour: float, end_hour: float) -> Array[Dictionary]:
    var resolved: Array[Dictionary] = []
    var remaining: Array[Dictionary] = []
    for event: Dictionary in _apartment_events:
        var due_at := float(event.get("due_at", 0.0))
        if due_at > start_hour and due_at <= end_hour:
            resolved.append(_resolve_apartment_event(event))
        else:
            remaining.append(event)
    _apartment_events = remaining
    return resolved

func _resolve_apartment_event(event: Dictionary) -> Dictionary:
    client.needs[&"social"] = clamp(float(client.needs.get(&"social", 0.0)) - 0.04, 0.0, 1.0)
    client.needs[&"security"] = clamp(float(client.needs.get(&"security", 0.0)) - 0.06, 0.0, 1.0)
    var observation_id: StringName = event.get("observation_id", &"")
    var entry := Catalog.observations.get(observation_id) as CaseEntry
    if entry != null:
        case_file.add_entry(entry)
        EventBus.case_file_updated.emit(entry.id)
    return {
        "id": String(event.get("id", &"")),
        "title": "Phone unanswered",
        "observation_id": String(observation_id),
        "summary": "Phone unanswered: Elling watched the line ring out while you were at the desk.",
    }

func _build_return_report(before: Dictionary, after: Dictionary, events: Array[Dictionary]) -> Dictionary:
    var changes: Array[String] = [
        "Desk capacity %.1f -> %.1f." % [before.get("capacity", 0.0), after.get("capacity", 0.0)],
    ]
    for event: Dictionary in events:
        changes.append(String(event.get("summary", "Apartment event resolved.")))
    return {
        "has_delta": true,
        "cause_id": String(DESK_BACKLOG_ACTION_ID),
        "away_hours": DESK_BACKLOG_AWAY_HOURS,
        "events": events.duplicate(true),
        "changes": changes,
        "why": "A scheduled apartment phone call came due while attention stayed at the desk.",
        "next_decision": "Use Phone Call Practice now, or keep the caseworker hour for diagnostics and risk the next call landing the same way.",
    }

func _snapshot_for_report() -> Dictionary:
    return {
        "capacity": economy.capacity_current,
    }
