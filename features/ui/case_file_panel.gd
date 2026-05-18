class_name CaseFilePanel extends ScrollContainer

var _list: VBoxContainer

func _ready() -> void:
	_list = VBoxContainer.new()
	add_child(_list)
	EventBus.case_file_updated.connect(_on_updated)
	_rebuild()

func _on_updated(_entry_id: StringName) -> void:
	_rebuild()

func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	if World.case_file == null: return
	for entry: CaseEntry in World.case_file.entries:
		var icon := "📓" if entry.source == 0 else "🔍"
		var lbl := Label.new()
		lbl.text = "%s %s" % [icon, entry.title]
		lbl.tooltip_text = entry.body
		_list.add_child(lbl)
