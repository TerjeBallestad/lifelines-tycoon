extends Node

const ELLING_INIT_PATH := "res://features/client/elling_init.tres"
const CLIENT_DECAY_PATH := "res://features/client/client_decay.tres"

# CA reproducibility seed slot. main.gd._apply_cli_flags() parses the
# `--seed <int>` CLI flag into this field BEFORE Sim/World boot, so CAEngine
# (a later task) can seed its OWN private RandomNumberGenerator from it at its
# first tick. We deliberately do NOT call the global seed() — this value is for
# CAEngine to consume into a private RNG, keeping CA history reproducible
# without coupling the rest of the engine to a global RNG state. 0 = unset.
var ca_seed: int = 0

var client: ClientState
var case_file: CaseFile
var economy: EconomyState
var decay: ClientDecay
var schedule_queue: ScheduleQueue
var _pending_return_report: Dictionary = {}

# Append-only activity history owned by World — the stable seam between the
# living sim and the Lens (per the ownership decision: World owns history;
# CAEngine/Sim WRITE via append_activity_record(); PatternDeriver READS via the
# read-only get_activity_history() query). This is the ONLY history coupling
# point PatternDeriver depends on, keeping the Lens off CAEngine internals.
# Each record is a Dictionary:
#   {day:int, step:int, activity_id:StringName,
#    needs_snapshot:Dictionary, mastery_snapshot:Dictionary}
var _activity_history: Array = []

# OWNERSHIP DECISION: World owns the PatternDeriver (the Lens). World already owns
# case_file (where derived traces land) and the activity history (the seam the Lens
# reads), so it is the natural owner — the deriver is constructed with a back-ref to
# World and lives for the World's lifetime. Sim does NOT own it: Sim drives time and
# merely triggers an evaluation on the day boundary (see Sim._on_day_started, which
# calls World.evaluate_patterns_for_day_end after World.start_new_day). Rebuilt on
# reset_for_test so a fresh case_file/history pairs with a fresh (un-fired) deriver.
var _pattern_deriver: PatternDeriver

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
    _activity_history = []
    schedule_queue = ScheduleQueue.new()
    _seed_initial_schedule()
    _pattern_deriver = PatternDeriver.new(self)

# Read-only accessor for the owned Lens. Exposed so tests (and only tests / the day
# hook) can observe the deriver; runtime code triggers it via evaluate_patterns_for_day_end.
func pattern_deriver() -> PatternDeriver:
    return _pattern_deriver

# Test-only seam: swap in a PatternDeriver double (e.g. a counting spy) so the cadence
# test can assert evaluate() runs exactly once per day-end. Production code never calls
# this; it only sets the same field reset_for_test populates.
func set_pattern_deriver_for_test(deriver: PatternDeriver) -> void:
    _pattern_deriver = deriver

# DAY-END LENS PASS. Called once per day rollover from Sim._on_day_started (after
# start_new_day) — NOT per tick. Runs the Lens over the whole activity history, then
# emits the uncovered-behaviour summary on EventBus so agent_bridge can stream it to
# events.jsonl for the standalone blind-read gate. This is a designer/gate-facing
# channel only: it touches no live UI node and cannot block the UI thread (a pure
# signal emit drained asynchronously by agent_bridge.pump()).
func evaluate_patterns_for_day_end() -> void:
    _pattern_deriver.evaluate(get_activity_history())
    EventBus.patterns_evaluated.emit(_pattern_deriver.get_uncovered_summary())

# Write seam: CAEngine/Sim push one activity record per CA decision step. We
# deep-duplicate on the way in so the caller cannot later mutate the stored
# record through a retained reference to its nested needs/mastery snapshots.
func append_activity_record(record: Dictionary) -> void:
    _activity_history.append(record.duplicate(true))

# Read-only query: PatternDeriver consumes this. Returns a deep duplicate of the
# whole history so callers cannot mutate internal records — neither the outer
# array nor the nested needs_snapshot/mastery_snapshot dictionaries are shared.
func get_activity_history() -> Array:
    return _activity_history.duplicate(true)

func scheduled_consequence_count(domain: StringName = &"") -> int:
    return schedule_queue.pending_count(domain)

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
    var pending := _pending_schedule_preview(action.domain)
    var report := _build_return_report(action, before, _snapshot_for_report(), events, pending)
    _pending_return_report = _merge_return_reports(_pending_return_report, report)
    EventBus.away_action_completed.emit(action.id)
    return true

func return_to_apartment() -> Dictionary:
    if _pending_return_report.is_empty():
        return {
            "has_delta": false,
            "changes": [],
            "events": [],
            "pending": _pending_schedule_preview(&"apartment"),
            "why": "No away-time action has changed the apartment since the last return.",
            "next_decision": "Choose a desk action or inspect Elling at home before spending capacity.",
        }
    var report := _pending_return_report.duplicate(true)
    _pending_return_report = {}
    EventBus.return_report_ready.emit(report)
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
    if not economy.can_spend_resources(i.resource_costs, i.hidden_resource_subsidies):
        EventBus.action_failed.emit(&"no_resources")
        return false
    economy.spend(i.caseworker_cost)
    client.overskudd = max(0.0, client.overskudd - i.overskudd_cost)
    var resource_delta := economy.apply_resource_delta(i.resource_costs, i.resource_effects, i.hidden_resource_subsidies, i.hidden_resource_effects)
    if not resource_delta.is_empty():
        EventBus.economy_resources_changed.emit(economy.resources.duplicate(true), resource_delta, i.id)
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

