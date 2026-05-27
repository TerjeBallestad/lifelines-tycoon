class_name ScheduleQueue extends RefCounted

var _items: Array[ScheduledItem] = []
var _next_id := 1

func clear() -> void:
    _items = []
    _next_id = 1

func schedule_consequence_after(now_hours: float, consequence: ScheduledConsequence, source_id: StringName = &"world") -> ScheduledItem:
    return schedule_consequence_at(now_hours + max(0.0, consequence.due_after_hours), consequence, source_id)

func schedule_consequence_at(due_at_hours: float, consequence: ScheduledConsequence, source_id: StringName = &"world") -> ScheduledItem:
    var item := ScheduledItem.new()
    item.id = StringName("sched_%04d_%s" % [_next_id, String(consequence.id)])
    _next_id += 1
    item.due_at_hours = due_at_hours
    item.domain = consequence.domain
    item.source_id = source_id
    item.consequence_id = consequence.id
    _items.append(item)
    _sort_items()
    return item

func pending_count(domain: StringName = &"") -> int:
    if domain == &"":
        return _items.size()
    var count := 0
    for item: ScheduledItem in _items:
        if item.domain == domain:
            count += 1
    return count

func due_between(domain: StringName, start_hours: float, end_hours: float) -> Array[ScheduledItem]:
    var due: Array[ScheduledItem] = []
    var pending: Array[ScheduledItem] = []
    for item: ScheduledItem in _items:
        if item.domain == domain and item.due_at_hours <= end_hours:
            due.append(item)
        else:
            pending.append(item)
    _items = pending
    return due

func peek(domain: StringName = &"", limit: int = 0) -> Array[ScheduledItem]:
    var out: Array[ScheduledItem] = []
    for item: ScheduledItem in _items:
        if domain == &"" or item.domain == domain:
            out.append(item)
            if limit > 0 and out.size() >= limit:
                break
    return out

func _sort_items() -> void:
    _items.sort_custom(func(a: ScheduledItem, b: ScheduledItem) -> bool:
        return a.due_at_hours < b.due_at_hours
    )
