class_name OverskuddBar extends VBoxContainer

var _bar: ProgressBar
var _label: Label

func _ready() -> void:
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	add_child(_bar)
	_label = Label.new()
	add_child(_label)
	EventBus.overskudd_changed.connect(_on_overskudd_changed)
	_refresh()

func _on_overskudd_changed(_client_id: StringName, value: float) -> void:
	_bar.value = value
	_refresh()

func _refresh() -> void:
	if World.client == null: return
	_bar.value = World.client.overskudd
	_label.text = "Overskudd %.0f / %.0f (ceiling)" % [World.client.overskudd, World.client.overskudd_ceiling()]