func start_new_day(day: int, chosen_activity_ids: Array = []) -> void:
    economy.refill_to_max()
    EventBus.caseworker_capacity_changed.emit(economy.capacity_current, economy.capacity_max)
    _apply_overnight_reset(chosen_activity_ids)

# CA overnight reset (sandbox sleep step). Sleep restores energy and partially
# relieves hunger/bladder; social/security PERSIST (no overnight reset). Mastery for
# every activity NOT chosen that day decays by the CA decay factor (skill fade). The
# factor mirrors CAEngine.DECAY_FACTOR (0.905); kept as a literal so this autoload
# takes no compile-time static dependency on the CAEngine class (whose own reload
# under the project's untyped_declaration=2 lint must not be dragged into autoload load).
const CA_MASTERY_DECAY_FACTOR := 0.905

func _apply_overnight_reset(chosen_activity_ids: Array) -> void:
    var needs := client.needs
    needs[&"energy"] = min(1.0, float(needs.get(&"energy", 0.0)) + 0.85)
    needs[&"hunger"] = max(0.0, float(needs.get(&"hunger", 0.0)) - 0.30)
    needs[&"bladder"] = max(0.0, float(needs.get(&"bladder", 0.0)) - 0.35)
    var chosen := {}
    for id: Variant in chosen_activity_ids:
        chosen[id] = true
    for activity_id: Variant in client.mastery.keys():
        if not chosen.has(activity_id):
            client.mastery[activity_id] = float(client.mastery[activity_id]) * CA_MASTERY_DECAY_FACTOR

func _seed_initial_schedule() -> void:
    for consequence: ScheduledConsequence in Catalog.consequences.values():
        schedule_queue.schedule_consequence_after(Clock.total_game_hours, consequence, &"initial_schedule")

func _resolve_due_consequences(domain: StringName, start_hour: float, end_hour: float) -> Array[Dictionary]:
    var resolved: Array[Dictionary] = []
    for item: ScheduledItem in schedule_queue.due_between(domain, start_hour, end_hour):
        var consequence := Catalog.consequences.get(item.consequence_id) as ScheduledConsequence
        if consequence != null:
            resolved.append(_apply_consequence(item, consequence))
    return resolved

func _apply_consequence(item: ScheduledItem, consequence: ScheduledConsequence) -> Dictionary:
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
        "scheduled_item_id": String(item.id),
        "source_id": String(item.source_id),
        "due_at_hours": item.due_at_hours,
        "title": consequence.label,
        "observation_id": String(observation_id),
        "summary": consequence.summary,
    }

func _pending_schedule_preview(domain: StringName) -> Array[Dictionary]:
    var pending: Array[Dictionary] = []
    for item: ScheduledItem in schedule_queue.peek(domain, 3):
        var consequence := Catalog.consequences.get(item.consequence_id) as ScheduledConsequence
        pending.append({
            "id": String(item.id),
            "consequence_id": String(item.consequence_id),
            "source_id": String(item.source_id),
            "due_at_hours": item.due_at_hours,
            "hours_from_now": max(0.0, item.due_at_hours - Clock.total_game_hours),
            "title": consequence.label if consequence != null else String(item.consequence_id),
        })
    return pending

func _build_return_report(action: AwayAction, before: Dictionary, after: Dictionary, events: Array[Dictionary], pending: Array[Dictionary]) -> Dictionary:
    var changes: Array[String] = [
        "Caseworker capacity %.1f -> %.1f." % [before.get("capacity", 0.0), after.get("capacity", 0.0)],
    ]
    for event: Dictionary in events:
        changes.append(String(event.get("summary", "A scheduled consequence resolved.")))
    return {
        "has_delta": true,
        "cause_id": String(action.id),
        "cause_ids": [String(action.id)],
        "away_hours": action.away_hours,
        "domain": String(action.domain),
        "events": events.duplicate(true),
        "pending": pending.duplicate(true),
        "changes": changes,
        "why": action.report_why,
        "next_decision": action.next_decision_hint,
    }

func _merge_return_reports(existing: Dictionary, incoming: Dictionary) -> Dictionary:
    if existing.is_empty() or not bool(existing.get("has_delta", false)):
        return incoming.duplicate(true)
    var merged := existing.duplicate(true)
    var cause_ids: Array = merged.get("cause_ids", [])
    if cause_ids.is_empty() and merged.has("cause_id"):
        cause_ids.append(String(merged.get("cause_id", "")))
    for cause_id: Variant in incoming.get("cause_ids", [incoming.get("cause_id", "")]):
        cause_ids.append(String(cause_id))
    merged["cause_ids"] = cause_ids
    merged["cause_id"] = String(cause_ids[cause_ids.size() - 1])
    merged["away_hours"] = float(merged.get("away_hours", 0.0)) + float(incoming.get("away_hours", 0.0))
    var changes: Array = merged.get("changes", [])
    changes.append_array(incoming.get("changes", []))
    merged["changes"] = changes
    var events: Array = merged.get("events", [])
    events.append_array(incoming.get("events", []))
    merged["events"] = events
    merged["pending"] = incoming.get("pending", []).duplicate(true)
    merged["next_decision"] = incoming.get("next_decision", merged.get("next_decision", ""))
    return merged

func _snapshot_for_report() -> Dictionary:
    return {
        "capacity": economy.capacity_current,
    }
