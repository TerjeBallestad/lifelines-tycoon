class_name CaseFile extends RefCounted

var entries: Array[CaseEntry] = []
var tags: Dictionary = {}

func add_entry(entry: CaseEntry) -> void:
    if has_entry(entry.id): return
    entries.append(entry)
    for t: StringName in entry.tags:
        tags[t] = true

func has_entry(id: StringName) -> bool:
    for e: CaseEntry in entries:
        if e.id == id: return true
    return false

func has_all_tags(required: Array[StringName]) -> bool:
    for t: StringName in required:
        if not tags.has(t): return false
    return true
