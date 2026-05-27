extends Node

const DIAGNOSTICS_DIR := "res://features/economy/diagnostics"
const INTERVENTIONS_DIR := "res://features/economy/interventions"
const AWAY_ACTIONS_DIR := "res://features/economy/away_actions"
const OBSERVATIONS_DIR := "res://features/case_file/seed"
const CONSEQUENCES_DIR := "res://features/sim/consequences"

var diagnostics: Dictionary = {}    # StringName -> Diagnostic
var interventions: Dictionary = {}  # StringName -> Intervention
var away_actions: Dictionary = {}   # StringName -> AwayAction
var observations: Dictionary = {}   # StringName -> CaseEntry
var consequences: Dictionary = {}   # StringName -> ScheduledConsequence

func _ready() -> void:
    _load_dir(DIAGNOSTICS_DIR, diagnostics)
    _load_dir(INTERVENTIONS_DIR, interventions)
    _load_dir(AWAY_ACTIONS_DIR, away_actions)
    _load_dir(OBSERVATIONS_DIR, observations)
    _load_dir(CONSEQUENCES_DIR, consequences)

func _load_dir(dir_path: String, target: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        push_warning("Catalog: cannot open %s" % dir_path)
        return
    for fname: String in _filter_tres_filenames(Array(dir.get_files())):
        var res: Resource = ResourceLoader.load(dir_path.path_join(fname))
        if res == null:
            push_warning("Catalog: failed to load %s" % fname)
            continue
        if not (res is Diagnostic or res is Intervention or res is AwayAction or res is CaseEntry or res is ScheduledConsequence):
            push_warning("Catalog: unexpected resource type for %s" % fname)
            continue
        target[res.id] = res

static func _filter_tres_filenames(names: Array) -> Array:
    var out: Array = []
    for n: String in names:
        if n.ends_with(".tres") and not n.ends_with(".tres.uid") and not n.ends_with(".tres.import"):
            out.append(n)
    return out

func available_diagnostics(case_file: CaseFile) -> Array[Diagnostic]:
    var out: Array[Diagnostic] = []
    for d: Diagnostic in diagnostics.values():
        if case_file.has_all_tags(d.gate_tags): out.append(d)
    return out

func available_interventions(case_file: CaseFile) -> Array[Intervention]:
    var out: Array[Intervention] = []
    for i: Intervention in interventions.values():
        if case_file.has_all_tags(i.gate_tags): out.append(i)
    return out

func observation_candidates(client: ClientState, case_file: CaseFile) -> Array[CaseEntry]:
    var out: Array[CaseEntry] = []
    for e: CaseEntry in observations.values():
        if case_file.has_entry(e.id): continue
        if not e.require_state_satisfied(client): continue
        out.append(e)
    return out
