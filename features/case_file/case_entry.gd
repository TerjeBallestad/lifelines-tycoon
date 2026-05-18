class_name CaseEntry extends Resource

@export var id: StringName
@export_enum("Observation", "Diagnostic") var source: int = 0
@export var title: String
@export_multiline var body: String
@export var tags: Array[StringName] = []
@export var require_state: Dictionary = {}

func require_state_satisfied(client: ClientState) -> bool:
    for raw_key: StringName in require_state.keys():
        if not _clause_holds(raw_key, require_state[raw_key], client):
            return false
    return true

func _clause_holds(clause_key: StringName, value: Variant, client: ClientState) -> bool:
    var parts := String(clause_key).split("_")
    if parts.size() < 3:
        push_warning("CaseEntry: malformed clause '%s' — needs <scope>_<field>_<op>" % clause_key)
        return false
    var op: String = parts[parts.size() - 1]
    var scope: String = parts[0]
    var field: StringName = StringName("_".join(parts.slice(1, parts.size() - 1)))

    var lhs: Variant
    match scope:
        "needs":
            if not client.needs.has(field): return false
            lhs = client.needs[field]
        "cognitive":
            if not client.cognitive.has(field): return false
            lhs = client.cognitive[field]
        "skill":
            if not client.skills.has(field): return false
            lhs = client.skills[field]
        _:
            push_warning("CaseEntry: unknown scope '%s' in clause '%s'" % [scope, clause_key])
            return false

    match op:
        "lt":  return lhs < value
        "ge":  return lhs >= value
        _:
            push_warning("CaseEntry: unknown op '%s' in clause '%s'" % [op, clause_key])
            return false
